/*
 * TLHttpAgent: a java.lang.instrument agent that logs TLauncher's outbound HTTP.
 *
 * WHY this exists: TLauncher's requests go through Apache HttpClient, which ignores
 * -Dhttp.proxyHost & the HTTP_PROXY env vars (each client builds its own SSLContext
 * & connection chain), so mitmproxy captured zero. This agent loads before any app
 * class & instruments the request methods in-process, after the TLS decrypt, where
 * the payload is plain text. It never modifies a request or a response.
 *
 * WHY Advice, not MethodDelegation: the real session showed MethodDelegation binding
 * fails on these targets. @SuperCall can't resolve under RETRANSFORMATION (the method
 * is rewritten in place, so there is no "super" call to hand back), and with it the
 * whole delegation signature fails to bind. Advice injects its body inline instead of
 * delegating by signature, and works on inherited & overloaded methods. The diag log
 * from that session carried the exact IllegalArgumentException for both targets.
 *
 * It hooks:
 *   - InternalHttpClient.doExecute(), both HttpClient families the JVMs load:
 *       org.apache.hc.client5.http.impl.classic.InternalHttpClient  (5.x, launcher JVM)
 *       org.apache.http.impl.client.InternalHttpClient              (4.x, starter JVMs)
 *     The two JVM groups don't share a stack; covering one name alone misses the other.
 *   - by.gdev.http.download.impl.HttpServiceImpl: TLauncher's own download class, named
 *     by hand in the logs so it is never relocated. getRequestByUrlAndSave(String, Path)
 *     takes the URL as argument 0, no request object to reflect through. It is the
 *     shortest path to a real capture (it did the GET to starterUpdateV1.json).
 *
 * WHY the helper classes go on the bootstrap classpath: an Advice body is copied INTO
 * the target class, so every class it names has to be visible to the target's own
 * classloader. TLauncher loads these targets from its own jars, through classloaders
 * that need not be children of the agent's. Appending the agent jar to the bootstrap
 * search (the ancestor of every loader) before the first reference to a helper makes
 * parent-first delegation define AgentLogger, Reflect & HttpTap once, in the bootstrap
 * loader, so both premain and the inlined bodies see the same class. This is the fix
 * for the NoClassDefFoundError that would otherwise fire at runtime inside TLauncher.
 *
 * JAVA_TOOL_OPTIONS loads this into every JVM TLauncher starts, so it self-disables on
 * the Minecraft/mod JVM (not the audit target) & writes one log per process (PID in the
 * name) so three JVMs can't interleave a request block. run.sh aggregates them in start
 * order with a per-PID banner.
 *
 * Third-party: the fat JAR bundles Byte Buddy 1.14.18 (net.bytebuddy:byte-buddy),
 * Apache License 2.0. scripts/build-agent.sh adds a NOTICE for it to the JAR.
 *
 * Compiled against Byte Buddy only (no HttpClient on the classpath), so every
 * request/response object is read through reflection, never imported.
 */
package com.github.tlsandbox.agent;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.CodeSource;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.locks.ReentrantLock;
import java.util.jar.JarFile;

import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.bytecode.assign.Assigner;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.utility.JavaModule;

public class TLHttpAgent {

    static final String HC5 = "org.apache.hc.client5.http.impl.classic.InternalHttpClient";
    static final String HC4 = "org.apache.http.impl.client.InternalHttpClient";
    static final String HSVC = "by.gdev.http.download.impl.HttpServiceImpl";

