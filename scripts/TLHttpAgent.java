/*
 * TLHttpAgent: a java.lang.instrument agent that logs TLauncher's outbound HTTP.
 *
 * WHY this exists: TLauncher's requests go through Apache HttpClient5, which ignores
 * -Dhttp.proxyHost & the HTTP_PROXY env vars (each client builds its own SSLContext
 * & connection chain), so mitmproxy captured zero. This agent loads before any app
 * class & instruments InternalHttpClient.execute() in-process, after the TLS decrypt,
 * where the payload is plain text. It never modifies a request or a response.
 *
 * Third-party: the fat JAR bundles Byte Buddy 1.14.18 (net.bytebuddy:byte-buddy),
 * Apache License 2.0. scripts/build-agent.sh adds a NOTICE for it to the JAR.
 *
 * Compiled against Byte Buddy only (no HttpClient5 on the classpath), so every
 * HttpClient5 object is read through reflection, never imported.
 */
package com.github.tlsandbox.agent;

import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.lang.instrument.Instrumentation;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.Callable;
import java.util.concurrent.locks.ReentrantLock;

import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.implementation.MethodDelegation;
import net.bytebuddy.implementation.bind.annotation.AllArguments;
import net.bytebuddy.implementation.bind.annotation.RuntimeType;
import net.bytebuddy.implementation.bind.annotation.SuperCall;
import net.bytebuddy.matcher.ElementMatchers;

public class TLHttpAgent {

    public static void premain(String args, Instrumentation inst) {
        // No log path means the launcher wasn't run with -P. Return in silence;
        // the agent never aborts TLauncher's startup.
        String logPath = System.getProperty("tl.intercept.log");
        if (logPath == null || logPath.isEmpty()) {
            return;
        }
        try {
            AgentLogger.init(logPath);
            new AgentBuilder.Default()
                    .with(AgentBuilder.RedefinitionStrategy.RETRANSFORMATION)
                    .type(ElementMatchers.named(
                            "org.apache.hc.client5.http.impl.classic.InternalHttpClient"))
                    .transform((builder, type, loader, module, domain) ->
                            builder.method(ElementMatchers.named("execute"))
                                    .intercept(MethodDelegation.to(HttpInterceptor.class)))
                    .installOn(inst);
            Runtime.getRuntime().addShutdownHook(new Thread(AgentLogger::close));
        } catch (Throwable t) {
            // Any failure here disables interception but leaves TLauncher untouched.
            System.err.println("[tl-http-agent] disabled: " + t);
        }
    }
}

/*
 * The delegation target. Byte Buddy passes the original call as a Callable & the
 * arguments as an Object[]. Everything about the HttpClient5 request/response is
 * read reflectively. Any instrumentation error is swallowed; the real call still
 * runs & its own exceptions still propagate to TLauncher unchanged.
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

    // --- reflection helpers ---

    private static Object invoke(Object target, String name) {
        try {
            Method m = target.getClass().getMethod(name);
            m.setAccessible(true);
            return m.invoke(target);
        } catch (Throwable t) {
            return null;
        }
    }

    private static boolean hasMethod(Object target, String name) {
        try {
            target.getClass().getMethod(name);
            return true;
        } catch (Throwable t) {
            return false;
        }
    }

    private static byte[] readStream(InputStream in, int max) {
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

    private static String str(Object o) {
        return o == null ? "?" : String.valueOf(o);
    }

    private static String preview(byte[] b) {
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
 * Thread-safe append-only writer. The agent runs on TLauncher's own request threads,
 * so every line goes out under a lock & is flushed, so a crash keeps what it had.
 */
class AgentLogger {

    private static PrintWriter out;
    private static final ReentrantLock LOCK = new ReentrantLock();
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("HH:mm:ss.SSS");

    static void init(String path) throws IOException {
        out = new PrintWriter(new BufferedWriter(new FileWriter(path, true)));
    }

    static void logRequest(String method, String host, String path) {
        line(method + " " + host + " " + path);
    }

    static void logStatus(int status, long reqBytes, long respBytes) {
        line("STATUS: " + status + " REQ: " + reqBytes + " RESP: " + respBytes);
    }

    static void logBody(String tag, String body) {
        line(tag + ": " + body);
    }

    private static void line(String s) {
        LOCK.lock();
        try {
            if (out != null) {
                out.println("[" + LocalTime.now().format(TS) + "] " + s);
                out.flush();
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
        } finally {
            LOCK.unlock();
        }
    }
}
