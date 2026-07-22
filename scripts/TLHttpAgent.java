/*
 * TLHttpAgent: a java.lang.instrument agent that logs TLauncher's outbound HTTP.
 *
 * WHY this exists: TLauncher's requests go through Apache HttpClient5, which ignores
 * -Dhttp.proxyHost & the HTTP_PROXY env vars (each client builds its own SSLContext
 * & connection chain), so mitmproxy captured zero. This agent loads before any app
 * class & instruments the request classes in-process, after the TLS decrypt, where
 * the payload is plain text. It never modifies a request or a response.
 *
 * It hooks two classes:
 *   - org.apache.hc.client5.http.impl.classic.InternalHttpClient.execute(): the
 *     standard HttpClient5 entry point. Missed when the jar ships a shaded copy under
 *     a relocated package name (the diagnostic log shows the real name when that
 *     happens).
 *   - by.gdev.http.download.impl.HttpServiceImpl: TLauncher's own download class,
 *     named by hand in the logs, so it is not relocated. Its methods don't share
 *     HttpClient5's execute() signature, so it gets its own generic URL extractor.
 *
 * JAVA_TOOL_OPTIONS loads this into every JVM TLauncher starts, so it self-disables
 * on the Minecraft/mod JVM (not the audit target) & writes one log per process (PID
 * in the name) so three JVMs can't interleave a request block.
 *
 * Third-party: the fat JAR bundles Byte Buddy 1.14.18 (net.bytebuddy:byte-buddy),
 * Apache License 2.0. scripts/build-agent.sh adds a NOTICE for it to the JAR.
 *
 * Compiled against Byte Buddy only (no HttpClient5 on the classpath), so every
 * request/response object is read through reflection, never imported.
 */
package com.github.tlsandbox.agent;

import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.Callable;
import java.util.concurrent.locks.ReentrantLock;

import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.implementation.MethodDelegation;
import net.bytebuddy.implementation.bind.annotation.AllArguments;
import net.bytebuddy.implementation.bind.annotation.Origin;
import net.bytebuddy.implementation.bind.annotation.RuntimeType;
import net.bytebuddy.implementation.bind.annotation.SuperCall;
import net.bytebuddy.matcher.ElementMatchers;
import net.bytebuddy.utility.JavaModule;

public class TLHttpAgent {

