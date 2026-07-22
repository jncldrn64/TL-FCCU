/*
 * All the interception logic, out of the inlined Advice bodies & in one bootstrap-
 * visible place. It reads HttpClient request/response objects reflectively (no imported
 * type), never modifies them, and only reads a body that is repeatable (a streaming
 * body would be consumed by reading it, which could break the download). A four-line
 * request block is written under a single lock so it can never be split.
 *
 * public, with public clientCall/serviceCall, because the inlined Advice bodies run in
 * the target class's loader (TLauncher's), which reaches this class only across the
 * bootstrap loader boundary, where package-private access is denied.
 */
package com.github.tlsandbox.agent;

import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;

public class HttpTap {

    // InternalHttpClient.doExecute(HttpHost, request, HttpContext) -> response.
    public static void clientCall(Object[] args, Object ret, Throwable thrown) {
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

    public static void serviceCall(String method, Object[] args, Object ret, Throwable thrown) {
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
