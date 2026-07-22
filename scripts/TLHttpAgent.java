/*
 * TLHttpAgent: a java.lang.instrument agent that logs TLauncher's outbound HTTP.
 *
 * WHY this exists: TLauncher's requests go through Apache HttpClient (4.x in the starter
 * JVMs, 5.x in the launcher JVM), which ignores -Dhttp.proxyHost & the HTTP_PROXY env
 * vars (each client builds its own SSLContext & connection chain), so mitmproxy captured
 * zero. This agent loads before any app class & instruments the request methods
 * in-process, after the TLS decrypt, where the payload is plain text. It never modifies
 * a request or a response.
 *
 * WHY Advice, not MethodDelegation: MethodDelegation's @SuperCall can't resolve under
 * RETRANSFORMATION (the method is rewritten in place, so there is no "super" call to hand
 * back), and its failure drags the whole delegation signature down. Advice injects its
 * body inline instead, and works on inherited & overloaded methods.
 *
 * WHY the helpers are public & on the bootstrap classpath: an Advice body is copied INTO
 * the target class, so every class it names has to be visible to the target's own
 * classloader. TLauncher loads the targets from its own jars, through classloaders that
 * need not be children of the agent's. Appending the agent jar to the bootstrap search
 * (the ancestor of every loader) before the first reference to a helper makes parent-
 * first delegation define AgentLogger, HttpTap & the rest once, in the bootstrap loader.
 * But premain itself runs in the app loader, and a class in one loader can't reach a
 * package-private member of the same-named class in another loader (they are different
 * runtime packages): that is the IllegalAccessError the second real session hit. So the
 * helpers, & the members crossed at that boundary, are public. Each helper is its own
 * top-level class, not a nested one, so there is no nest host to resolve twice across the
 * two loaders.
 *
 * JAVA_TOOL_OPTIONS loads this into every JVM TLauncher starts, so it self-disables on
 * the Minecraft/mod JVM (not the audit target) BEFORE it touches the bootstrap classpath,
 * so it never forces Byte Buddy & its ASM ahead of Forge's own ASM there. It writes one
 * log per process (PID in the name); run.sh aggregates them in start order.
 *
 * Third-party: the fat JAR bundles Byte Buddy 1.14.18 (net.bytebuddy:byte-buddy),
 * Apache License 2.0. scripts/build-agent.sh adds a NOTICE for it to the JAR.
 *
 * Compiled against Byte Buddy only (no HttpClient on the classpath), so every
 * request/response object is read through reflection, never imported.
 */
package com.github.tlsandbox.agent;

import java.io.File;
import java.lang.instrument.Instrumentation;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.security.CodeSource;
import java.time.LocalTime;
import java.util.jar.JarFile;

import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.asm.Advice;
import net.bytebuddy.matcher.ElementMatchers;

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
        // Decide whether to instrument BEFORE touching the bootstrap classpath or loading
        // any helper. JAVA_TOOL_OPTIONS loads us into every JVM, Minecraft & Forge
        // included. The game is not the audit target, and appending our fat JAR (Byte
        // Buddy + ASM) to the bootstrap loader there would put our ASM ahead of Forge's
        // own. So self-disable first, & record the skip with a plain file write, not the
        // AgentLogger helper (which we have deliberately not made bootstrap-visible yet).
        String cmd = System.getProperty("sun.java.command", "");
        if (isGameJvm(cmd)) {
            writeSkippedNote(dir, cmd);
            return;
        }
        // Now, & only now, put the helpers on the bootstrap classpath, before the first
        // reference to any of them.
        appendSelfToBootstrap(inst);
        try {
            AgentLogger.init(dir);
        } catch (Throwable t) {
            System.err.println("[tl-http-agent] logger init failed: " + t);
            return;
        }
        try {
            AgentLogger.diag("premain in JVM: " + cmd);
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

    // Record the game-JVM skip without the AgentLogger helper (we haven't put it on the
    // bootstrap classpath, on purpose). A plain append keeps the aggregated agent-diag.log
    // honest about which JVMs the agent chose not to instrument. Best-effort.
    private static void writeSkippedNote(String dir, String cmd) {
        long pid = ProcessHandle.current().pid();
        String line = "[" + LocalTime.now() + "] skipped: game/mod JVM, not instrumenting: "
                + cmd + System.lineSeparator();
        try {
            Files.write(Paths.get(dir, "agent-diag-" + pid + ".log"),
                    line.getBytes(StandardCharsets.UTF_8),
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (Throwable t) {
            System.err.println("[tl-http-agent] skipped game JVM (diag write failed: " + t + ")");
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