    public static void premain(String args, Instrumentation inst) {
        // No log dir means the launcher wasn't run with -P. Return in silence; the
        // agent never aborts TLauncher's startup.
        String dir = System.getProperty("tl.intercept.dir");
        if (dir == null || dir.isEmpty()) {
            return;
        }
        // Put the helpers on the bootstrap classpath BEFORE the first reference to any
        // of them, so parent-first delegation defines them in the bootstrap loader &
        // the inlined Advice bodies can reach them from any target classloader.
        appendSelfToBootstrap(inst);
        try {
            AgentLogger.init(dir);
        } catch (Throwable t) {
            System.err.println("[tl-http-agent] logger init failed: " + t);
            return;
        }
        try {
            String cmd = System.getProperty("sun.java.command", "");
            AgentLogger.diag("premain in JVM: " + cmd);
            if (isGameJvm(cmd)) {
                // JAVA_TOOL_OPTIONS loads us into every JVM, Minecraft included. The
                // game is not the audit target & would flood the log with asset/skin
                // traffic, so self-disable here. The diag line records that we did.
                AgentLogger.diag("skipped: looks like the game/mod JVM, not instrumenting");
                AgentLogger.close();
                return;
            }
            new AgentBuilder.Default()
                    .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                    .with(new DiagListener())
                    .type(ElementMatchers.named(HC5).or(ElementMatchers.named(HC4)))
                    .transform((builder, type, loader, module, domain) ->
                            builder.visit(Advice.to(HttpAdvice.class).on(
                                    ElementMatchers.named("doExecute")
                                            .or(ElementMatchers.named("execute"))
                                            .and(ElementMatchers.not(ElementMatchers.isAbstract()))
                                            .and(ElementMatchers.not(ElementMatchers.isStatic())))))
                    .type(ElementMatchers.named(HSVC))
                    .transform((builder, type, loader, module, domain) ->
                            builder.visit(Advice.to(ServiceAdvice.class).on(
                                    ElementMatchers.isMethod()
                                            .and(ElementMatchers.isPublic())
                                            .and(ElementMatchers.not(ElementMatchers.isStatic()))
                                            .and(ElementMatchers.not(ElementMatchers.takesArguments(0)))
                                            .and(ElementMatchers.not(ElementMatchers.isDeclaredBy(Object.class))))))
                    .installOn(inst);
            Runtime.getRuntime().addShutdownHook(new Thread(AgentLogger::close));
        } catch (Throwable t) {
            // Any failure here disables interception but leaves TLauncher untouched.
            System.err.println("[tl-http-agent] disabled: " + t);
            try {
                AgentLogger.diag("disabled: " + t);
            } catch (Throwable ignore) {
                // nothing left to do
            }
        }
    }

    // Append our own jar to the bootstrap search. Best-effort: if it fails, the agent
    // still runs, it just can't reach helpers from a foreign target loader, & those
    // Advice bodies suppress their own throwables, so TLauncher is never broken.
    private static void appendSelfToBootstrap(Instrumentation inst) {
        try {
            CodeSource cs = TLHttpAgent.class.getProtectionDomain().getCodeSource();
            if (cs == null || cs.getLocation() == null) {
                return;
            }
            File jar = new File(cs.getLocation().toURI());
            if (jar.isFile()) {
                inst.appendToBootstrapClassLoaderSearch(new JarFile(jar));
            }
        } catch (Throwable t) {
            System.err.println("[tl-http-agent] bootstrap append failed: " + t);
        }
    }

    // Best-effort: is this the Minecraft/Forge/mod JVM rather than the starter or
    // launcher? These substrings come from the real process dump of a game launch.
    private static boolean isGameJvm(String cmd) {
        if (cmd == null) {
            return false;
        }
        String c = cmd.toLowerCase();
        return c.contains("bootstraplauncher")
                || c.contains("net.minecraft")
                || c.contains("--gamedir")
                || c.contains("--assetindex")
                || c.contains("minecraftforge")
                || c.contains("fml.")
                || c.contains("crash_assistant");
    }
}

/*
 * A Byte Buddy listener so "zero captures" is never ambiguous: it records, in the
 * diag log, every HttpClient/HttpService type the agent saw & every type it hooked.
 * If a target is shaded, its relocated name shows up here as SAW without a matching
 * HOOKED, which is the signal to add that name to the matcher. A binding or transform
 * failure lands as ERROR with the throwable, which is how the MethodDelegation break
 * was diagnosed in the first place.
 */
class DiagListener extends AgentBuilder.Listener.Adapter {

    private static boolean interesting(String typeName) {
        String low = typeName.toLowerCase();
        return low.contains("httpclient") || low.contains("httpservice")
                || low.contains("internalhttp");
    }

    @Override
    public void onDiscovery(String typeName, ClassLoader classLoader, JavaModule module, boolean loaded) {
        if (interesting(typeName)) {
            AgentLogger.diag("SAW " + typeName);
        }
    }

    @Override
    public void onTransformation(TypeDescription td, ClassLoader classLoader, JavaModule module,
                                 boolean loaded, DynamicType dynamicType) {
        AgentLogger.diag("HOOKED " + td.getName());
    }

    @Override
    public void onError(String typeName, ClassLoader classLoader, JavaModule module,
                        boolean loaded, Throwable throwable) {
        if (interesting(typeName)) {
            AgentLogger.diag("ERROR " + typeName + ": " + throwable);
        }
    }
}

