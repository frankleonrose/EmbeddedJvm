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
        NSURL *exeUrl = [app executableURL];
        if ([[exeUrl lastPathComponent] isEqualToString:@"xctest"]) {
            path = @"EmbeddedJvm/jre/lib/server/libjvm.dylib";
            NSLog(@"XCTest deployment loading %@", path);
        }
        else {
            NSURL *contentsPath = [[exeUrl URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
            path = [NSString stringWithFormat:@"%@/Frameworks/EmbeddedJvm.framework/Versions/A/JVM/jre/lib/server/libjvm.dylib", [contentsPath path]];
        }
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
        optionCount = 5;
        optionsArray = new JavaVMOption[optionCount];
        NSString *classpath = [paths componentsJoinedByString:@";"];
        NSString *classpathDef = [NSString stringWithFormat:@"-Djava.class.path=%@", classpath];
        optionsArray[0].optionString = [self asciiString:classpathDef];
        optionsArray[1].optionString = [self asciiString:@"-verbose[:class|gc|jni]"];
        optionsArray[2].optionString = [self asciiString:@"-XX:MaxPermSize=256m"];
        optionsArray[3].optionString = [self asciiString:@"-Xms200m"];
        optionsArray[4].optionString = [self asciiString:@"-Xmx1500m"];

        self.commands = [[NSMutableArray alloc] init];

        NSLog(@"Initializing mainThreadLoop (self=%@)", self);
        self.mainThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(mainThreadLoop:)
                                                       object:nil];
        [self.mainThread setName:@"EmbeddedJvm"];
        [self.mainThread start];  // Actually start the thread
        
    }
    return self;
}

-(char *)asciiString:(NSString*)s {
    return const_cast<char *>([s cStringUsingEncoding:NSASCIIStringEncoding]);
}

-(void)dealloc {
    NSLog(@"Deallocating EmbeddedJvm");
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
    NSLog(@"Starting mainThreadLoop (self=%@)", self);
    NSError *error = nil;
    [self createJvm:&error];
    if (error!=nil) {
        // TODO: Send error back to caller
        return;
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
        bool sourceOrTimeout = [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        if (!sourceOrTimeout) {
            NSLog(@"Failed to start run loop in EmbeddedJvm");
            threadTerminated = true;
        }
        [self doCommand];
    }
    NSLog(@"Terminated EmbeddedJvm main thread");
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
    //NSLog(@"Run all enqueued commands");
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
            NSLog(@"Picked a command from the JVM queue");
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
    //NSLog(@"Done running commands");
}

- (void) doWithJvmThread:(void(^)(JNIEnv* env))block {
    NSLog(@"Enqueuing command to JVM queue");
    @synchronized(self.commands) {
        [self.commands addObject:block];
    }
    if (self.runLoop!=nil && self.runLoopSource!=nil) {
        NSLog(@"Alerting JVM runloop about new command");
        CFRunLoopSourceSignal(self.runLoopSource);
        CFRunLoopWakeUp(self.runLoop);
    }
    else {
        NSLog(@"JVM runloop not yet started");
    }
}

@end

// C-linked functions used to wire up CFRunLoopSource
void RunLoopSourceScheduleRoutine (void *info, CFRunLoopRef rl, CFStringRef mode)
{
    EmbeddedJvm *host = (__bridge_transfer EmbeddedJvm*)(info);
    [host setRunLoop:rl];
}
void RunLoopSourcePerformRoutine (void *info)
{
    EmbeddedJvm *host = (__bridge_transfer EmbeddedJvm*)(info);
    [host doCommand];
}
void RunLoopSourceCancelRoutine (void *info, CFRunLoopRef rl, CFStringRef mode)
{
    EmbeddedJvm *host = (__bridge_transfer EmbeddedJvm*)(info);
    [host setRunLoop:nil];
    NSLog(@"Unexpected cancelation of run loop source");
}
