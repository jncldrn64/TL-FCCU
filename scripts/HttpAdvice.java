/*
 * Advice for InternalHttpClient.doExecute() (both HttpClient families). The body is
 * inlined into the target method; it does nothing but hand the arguments, return value
 * & any throwable to HttpTap, which is bootstrap-visible. suppress = Throwable.class is
 * MANDATORY: without it an exception in this body would propagate into TLauncher. All
 * reading happens on exit, after the real call ran, so nothing here changes the request.
 *
 * public because premain (app loader) references HttpAdvice.class while it is defined by
 * the bootstrap loader.
 */
package com.github.tlsandbox.agent;

import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

public class HttpAdvice {

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    static void exit(@Advice.AllArguments Object[] args,
                     @Advice.Return(typing = Assigner.Typing.DYNAMIC, readOnly = true) Object ret,
                     @Advice.Thrown Throwable thrown) {
        HttpTap.clientCall(args, ret, thrown);
    }
}