/*
 * Advice for InternalHttpClient.doExecute() (both HttpClient families). The body is
 * inlined into the target method; it does nothing but hand the arguments, return value
 * & any throwable to HttpTap, which is bootstrap-visible. suppress = Throwable.class is
 * MANDATORY: without it an exception in this body would propagate into TLauncher. All
 * reading happens on exit, after the real call ran, so nothing here changes the request.
 */
class HttpAdvice {

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    static void exit(@Advice.AllArguments Object[] args,
                     @Advice.Return(typing = Assigner.Typing.DYNAMIC, readOnly = true) Object ret,
                     @Advice.Thrown Throwable thrown) {
        HttpTap.clientCall(args, ret, thrown);
    }
}

/*
 * Advice for HttpServiceImpl's public instance methods. Same contract: inline, suppress
 * throwables, read on exit only. The method name arrives through @Advice.Origin("#m").
 */
class ServiceAdvice {

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    static void exit(@Advice.Origin("#m") String method,
                     @Advice.AllArguments Object[] args,
                     @Advice.Return(typing = Assigner.Typing.DYNAMIC, readOnly = true) Object ret,
                     @Advice.Thrown Throwable thrown) {
        HttpTap.serviceCall(method, args, ret, thrown);
    }
}

/*
 * All the interception logic, out of the inlined Advice bodies & in one bootstrap-
 * visible place. It reads HttpClient request/response objects reflectively (no imported
 * type), never modifies them, and only reads a body that is repeatable (a streaming
 * body would be consumed by reading it, which could break the download). A four-line
 * request block is written under a single lock so it can never be split.
 */
class HttpTap {

    // InternalHttpClient.doExecute(HttpHost, request, HttpContext) -> response.
    static void clientCall(Object[] args, Object ret, Throwable thrown) {
        String method = "?";
        String host = "?";
        String path = "?";
        String bodyOut = "empty";
        long reqBytes = 0;

        try {
            Object request = findRequest(args);
            if (request != null) {
                method = methodOf(request);
                String[] hp = hostPath(request, args);
                host = hp[0];
                path = hp[1];
                byte[] rb = repeatableRequestBody(request);
                if (rb != null) {
                    reqBytes = rb.length;
                    bodyOut = Reflect.preview(rb);
                } else if (Reflect.invoke(request, "getEntity") != null) {
                    bodyOut = "<not repeatable>";
                }
            }
        } catch (Throwable t) {
            bodyOut = "<unreadable>";
        }

        int status = -1;
        long respBytes = -1;
        String bodyIn = thrown != null ? "<request-threw>" : "<not buffered>";
        if (thrown == null) {
            try {
                status = statusOf(ret);
                Object entity = Reflect.invoke(ret, "getEntity");
                if (entity != null) {
                    Object len = Reflect.invoke(entity, "getContentLength");
                    if (len instanceof Long) {
                        respBytes = (Long) len;
                    }
                    Object rep = Reflect.invoke(entity, "isRepeatable");
                    if (rep instanceof Boolean && (Boolean) rep) {
                        Object in = Reflect.invoke(entity, "getContent");
                        if (in instanceof InputStream) {
                            byte[] rb = Reflect.readStream((InputStream) in, 4096);
                            if (rb != null) {
                                bodyIn = Reflect.preview(rb);
                            }
                        }
                    } else {
                        bodyIn = "<not repeatable>";
                    }
                }
            } catch (Throwable ignore) {
                // Leave the defaults; never let response inspection break the call.
            }
        }

        AgentLogger.logBlock(method, host, path, status, reqBytes, respBytes, bodyOut, bodyIn);
    }

    static void serviceCall(String method, Object[] args, Object ret, Throwable thrown) {
        try {
            String url = firstUrl(args);
            if (url == null && thrown == null) {
                url = urlOf(ret);
            }
            if (url == null) {
                return; // no URL in this call; stay quiet rather than log noise
            }
            String host = "?";
            String path = "?";
            try {
                URI u = URI.create(url);
                if (u.getHost() != null) {
                    host = u.getHost();
                }
                path = u.getRawPath() != null ? u.getRawPath() : "/";
            } catch (Throwable ignore) {
                // leave placeholders
            }
            String bodyIn = thrown != null ? "<call-threw>" : respPreview(ret);
            AgentLogger.diag("HttpServiceImpl." + method + " -> " + url);
            // Label as GET so the report table (which greps HTTP verbs) picks it up;
            // a download service's requests are GETs.
            AgentLogger.logBlock("GET", host, path, -1, 0, -1, "empty", bodyIn);
        } catch (Throwable ignore) {
            // logging never breaks the call
        }
    }

