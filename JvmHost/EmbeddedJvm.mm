//
//  EmbeddedJvm.mm
//  EmbeddedJvm
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import "EmbeddedJvm.h"
#include <dlfcn.h>

typedef jint (*JNI_GetDefaultJavaVMInitArgs_t)(void *args);
typedef jint (*JNI_CreateJavaVM_t)(JavaVM **pvm, void **penv, void *args);
typedef jint (*JNI_GetCreatedJavaVMs_t)(JavaVM **, jsize, jsize *);
//typedef jint (*jni_DestroyJavaVM_t)(JavaVM *vm);

// These are the CFRunLoopSourceRef callback functions.
void RunLoopSourceScheduleRoutine (void *info, CFRunLoopRef rl, CFStringRef mode);
void RunLoopSourcePerformRoutine (void *info);
void RunLoopSourceCancelRoutine (void *info, CFRunLoopRef rl, CFStringRef mode);

@interface EmbeddedJvm () {
    NSString *path;
    JavaVMOption* optionsArray;
    int optionCount;
    void *jvmlib;       /* The handle to the JVM library */
    JNI_CreateJavaVM_t createJavaVM;
    
    JavaVM *jvm;       /* denotes a Java VM */
    JNIEnv *env;       /* pointer to native method interface */

}
@property NSThread* mainThread;
@property NSMutableArray* commands;
@property CFRunLoopRef runLoop;
@property CFRunLoopSourceRef runLoopSource;
-(void)doCommand;
@end

@implementation EmbeddedJvm
- (EmbeddedJvm*) initWithClassPaths:(NSArray*)paths options:(NSDictionary*)options error:(NSError**)error {
    if (self = [super init]) {
        if (const char *err = dlerror()) {
            NSLog(@"Flushing existing dl error: %s", err);
        }
        
        NSBundle *app = [NSBundle mainBundle];
        //path = @"JvmHost/jre/lib/server/libjvm.dylib";
        path = [NSString stringWithFormat:@"%@/Contents/Frameworks/EmbeddedJvm.framework/Versions/A/JVM/jre/lib/server/libjvm.dylib", [app executablePath]];
        jvmlib = dlopen([path cStringUsingEncoding:NSASCIIStringEncoding], RTLD_NOW); // or RTLD_LAZY, no difference.
        
        if (jvmlib==nil) {
            const char *derror = dlerror();
            NSFileManager *fm = [[NSFileManager alloc] init];
            NSString *cwd = [fm currentDirectoryPath];
            NSString *msg = [NSString stringWithFormat:@"Error dl loading JVM: %s (from %@)", derror, cwd];
            NSLog(@"%@", msg);
            if (error!=nil) {
                *error = [NSError errorWithDomain:@"load" code:100 userInfo:@{@"msg": msg, @"jvm": path, @"cwd": cwd}];
            }
            return self = nil;
        }
        
        createJavaVM = (JNI_CreateJavaVM_t)dlsym(jvmlib, "JNI_CreateJavaVM");
        if (createJavaVM==nil) {
            NSString *msg = @"Failed to load JNI_CreateJavaVM symbol";
            NSLog(@"%@", msg);
            if (error!=nil) {
                *error = [NSError errorWithDomain:@"load" code:100 userInfo:@{@"msg": msg, @"jvm": path}];
            }
            return self = nil;
        }

        //    options[0].optionString = "-Djava.compiler=NONE";           /* disable JIT */
        //    options[1].optionString = "-Djava.class.path=c:\myclasses"; /* user classes */
        //    options[2].optionString = "-Djava.library.path=c:\mylibs";  /* set native library path */
        //    options[3].optionString = "-verbose:jni";                   /* print JNI-related messages */
        optionsArray = new JavaVMOption[2];
        NSString *classpath = [paths componentsJoinedByString:@";"];
        NSString *classpathDef = [NSString stringWithFormat:@"-Djava.class.path=%@", classpath];
        optionsArray[0].optionString = const_cast<char *>([classpathDef cStringUsingEncoding:NSASCIIStringEncoding]);
        optionsArray[1].optionString = const_cast<char *>([@"-verbose[:class|gc|jni]" cStringUsingEncoding:NSASCIIStringEncoding]);
        optionCount = 2;

        self.commands = [[NSMutableArray alloc] init];

        self.mainThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(mainThreadLoop:)
                                                       object:nil];
        [self.mainThread start];  // Actually create the thread
        
    }
    return self;
}

-(void)dealloc {
    delete[] optionsArray;
}

-(void)close {
    
}

