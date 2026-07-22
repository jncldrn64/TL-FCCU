/*
 * Shared reflection helpers. Kept in one place so both call paths read objects the same
 * way & neither imports an HttpClient type. Public class (bootstrap-defined alongside the
 * other helpers); its methods are only called by HttpTap in the same package & loader, so
 * they stay package-private.
 */
package com.github.tlsandbox.agent;

import java.io.InputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;

public class Reflect {

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