    // --- request extraction, family-agnostic ---

    // The request is the argument that carries a request line or a method; HttpHost &
    // HttpContext (the other doExecute args) carry neither.
    private static Object findRequest(Object[] args) {
        if (args == null) {
            return null;
        }
        for (Object a : args) {
            if (a == null) {
                continue;
            }
            if (Reflect.hasMethod(a, "getRequestLine") || Reflect.hasMethod(a, "getMethod")) {
                return a;
            }
        }
        return null;
    }

    private static String methodOf(Object request) {
        // 5.x: request.getMethod(). 4.x: request.getRequestLine().getMethod().
        Object m = Reflect.invoke(request, "getMethod");
        if (m != null) {
            return Reflect.str(m);
        }
        Object line = Reflect.invoke(request, "getRequestLine");
        return Reflect.str(Reflect.invoke(line, "getMethod"));
    }

    // Returns {host, path}. 5.x exposes a full URI on the request; 4.x carries only the
    // path on the request line, with the host on the HttpHost argument.
    private static String[] hostPath(Object request, Object[] args) {
        String host = "?";
        String path = "?";
        Object uri = Reflect.invoke(request, "getUri");
        if (uri == null) {
            uri = Reflect.invoke(request, "getURI");
        }
        if (uri != null) {
            host = Reflect.str(Reflect.invoke(uri, "getHost"));
            path = Reflect.str(Reflect.invoke(uri, "getPath"));
        }
        if (isUnknown(path)) {
            Object line = Reflect.invoke(request, "getRequestLine");
            if (line != null) {
                path = Reflect.str(Reflect.invoke(line, "getUri"));
            }
        }
        if (isUnknown(host)) {
            host = hostFromArgs(args);
        }
        return new String[]{host, path};
    }

    // The HttpHost argument, if present, answers getHostName().
    private static String hostFromArgs(Object[] args) {
        if (args == null) {
            return "?";
        }
        for (Object a : args) {
            if (a == null) {
                continue;
            }
            Object h = Reflect.invoke(a, "getHostName");
            if (h != null) {
                return Reflect.str(h);
            }
        }
        return "?";
    }

    private static int statusOf(Object response) {
        // 5.x: getCode(). 4.x: getStatusLine().getStatusCode().
        Object code = Reflect.invoke(response, "getCode");
        if (code instanceof Integer) {
            return (Integer) code;
        }
        Object line = Reflect.invoke(response, "getStatusLine");
        Object sc = Reflect.invoke(line, "getStatusCode");
        if (sc instanceof Integer) {
            return (Integer) sc;
        }
        return -1;
    }

    // Read the request body only if the entity is already repeatable. A non-repeatable
    // entity would be consumed by reading it, and the constraint is: never read a body
    // that isn't repeatable, and never modify the request to make it so.
    private static byte[] repeatableRequestBody(Object request) {
        try {
            Object entity = Reflect.invoke(request, "getEntity");
            if (entity == null) {
                return null;
            }
            Object rep = Reflect.invoke(entity, "isRepeatable");
            if (!(rep instanceof Boolean) || !((Boolean) rep)) {
                return null;
            }
            Object in = Reflect.invoke(entity, "getContent");
            if (in instanceof InputStream) {
                return Reflect.readStream((InputStream) in, 4096);
            }
            return null;
        } catch (Throwable t) {
            return null;
        }
    }

    // --- URL extraction for HttpServiceImpl ---

    private static String firstUrl(Object[] args) {
        if (args == null) {
            return null;
        }
        for (Object a : args) {
            String u = urlOf(a);
            if (u != null) {
                return u;
            }
        }
        return null;
    }

    // A URL is the value itself, or reachable via getUrl()/getUri() on a small dto.
    private static String urlOf(Object o) {
        if (o == null) {
            return null;
        }
        String s = asUrl(o);
        if (s != null) {
            return s;
        }
        s = asUrl(Reflect.invoke(o, "getUrl"));
        if (s != null) {
            return s;
        }
        return asUrl(Reflect.invoke(o, "getUri"));
    }