    public static void premain(String args, Instrumentation inst) {
        // No log dir means the launcher wasn't run with -P. Return in silence; the
        // agent never aborts TLauncher's startup.
        String dir = System.getProperty("tl.intercept.dir");
        if (dir == null || dir.isEmpty()) {
            return;
        }
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
                    .type(ElementMatchers.named(
                            "org.apache.hc.client5.http.impl.classic.InternalHttpClient"))
                    .transform((builder, type, loader, module, domain) ->
                            builder.method(ElementMatchers.named("execute"))
                                    .intercept(MethodDelegation.to(HttpInterceptor.class)))
                    .type(ElementMatchers.named(
                            "by.gdev.http.download.impl.HttpServiceImpl"))
                    .transform((builder, type, loader, module, domain) ->
                            builder.method(ElementMatchers.isPublic()
                                    .and(ElementMatchers.not(ElementMatchers.isStatic()))
                                    .and(ElementMatchers.not(ElementMatchers.takesArguments(0)))
                                    .and(ElementMatchers.not(ElementMatchers.isDeclaredBy(Object.class))))
                                    .intercept(MethodDelegation.to(HttpServiceInterceptor.class)))
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
 * If InternalHttpClient is shaded, its relocated name shows up here as SAW without a
 * matching HOOKED, which is the signal to add that name to the matcher.
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
 * Delegation target for InternalHttpClient.execute(). Byte Buddy passes the original
 * call as a Callable & the arguments as an Object[]. Everything about the HttpClient5
 * request/response is read reflectively. Any instrumentation error is swallowed; the
 * real call still runs & its own exceptions still propagate to TLauncher unchanged.
 */
class HttpInterceptor {

    @RuntimeType
    public static Object intercept(@SuperCall Callable<?> superCall,
                                   @AllArguments Object[] args) throws Exception {
        String method = "?";
        String host = "?";
        String path = "?";
        String bodyOut = "empty";
        long reqBytes = 0;

        try {
            Object request = findRequest(args);
            if (request != null) {
                method = str(invoke(request, "getMethod"));
                Object uri = invoke(request, "getUri");
                if (uri != null) {
                    host = str(invoke(uri, "getHost"));
                    path = str(invoke(uri, "getPath"));
                }
                byte[] rb = readRequestBody(request);
                if (rb != null) {
                    reqBytes = rb.length;
                    bodyOut = preview(rb);
                }
            }
        } catch (Throwable t) {
            bodyOut = "<unreadable>";
        }

        // Run the real request. If it throws, that's TLauncher's own failure: log it,
        // then rethrow so TLauncher's error handling behaves exactly as before.
        Object response;
        try {
            response = superCall.call();
        } catch (Exception e) {
            safeLog(method, host, path, -1, reqBytes, -1, bodyOut, "<request-threw>");
            throw e;
        }

        int status = -1;
        long respBytes = -1;
        String bodyIn = "<not buffered>";
        try {
            Object code = invoke(response, "getCode");
            if (code instanceof Integer) {
                status = (Integer) code;
            }
            Object entity = invoke(response, "getEntity");
            if (entity != null) {
                Object len = invoke(entity, "getContentLength");
                if (len instanceof Long) {
                    respBytes = (Long) len;
                }
                // Only read a response that can be re-read. A streaming response would
                // be consumed by reading it here, which could break TLauncher; skip it.
                Object rep = invoke(entity, "isRepeatable");
                if (rep instanceof Boolean && (Boolean) rep) {
                    Object in = invoke(entity, "getContent");
                    if (in instanceof InputStream) {
                        byte[] rb = readStream((InputStream) in, 4096);
                        if (rb != null) {
                            bodyIn = preview(rb);
                        }
                    }
                }
            }
        } catch (Throwable ignore) {
            // Leave the defaults; never let response inspection break the call.
        }

        safeLog(method, host, path, status, reqBytes, respBytes, bodyOut, bodyIn);
        return response;
    }

    // Read the request entity without consuming it for TLauncher: if it isn't
    // repeatable, wrap it in a BufferedHttpEntity & set it back on the request, so
    // the buffered copy feeds both our read & the real send.
    private static byte[] readRequestBody(Object request) {
        try {
            Object entity = invoke(request, "getEntity");
            if (entity == null) {
                return null;
            }
            Object repeatable = entity;
            Object rep = invoke(entity, "isRepeatable");
            if (rep instanceof Boolean && !((Boolean) rep)) {
                ClassLoader cl = request.getClass().getClassLoader();
                Class<?> httpEntity = Class.forName(
                        "org.apache.hc.core5.http.HttpEntity", false, cl);
                Class<?> buffered = Class.forName(
                        "org.apache.hc.core5.http.io.entity.BufferedHttpEntity", false, cl);
                Object wrapped = buffered.getConstructor(httpEntity).newInstance(entity);
                request.getClass().getMethod("setEntity", httpEntity).invoke(request, wrapped);
                repeatable = wrapped;
            }
            Object in = invoke(repeatable, "getContent");
            if (in instanceof InputStream) {
                return readStream((InputStream) in, 4096);
            }
            return null;
        } catch (Throwable t) {
            return new byte[0];
        }
    }

    private static Object findRequest(Object[] args) {
        if (args == null) {
            return null;
        }
        for (Object a : args) {
            if (a == null) {
                continue;
            }
            String cn = a.getClass().getName().toLowerCase();
            if (cn.contains("request") && hasMethod(a, "getMethod")) {
                return a;
            }
        }
        return null;
    }

    private static void safeLog(String m, String h, String p, int status,
                                long req, long resp, String bodyOut, String bodyIn) {
        try {
            AgentLogger.logRequest(m, h, p);
            AgentLogger.logStatus(status, req, resp);
            AgentLogger.logBody("BODY_OUT", bodyOut);
            AgentLogger.logBody("BODY_IN", bodyIn);
        } catch (Throwable ignore) {
            // Logging must never break the call.
        }
    }

    // --- reflection helpers, shared with HttpServiceInterceptor via Reflect ---

    private static Object invoke(Object t, String n) { return Reflect.invoke(t, n); }
    private static boolean hasMethod(Object t, String n) { return Reflect.hasMethod(t, n); }
    private static byte[] readStream(InputStream in, int max) { return Reflect.readStream(in, max); }
    private static String str(Object o) { return Reflect.str(o); }
    private static String preview(byte[] b) { return Reflect.preview(b); }
}

/*
 * Delegation target for HttpServiceImpl's methods. HttpServiceImpl is TLauncher's own
 * download class & its methods don't share HttpClient5's execute() signature, so this
 * has its own extraction: it scans the arguments (and the return value) for a URL,
 * & logs it as a GET, since a download service's requests are GETs. It never reads a
 * streaming return value (that would consume it) & never modifies anything.
 */
class HttpServiceInterceptor {

    @RuntimeType
    public static Object intercept(@Origin Method method,
                                   @SuperCall Callable<?> superCall,
                                   @AllArguments Object[] args) throws Exception {
        String url = firstUrl(args);

        Object response;
        try {
            response = superCall.call();
        } catch (Exception e) {
            if (url != null) {
                logUrl(method.getName(), url, "<call-threw>");
            }
            throw e;
        }

        if (url == null) {
            url = urlOf(response);
        }
        if (url != null) {
            logUrl(method.getName(), url, respPreview(response));
        }
        return response;
    }

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

    // A URL is either the value itself, or reachable via a getUrl()/getUri() on a
    // small request/dto object.
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

    private static void logUrl(String javaMethod, String url, String bodyIn) {
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
        try {
            AgentLogger.diag("HttpServiceImpl." + javaMethod + " -> " + url);
            // Label as GET so the report table (which greps HTTP verbs) picks it up;
            // a download service's requests are GETs.
            AgentLogger.logRequest("GET", host, path);
            AgentLogger.logStatus(-1, 0, -1);
            AgentLogger.logBody("BODY_OUT", "empty");
            AgentLogger.logBody("BODY_IN", bodyIn == null ? "<via HttpServiceImpl>" : bodyIn);
        } catch (Throwable ignore) {
            // logging never breaks the call
        }
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
}

/*
 * Shared reflection helpers. Kept in one place so both interceptors read objects the
 * same way & neither imports an HttpClient5 type.
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
 * processes, so each JVM writes its own files & run.sh concatenates them; that keeps
 * a four-line request block whole instead of interleaving three JVMs into one file.
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

    static void logRequest(String method, String host, String path) {
        line(out, method + " " + host + " " + path);
    }

    static void logStatus(int status, long reqBytes, long respBytes) {
        line(out, "STATUS: " + status + " REQ: " + reqBytes + " RESP: " + respBytes);
    }

    static void logBody(String tag, String body) {
        line(out, tag + ": " + body);
    }

    static void diag(String s) {
        line(diagOut, s);
    }

    private static void line(PrintWriter w, String s) {
        LOCK.lock();
        try {
            if (w != null) {
                w.println("[" + LocalTime.now().format(TS) + "] " + s);
                w.flush();
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
