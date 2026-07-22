/*
 * A Byte Buddy listener so "zero captures" is never ambiguous: it records, in the
 * diag log, every HttpClient/HttpService type the agent saw & every type it hooked.
 * If a target is shaded, its relocated name shows up here as SAW without a matching
 * HOOKED, which is the signal to add that name to the matcher. A binding or transform
 * failure lands as ERROR with the throwable, which is how the MethodDelegation break
 * was diagnosed.
 *
 * public because premain (app loader) instantiates it while it is defined by the
 * bootstrap loader.
 */
package com.github.tlsandbox.agent;

import net.bytebuddy.agent.builder.AgentBuilder;
import net.bytebuddy.description.type.TypeDescription;
import net.bytebuddy.dynamic.DynamicType;
import net.bytebuddy.utility.JavaModule;

public class DiagListener extends AgentBuilder.Listener.Adapter {

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
