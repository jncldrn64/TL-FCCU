/*
 * Advice for HttpServiceImpl's public instance methods. Same contract as HttpAdvice:
 * inline, suppress throwables, read on exit only. The method name arrives through
 * @Advice.Origin("#m").
 *
 * public because premain (app loader) references ServiceAdvice.class while it is defined
 * by the bootstrap loader.
 */
package com.github.tlsandbox.agent;

import net.bytebuddy.asm.Advice;
import net.bytebuddy.implementation.bytecode.assign.Assigner;

public class ServiceAdvice {

    @Advice.OnMethodExit(onThrowable = Throwable.class, suppress = Throwable.class)
    static void exit(@Advice.Origin("#m") String method,
                     @Advice.AllArguments Object[] args,
                     @Advice.Return(typing = Assigner.Typing.DYNAMIC, readOnly = true) Object ret,
                     @Advice.Thrown Throwable thrown) {
        HttpTap.serviceCall(method, args, ret, thrown);
    }
}
