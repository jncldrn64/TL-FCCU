/*
 * Thread-safe append-only writer, one intercept log & one diag log per process (the
 * PID is in the file name). AgentLogger is thread-safe within a JVM, not across
 * processes, so each JVM writes its own files & run.sh concatenates them in start order;
 * that keeps a four-line request block whole instead of interleaving three JVMs into one
 * file. logBlock writes all four lines under one lock so a block is never split even by
 * two concurrent requests inside the same JVM.
 *
 * public, with public members, because it is defined by the bootstrap loader (the agent
 * jar is appended there) while premain runs in the app loader: a package-private member
 * would be denied across that loader boundary.
 */
package com.github.tlsandbox.agent;

import java.io.BufferedWriter;
import java.io.FileWriter;
import java.io.IOException;
import java.io.PrintWriter;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.concurrent.locks.ReentrantLock;

public class AgentLogger {

    private static PrintWriter out;
    private static PrintWriter diagOut;
    private static final ReentrantLock LOCK = new ReentrantLock();
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("HH:mm:ss.SSS");

    public static void init(String dir) throws IOException {
        long pid = ProcessHandle.current().pid();
        out = new PrintWriter(new BufferedWriter(
                new FileWriter(dir + "/http-intercept-" + pid + ".log", true)));
        diagOut = new PrintWriter(new BufferedWriter(
                new FileWriter(dir + "/agent-diag-" + pid + ".log", true)));
    }

    // The four-line request block the report parser reads: method line, status line,
    // then the two body lines, in that exact order & format. Written under one lock.
    public static void logBlock(String method, String host, String path, int status,
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

    public static void diag(String s) {
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

    public static void close() {
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