- (bool)createJvm:(NSError**)error {
    // R"(Maybe use raw strings?)";
    JavaVMInitArgs vm_args; /* JDK/JRE 6 VM initialization arguments */
    vm_args.version = JNI_VERSION_1_6;
    vm_args.nOptions = optionCount;
    vm_args.options = optionsArray;
    vm_args.ignoreUnrecognized = false;

    /* load and initialize a Java VM, return a JNI interface pointer in env */
    //JNI_CreateJavaVM(&jvm, (void**)&env, &vm_args);
    jint result = createJavaVM(&jvm, (void**)&env, &vm_args);
    if (result!=0) {
        NSString *msg = [NSString stringWithFormat:@"Failed to load JVM with error code: %d", result];
        NSLog(@"%@", msg);
        if (error!=nil) {
            *error = [NSError errorWithDomain:@"load" code:100 userInfo:@{@"msg": msg, @"jvm": path}];
        }
    }
    return result==0;
}

- (void)mainThreadLoop:(NSObject*)parameter {
    NSError *error = nil;
    [self createJvm:&error];
    if (error!=nil) {
        // TODO: Send error back to caller
    }
    
    NSRunLoop* runLoop = [NSRunLoop currentRunLoop];
    
    // Attach source that feeds events to runloop
    void *memo = (__bridge void *)(self); // Pass weak reference.
    CFRunLoopSourceContext    context = {0, memo, NULL, NULL, NULL, NULL, NULL,
        RunLoopSourceScheduleRoutine,
        RunLoopSourceCancelRoutine,
        RunLoopSourcePerformRoutine};
    
    self.runLoop = [runLoop getCFRunLoop];
    self.runLoopSource = CFRunLoopSourceCreate(NULL, 0, &context);
    
    CFRunLoopAddSource(self.runLoop, self.runLoopSource, kCFRunLoopDefaultMode);
    
    [self doCommand]; // Run all the commands queued while waiting for this thread to start.

    bool threadTerminated = false;
    while (!threadTerminated) {
        bool sourced = [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        if (!sourced) {
            NSLog(@"");
            threadTerminated = true;
        }
    }
}

- (void)destroy {
    /* We are done. */
    jint result = jvm->DestroyJavaVM();
    if (result!=0) {
        NSString *msg = [NSString stringWithFormat:@"Failed to destroy JVM with error code: %d", result];
        NSLog(@"%@", msg);
    }
    dlclose(jvmlib);
}

-(void)doCommand {
    bool done = false;
    do {
        NSObject *command = nil;
        @synchronized(self.commands) {
            if ([self.commands count]>0) {
                command = [self.commands objectAtIndex:0];
                [self.commands removeObjectAtIndex:0];
            }
            else {
                done = true;
            }
        }
        if (command!=nil) {
            void (^cmdBlock)(JNIEnv* env) = (__bridge void(^)(JNIEnv* env))((__bridge void*)(command));
            @try {
                cmdBlock(env);
            }
            @catch (NSException *e) {
                NSLog(@"ERROR: %@", e);
            }
            if (env->ExceptionCheck()) {
                NSLog(@"Unchecked Java exception in user block");
                env->ExceptionDescribe(); // Log exception details in case there is nothing else to do with it.
                // jthrowable ex = env->ExceptionOccurred(); // TODO: Send an error notification?
                env->ExceptionClear();
            }
            command = nil; // Release the block
        }
    } while (!done);
}

- (void) doWithJvmThread:(void(^)(JNIEnv* env))block {
    @synchronized(self.commands) {
        [self.commands addObject:block];
    }
    if (self.runLoop!=nil && self.runLoopSource!=nil) {
        CFRunLoopSourceSignal(self.runLoopSource);
        CFRunLoopWakeUp(self.runLoop);
    }
}

@end

// C-linked functions used to wire up CFRunLoopSource
void RunLoopSourceScheduleRoutine (void *info, CFRunLoopRef rl, CFStringRef mode)
{
    EmbeddedJvm *host = (EmbeddedJvm*)CFBridgingRelease(info);
    [host setRunLoop:rl];
}
void RunLoopSourcePerformRoutine (void *info)
{
    EmbeddedJvm *host = (EmbeddedJvm*)CFBridgingRelease(info);
    [host doCommand];
}
void RunLoopSourceCancelRoutine (void *info, CFRunLoopRef rl, CFStringRef mode)
{
    EmbeddedJvm *host = (EmbeddedJvm*)CFBridgingRelease(info);
    [host setRunLoop:nil];
    NSLog(@"Unexpected cancelation of run loop source");
}
