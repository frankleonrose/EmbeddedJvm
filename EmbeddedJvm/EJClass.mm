//
//  EJClass.m
//  Pods
//
//  Created by Frank on 2014/2/28.
//
//

#import "EJClass.h"
#import "EJJvm.h"
#include <dlfcn.h>

@interface EJClass() {
    jclass cls;
    jmethodID ctor;
}
@property NSString *name;
@end

@implementation EJClass
- (id) initWithClassName:(NSString *)className env:(JNIEnv *)env error:(NSError * __autoreleasing *)error {
    self = [super init];
    if (self) {
        cls = env->FindClass([className cStringUsingEncoding:NSASCIIStringEncoding]);
        if (cls==nil) {
            [self clearJvmException:env];
            if (error!=nil) {
                NSString *msg = [NSString stringWithFormat:@"Could not find class \"%@\"", className];
                *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
            }
            self = nil;
        }
        else {
            self.name = className;
        }
    }
    return self;
}
- (jclass)theClass {
    return cls;
}
- (jobject) createObject:(JNIEnv *)env error:(NSError * __autoreleasing *)error signature:(NSString *)sig, ... {
    /* Variable arg list. http://www.cocoawithlove.com/2009/05/variable-argument-lists-in-cocoa.html */
    jmethodID ctorv = env->GetMethodID(cls, "<init>", [sig cStringUsingEncoding:NSUTF8StringEncoding]);
    if (ctorv==NULL) {
        [self clearJvmException:env];
        if (error!=nil) {
            NSString *msg = [NSString stringWithFormat:@"Could not find method: %@ constructor", sig];
            *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
        }
    }
    jobject obj = NULL;
    if (ctorv!=NULL) {
        va_list args;
        va_start(args, sig);
        obj = env->NewObjectV(cls, ctorv, args);
        va_end(args);

        if (obj==NULL) {
            [self clearJvmException:env];
            if (error!=nil) {
                NSString *msg = [NSString stringWithFormat:@"Failed to create object using %@ constructor", sig];
                *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
            }
        }
    }
    return obj;
}
- (jobject) createObject:(JNIEnv *)env error:(NSError * __autoreleasing *)error {
    if (ctor==NULL) {
        ctor = env->GetMethodID(cls, "<init>", "()V");
        if (ctor==NULL) {
            [self clearJvmException:env];
            if (error!=nil) {
                NSString *msg = @"Could not find method: default constructor";
                *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
            }
        }
    }
    jobject obj = NULL;
    if (ctor!=NULL) {
        obj = env->NewObject(cls, ctor);
        if (obj==NULL) {
            [self clearJvmException:env];
            if (error!=nil) {
                NSString *msg = @"Failed to create object using default constructor";
                *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
            }
        }
    }
    return obj;
}
- (jmethodID) getObjectMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError * __autoreleasing *)error {
    jmethodID m = env->GetMethodID(cls,
                                   [methodName cStringUsingEncoding:NSASCIIStringEncoding],
                                   [methodSignature cStringUsingEncoding:NSASCIIStringEncoding]);
    if (m==nil) {
        [self clearJvmException:env];
        if (error!=nil) {
            NSString *msg = [NSString stringWithFormat:@"Could not find object method \"%@\"", methodName];
            *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
        }
    }
    return m;
}
- (jmethodID) getStaticMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError * __autoreleasing *)error {
    jmethodID m = env->GetStaticMethodID(cls,
                                         [methodName cStringUsingEncoding:NSASCIIStringEncoding],
                                         [methodSignature cStringUsingEncoding:NSASCIIStringEncoding]);
    if (m==nil) {
        [self clearJvmException:env];
        if (error!=nil) {
            NSString *msg = [NSString stringWithFormat:@"Could not find static method \"%@\".", methodName];
            *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
        }
    }
    return m;
}
- (BOOL) registerNativeMethods:(JNINativeMethod *)methods count:(int)count env:(JNIEnv *)env error:(NSError * __autoreleasing *)error {
    jint ret = env->RegisterNatives(cls, methods, count);
    if (ret!=0) {
        [self clearJvmException:env];
        if (error!=nil) {
            NSString *msg = [NSString stringWithFormat:@"Could not register native methods for class \"%@\"", self.name];
            *error = [NSError errorWithDomain:msg code:0 userInfo:nil];
        }
    }
    return ret==0;
}
- (void) printMethods:(JNIEnv *)env {
    jclass methodClass = env->FindClass("java/lang/reflect/Method");
    jmethodID getGenericNameMethod = env->GetMethodID(methodClass, "toGenericString", "()Ljava/lang/String;");
    
    jclass classClass = env->FindClass("java/lang/Class");
    jmethodID getMethodsMethod = env->GetMethodID(classClass, "getMethods", "()[Ljava/lang/reflect/Method;");
    
    jobjectArray methods = (jobjectArray)env->CallObjectMethod(cls, getMethodsMethod);
    int mcount = env->GetArrayLength(methods);
    for (int i=0; i<mcount; ++i) {
        jobject method = env->GetObjectArrayElement(methods, i);
        jstring name = (jstring)env->CallObjectMethod(method, getGenericNameMethod);
        jboolean isCopy = 0;
        const char *cname = env->GetStringUTFChars(name, &isCopy);
        NSLog(@"%s", cname);
        if (isCopy) {
            env->ReleaseStringUTFChars(name, cname);
        }
    }
}
-(void)clearJvmException:(JNIEnv *)env {
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
}
@end