    private static String asUrl(Object o) {
        if (o == null) {
            return null;
        }
        String s = String.valueOf(o);
        if (s.startsWith("http://") || s.startsWith("https://")) {
            return s;
        }
        return null;
    }

    // Preview a return value only if it is already in memory (String or byte[]).
    // Never read an InputStream return: that would consume the download.
    private static String respPreview(Object resp) {
        if (resp instanceof CharSequence) {
            return Reflect.preview(resp.toString().getBytes(StandardCharsets.UTF_8));
        }
        if (resp instanceof byte[]) {
            return Reflect.preview((byte[]) resp);
        }
        return "<via HttpServiceImpl>";
    }

    private static boolean isUnknown(String s) {
        return s == null || s.isEmpty() || "?".equals(s) || "null".equals(s);
    }
}

/*
 * Shared reflection helpers. Kept in one place so both call paths read objects the same
 * way & neither imports an HttpClient type.
 */
class Reflect {

    static Object invoke(Object target, String name) {
        if (target == null) {
            return null;
        }
        try {
            Method m = target.getClass().getMethod(name);
            m.setAccessible(true);
            return m.invoke(target);
        } catch (Throwable t) {
            return null;
        }
    }

    static boolean hasMethod(Object target, String name) {
        if (target == null) {
            return false;
        }
        try {
            target.getClass().getMethod(name);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    static byte[] readStream(InputStream in, int max) {
        try {
            byte[] buf = new byte[max];
            int total = 0;
            int r;
            while (total < max && (r = in.read(buf, total, max - total)) != -1) {
                total += r;
            }
            byte[] out = new byte[total];
            System.arraycopy(buf, 0, out, 0, total);
            return out;
        } catch (Throwable t) {
            return null;
        }
    }

    static String str(Object o) {
        return o == null ? "?" : String.valueOf(o);
    }

    static String preview(byte[] b) {
        if (b == null || b.length == 0) {
            return "empty";
        }
        int n = Math.min(b.length, 4096);
        String s = new String(b, 0, n, StandardCharsets.UTF_8)
                .replace("\r", " ").replace("\n", " ");
        return b.length > 4096 ? s + " ...[truncated " + b.length + "B]" : s;
    }
}

/*
 * Thread-safe append-only writer, one intercept log & one diag log per process (the
 * PID is in the file name). AgentLogger is thread-safe within a JVM, not across
 * processes, so each JVM writes its own files & run.sh concatenates them in start order;
 * that keeps a four-line request block whole instead of interleaving three JVMs into one
 * file. logBlock writes all four lines under one lock so a block is never split even by
 * two concurrent requests inside the same JVM.
 */
class AgentLogger {

    private static PrintWriter out;
    private static PrintWriter diagOut;
    private static final ReentrantLock LOCK = new ReentrantLock();
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("HH:mm:ss.SSS");

    static void init(String dir) throws IOException {
        long pid = ProcessHandle.current().pid();
        out = new PrintWriter(new BufferedWriter(
                new FileWriter(dir + "/http-intercept-" + pid + ".log", true)));
        diagOut = new PrintWriter(new BufferedWriter(
                new FileWriter(dir + "/agent-diag-" + pid + ".log", true)));
    }

    // The four-line request block the report parser reads: method line, status line,
    // then the two body lines, in that exact order & format. Written under one lock.
    static void logBlock(String method, String host, String path, int status,
                         long reqBytes, long respBytes, String bodyOut, String bodyIn) {
        LOCK.lock();
        try {
            if (out != null) {
                String ts = "[" + LocalTime.now().format(TS) + "] ";
                out.println(ts + method + " " + host + " " + path);
                out.println(ts + "STATUS: " + status + " REQ: " + reqBytes + " RESP: " + respBytes);
                out.println(ts + "BODY_OUT: " + bodyOut);
                out.println(ts + "BODY_IN: " + bodyIn);
                out.flush();
            }
        } finally {
            LOCK.unlock();
        }
    }

    static void diag(String s) {
        LOCK.lock();
        try {
            if (diagOut != null) {
                diagOut.println("[" + LocalTime.now().format(TS) + "] " + s);
                diagOut.flush();
            }
        } finally {
            LOCK.unlock();
        }
    }

    static void close() {
        LOCK.lock();
        try {
            if (out != null) {
                out.close();
            }
            if (diagOut != null) {
                diagOut.close();
            }
        } finally {
            LOCK.unlock();
        }
    }
}
