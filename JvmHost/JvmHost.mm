//
//  JvmHost.mm
//  JvmHost
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import "jni.h"
#import "JvmHost.h"


@interface JvmHost ()
@end

@implementation JvmHost
- (JvmHost*) init {
    if (self) {
        //
        
    }
    return self;
}

- (JvmHost*) initWithOptions:(NSDictionary*)options {
    if (self) {
        // R"(Maybe use raw strings?)";
        JavaVMInitArgs vm_args; /* JDK/JRE 6 VM initialization arguments */
        JavaVMOption* options = new JavaVMOption[1];
        options[0].optionString = const_cast<char *>([@"-Djava.class.path=/usr/lib/java" cStringUsingEncoding:NSASCIIStringEncoding]);
        vm_args.version = JNI_VERSION_1_6;
        vm_args.nOptions = 1;
        vm_args.options = options;
        vm_args.ignoreUnrecognized = false;
        /* load and initialize a Java VM, return a JNI interface pointer in env */
        JNI_CreateJavaVM(&jvm, (void**)&env, &vm_args);
        delete options;
    }
    return self;
}

- (void)destroy {
    /* We are done. */
    jvm->DestroyJavaVM();
}

- (void) invoke:(NSString*)method withSignature:(NSString*)signature {
    /* invoke the Main.test method using the JNI */
    jclass cls = env->FindClass("Main");
    jmethodID mid = env->GetStaticMethodID(cls, "test", "(I)V");
    env->CallStaticVoidMethod(cls, mid, 100);
}

@end
