//
//  EJJvm.mm
//  EmbeddedJvm
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//
/*
 If we want to use this JVM from more threads, we should offer classes that can be requested of the JVM that manage attaching
 and detaching their threads.
   getQueuedAccessor - This is like the current model where the caller submits a block to be run on the right thread.
   getDirectAccessor - Used to attach the calling thread and allow JVM access from that thread alone.
   getUniversalAccessor - At the cost of attach/detach bookkeeping, this accessor guarantees that all users are attached and ready to call into the JVM.

 jint AttachCurrentThread(JavaVM* vm, void** penv, void* args);
 jint AttachCurrentThreadAsDaemon(JavaVM* vm, void** penv, void* args);
 
 
 Demonstrate using RegisterNatives to link functions in the host to classes loaded into the Embedded JVM.
 */


#import "EmbeddedJvm.h"
#include <dlfcn.h>
#include <pthread.h>

JNIEXPORT void JNICALL EmbeddedJvmOutputStream_write(JNIEnv *env, jobject obj, jbyteArray bytes, jint offset, jint len);
JNIEXPORT void JNICALL EmbeddedJvmOutputStream_open(JNIEnv *env, jobject obj, jstring tag);
JNIEXPORT void JNICALL EmbeddedJvmOutputStream_flush(JNIEnv *env, jobject obj);
JNIEXPORT void JNICALL EmbeddedJvmOutputStream_close(JNIEnv *env, jobject obj);

NSData *EJJBytesToData(jbyteArray bytes, JNIEnv *env) {
    jsize length = env->GetArrayLength(bytes);
    jboolean isCopy = false;
    jbyte *jbytes = env->GetByteArrayElements(bytes, &isCopy);
    return [NSData dataWithBytes:jbytes length:length];
}

jbyteArray EJDataToJBytes(NSData *data, JNIEnv *env) {
    assert([data length]<=INT_MAX);
    jsize responseSize = (int)[data length];
    jbyteArray response = env->NewByteArray(responseSize);
    jbyte *jbytes = const_cast<jbyte*>(static_cast<const jbyte *>([data bytes]));
    env->SetByteArrayRegion(response, 0, responseSize, jbytes);
    return response;
}

typedef jint (JNICALL *JNI_GetDefaultJavaVMInitArgs_t)(void *args);
typedef jint (JNICALL *JNI_CreateJavaVM_t)(JavaVM **pvm, void **penv, void *args);
typedef jint (JNICALL *JNI_GetCreatedJavaVMs_t)(JavaVM **, jsize, jsize *);
typedef jint (JNICALL *JNI_DestroyJavaVM_t)(JavaVM *vm);

static jint JNICALL my_vfprintf(FILE *fp, const char *format, va_list args);
static NSMutableArray *errors = [NSMutableArray array];

// These are the CFRunLoopSourceRef callback functions.
void RunLoopSourceScheduleRoutine (void *info, CFRunLoopRef rl, CFStringRef mode);
void RunLoopSourcePerformRoutine (void *info);
void RunLoopSourceCancelRoutine (void *info, CFRunLoopRef rl, CFStringRef mode);

@interface EJJvm () {
    JavaVMOption* optionsArray;
    int optionCount;
    void *jvmlib;       /* The handle to the JVM library */
    CFBundleRef jreBundle;
    JNI_CreateJavaVM_t createJavaVM;
    
    JavaVM *jvm;       /* denotes a Java VM */
    JNIEnv *env;       /* pointer to native method interface */

    dispatch_semaphore_t mainThreadStartSignal;
    dispatch_semaphore_t mainThreadEndSignal;
    dispatch_queue_t lifecycleQueue;
}
@property NSString *classpath;
@property NSThread* mainThread;
@property NSMutableArray* commands;
@property CFRunLoopRef runLoop;
@property CFRunLoopSourceRef runLoopSource;
@property BOOL shutdownRequested;
@property BOOL isShutdown;
@property NSError *startError;
-(void)doCommand;
@end

#define JRE_JVM_SHARED_LIB @"lib/server/libjvm.dylib"
#define JDK_JVM_SHARED_LIB @"jre/" JRE_JVM_SHARED_LIB

#define kLaunchFailure "JavaAppLauncherFailure"
#define CREATE_JVM_FN "JNI_CreateJavaVM"

@implementation EJJvm
+(NSString *)appendJvmToJre:(NSString *)javaHome {
    NSString *lib = JRE_JVM_SHARED_LIB;
    if ([javaHome rangeOfString:@"jre"].location == NSNotFound) {
        // Assume we have JDK
        lib = JDK_JVM_SHARED_LIB;
    }
    return [NSString stringWithFormat:@"%@/%@", javaHome, lib];
}

+(char *)createCString:(NSString *)s {
    NSUInteger bufferSize = [s length] + 1; // Room for nul terminator
    char *buffer = new char[bufferSize];
    BOOL success = [s getCString:buffer maxLength:bufferSize encoding:NSASCIIStringEncoding];
    if (!success) {
        delete [] buffer;
        return NULL;
    }
    return buffer;
}

+(NSArray *)findSubPaths:(NSString *)directoryToScan
{
    NSFileManager *localFileManager=[[NSFileManager alloc] init];
    NSDirectoryEnumerator *dirEnumerator = [localFileManager enumeratorAtURL:[NSURL fileURLWithPath:directoryToScan]
                                                  includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler:nil];
    NSMutableArray *subPaths=[NSMutableArray array];
    for (NSURL *theURL in dirEnumerator) {
        NSNumber *isDirectory;
        [theURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
        if ([isDirectory boolValue]==YES) {
            [subPaths addObject:[theURL path]];
        }
    }
    return subPaths;
}

+(NSArray *)findJars:(NSString *)directoryToScan
{
    NSFileManager *localFileManager=[[NSFileManager alloc] init];
    NSDirectoryEnumerator *dirEnumerator = [localFileManager enumeratorAtURL:[NSURL fileURLWithPath:directoryToScan]
                                                  includingPropertiesForKeys:@[NSURLNameKey, NSURLIsDirectoryKey]
                                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                errorHandler:nil];
    NSMutableArray *jars=[NSMutableArray array];
    for (NSURL *theURL in dirEnumerator) {
        if ([dirEnumerator level]>=1) {
            // Keep to a single level.  In the future we may do a more clever scan to separate
            // .jar library directories and .class file package structures.
            [dirEnumerator skipDescendants];
        }
        
        NSString *name = nil;
        [theURL getResourceValue:&name forKey:NSURLNameKey error:NULL];
        
        NSNumber *isDirectory;
        [theURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:NULL];
        
        NSRange substring = [name rangeOfString:@".jar" options:NSCaseInsensitiveSearch];
        
        // Not directory and string ends with .jar
        if ([isDirectory boolValue]==NO && substring.location==([name length]-4)) {
            [jars addObject:[theURL path]];
        }
    }
    return jars;
}

// CFBundle strategy from https://bugs.eclipse.org/bugs/show_bug.cgi?id=411361#c7
// Silenio Quarti (IBM Eclipse Team Lead): <<It turns out that JNI_CreateJavaVM() pops up the dialog only if the VM library/function has been loaded using dlopen/dlsym.  The problem does not happen if the function is loaded using the CFBundle APIs (CFBundleCreate/CFBundleGetFunctionPointerForName). Somehow loading the JDK 1.7 bundle avoids the problem.>>
// And sample code from OpenJDK: http://cr.openjdk.java.net/~michaelm/7113349/7u4/4/jdk7u-osx/new/src/macosx/bundle/JavaAppLauncher/src/JavaAppLauncher.m.html
- (JNI_CreateJavaVM_t) loadAsBundle:(NSURL *)jreBundleURL error:(NSError * __autoreleasing *)error {
    // load the libjli.dylib of the embedded JRE (or JDK) bundle
    jreBundle = CFBundleCreate(NULL, (__bridge CFURLRef)jreBundleURL);
    
    CFErrorRef err = NULL;
    Boolean jreBundleLoaded = CFBundleLoadExecutableAndReturnError(jreBundle, &err);
    if (err != nil || !jreBundleLoaded) {
        NSError *nserr = (__bridge_transfer NSError *)err;
        if (error!=nil) {
            *error = nserr;
        }
        NSLog(@"could not load the JRE/JDK: %@", nserr);
        return NULL;
    }
    
    // if there is a preferred libjvm to load, set it here
    //         if (args.preferredJVMLib != NULL) {
    //             SetPreferredJVM_t setPrefJVMFxnPtr = CFBundleGetFunctionPointerForName(jreBundle, CFSTR("JLI_SetPreferredJVM"));
    //             if (setPrefJVMFxnPtr != NULL) {
    //                 setPrefJVMFxnPtr(args.preferredJVMLib);
    //             } else {
    //                 NSLog(@"No JLI_SetPreferredJVM in JRE/JDK primary executable, failed to set preferred JVM library to: %s", args->preferredJVMLib);
    //             }
    //         }
    
    // pull the JNI_CreateJavaVM function pointer out of the primary executable of the JRE/JDK bundle
    void *rawCreateFn = CFBundleGetFunctionPointerForName(jreBundle, CFSTR(CREATE_JVM_FN));
    return reinterpret_cast<JNI_CreateJavaVM_t>(rawCreateFn);
}

- (JNI_CreateJavaVM_t) loadAsDylib:(NSString *)appJvm error:(NSError * __autoreleasing *)error {
    if (const char *err = dlerror()) {
        NSLog(@"Flushing existing dl error: %s", err);
    }

    jvmlib = dlopen([appJvm cStringUsingEncoding:NSASCIIStringEncoding], RTLD_NOW | RTLD_LOCAL); // Being strict
    
    if (jvmlib==nil) {
        const char *derror = dlerror();
        NSFileManager *fm = [[NSFileManager alloc] init];
        NSString *cwd = [fm currentDirectoryPath];
        NSString *msg = [NSString stringWithFormat:@"Error dl loading JVM: %s (from %@)", derror, cwd];
        NSLog(@"%@", msg);
        if (error!=nil) {
            *error = [NSError errorWithDomain:@"load" code:0 userInfo:@{@"msg": msg, @"jvm": appJvm, @"cwd": cwd}];
        }
        return NULL;
    }
    
    return (JNI_CreateJavaVM_t)dlsym(jvmlib, CREATE_JVM_FN);
}

- (EJJvm*) initWithClassPaths:(NSArray*)paths options:(NSArray*)options error:(NSError * __autoreleasing *)error {
    if (self = [super init]) {
        self.isShutdown = NO;
        self.shutdownRequested = NO;
        self->mainThreadStartSignal = dispatch_semaphore_create(0);
        self->mainThreadEndSignal = dispatch_semaphore_create(0);
        self->lifecycleQueue = dispatch_queue_create("EJJvmLifecycle", 0);
        
        if (paths==nil) {
            paths = @[];
        }
        NSBundle *appBundle = [NSBundle mainBundle];
        NSURL *exeUrl = [appBundle executableURL];
        NSURL *appContents = [[appBundle bundleURL] URLByAppendingPathComponent:@"Contents"];
        NSString *javaHome = [[[NSProcessInfo processInfo] environment] objectForKey:@"EMBEDDEDJVM_JAVA_HOME"];
        NSURL *jreBundleURL = nil;
        if (javaHome!=nil) {
            NSLog(@"Using EMBEDDEDJVM_JAVA_HOME environment variable: \"%@\"", javaHome);
        }
        else if ([[exeUrl lastPathComponent] isEqualToString:@"xctest"]) {
            // If we haven't been overridden and we're running tests, don't try to use embedded JVM.
            javaHome = [[[NSProcessInfo processInfo] environment] objectForKey:@"JAVA_HOME"];
            NSLog(@"Using JAVA_HOME environment variable for XCTest: \"%@\"", javaHome);
        }
        else {
            // app/Contents/PlugIns/jre1.7.0_.jre/Contents/Home
            NSString *jvmRuntime = (NSString *)[appBundle objectForInfoDictionaryKey:@"JVMRuntime"];
            if (jvmRuntime==nil) {
                NSString *msg = @"Unable to read Info.plist key \"JVMRuntime\"";
                NSLog(@"%@", msg);
                if (error!=nil) {
                    *error = [NSError errorWithDomain:@"EmbeddedJvm" code:0 userInfo:@{@"msg": msg}];
                }
                return self = nil;
            }
            jreBundleURL = [[appBundle builtInPlugInsURL] URLByAppendingPathComponent:jvmRuntime];
            javaHome = [[jreBundleURL path] stringByAppendingPathComponent:@"Contents/Home"];
            NSLog(@"Using embedded JVM with plugin name from Info.plist: \"%@\"", [jreBundleURL path]);
        }
        if (jreBundleURL==nil) {
            jreBundleURL = [NSURL URLWithString:[[javaHome stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]];
        }
        NSString *appJvm = [EJJvm appendJvmToJre:javaHome];

//        createJavaVM = [self loadAsDylib:appJvm error:error];
        createJavaVM = [self loadAsBundle:jreBundleURL error:error];
        
        if (createJavaVM==nil) {
            NSString *msg = @"Failed to load JNI_CreateJavaVM symbol";
            NSLog(@"%@", msg);
            if (error!=nil) {
                *error = [NSError errorWithDomain:@"EmbeddedJvm" code:0 userInfo:@{@"msg": msg, @"jvm": appJvm}];
            }
            return self = nil;
        }

        NSString *appJava = [NSString stringWithFormat:@"%@/Java", [appContents path]];
        {
            // Convenience method replaces APP_JAVA with actual app's Java path
            NSMutableArray *adjustedPaths = [NSMutableArray arrayWithCapacity:[paths count]];
            for(id o in paths){
                NSString *p = (NSString *)o;
                p = [p stringByReplacingOccurrencesOfString:@"$APP_JAVA" withString:appJava];
                [adjustedPaths addObject:p];
            }
            paths = adjustedPaths;
        }
        
        {
            NSMutableArray *buildPaths = [NSMutableArray arrayWithArray:paths];
            
            NSArray *jars = [EJJvm findJars:appJava];
            [buildPaths addObjectsFromArray:jars];

            NSArray *subPaths = [EJJvm findSubPaths:appJava];
            // Append /* to subPaths
            {
                NSMutableArray *adjustedPaths = [NSMutableArray arrayWithCapacity:[subPaths count]];
                for(id o in subPaths){
                    NSString *p = (NSString *)o;
                    p = [p stringByAppendingPathComponent:@"*"];
                    [adjustedPaths addObject:p];
                }
                subPaths = adjustedPaths;
            }
            [buildPaths addObjectsFromArray:subPaths];

            paths = buildPaths;
        }
        
        // "-Djava.compiler=NONE";           /* disable JIT */
        // "-Djava.class.path=c:\myclasses"; /* user classes */
        // "-Djava.library.path=c:\mylibs";  /* set native library path */
        // "-verbose:jni";                   /* print JNI-related messages */

        if (options==nil) {
            options = @[];
        }
        NSMutableArray *buildOptions = [NSMutableArray arrayWithArray:options];

        NSString *classpath = [paths componentsJoinedByString:@":"]; // Unix & OSX path separator
        NSLog(@"Classpath: %@", classpath);
        NSString *classpathDef = [NSString stringWithFormat:@"-Djava.class.path=%@", classpath];
        [buildOptions addObject:classpathDef];
        
        id bundleOptions = (NSString *)[appBundle objectForInfoDictionaryKey:@"JVMOptions"];
        if ([bundleOptions isKindOfClass:[NSArray class]]) {
            options = bundleOptions;
            for (id opt in options) {
                if ([opt isKindOfClass:[NSString class]]) {
                    [buildOptions addObject:opt];
                }
                else {
                    NSLog(@"Warning: And item in JVMOptions in Info.plist is not a string (%@).", opt);
                }
            }
        }
        else {
            NSLog(@"Warning: JVMOptions in Info.plist does not appear to be an array.");
        }
        
        optionCount = (int)[buildOptions count] + 1;
        
        optionsArray = new JavaVMOption[optionCount];
        memset(optionsArray, 0, optionCount * sizeof(JavaVMOption));

        optionsArray[0].optionString = const_cast<char *>("vfprintf");
        optionsArray[0].extraInfo = (void *)my_vfprintf;
        
        int i = 1;
        for (NSString *option in buildOptions) {
            char *buffer = [EJJvm createCString:option];
            if (buffer==NULL) {
                NSString *msg = [NSString stringWithFormat:@"Failed to encode JVM option as cstring (%@)", option];
                NSLog(@"%@", msg);
                if (error!=nil) {
                    *error = [NSError errorWithDomain:@"EmbeddedJvm" code:0 userInfo:@{@"msg": msg, @"jvm": appJvm}];
                }
                return self = nil;
            }
            optionsArray[i++].optionString = buffer;
        }

        self.commands = [[NSMutableArray alloc] init];

        NSLog(@"Initializing mainThreadLoop (self=%@)", self);
        self.mainThread = [[NSThread alloc] initWithTarget:self
                                                     selector:@selector(mainThreadLoop:)
                                                       object:nil];
        [self.mainThread  setName:@"EmbeddedJvm"];
        [self.mainThread start];  // Actually start the thread
        dispatch_semaphore_wait(mainThreadStartSignal, DISPATCH_TIME_FOREVER);
        if (self.isShutdown) {
            // We had a problem starting
            if (error!=nil) {
                *error = self.startError;
            }
            return self = nil;
        }
    }
    return self;
}

-(void)dealloc {
    NSLog(@"Deallocating EmbeddedJvm");
    
    [self close];
    
    if (optionsArray!=nil) {
        // 0th entry was not allocated on stack!
        for (int j=1; j<optionCount; ++j) {
            delete[] optionsArray[j].optionString;
        }
        delete[] optionsArray;
    }
    
    dispatch_release(self->mainThreadStartSignal);
    dispatch_release(self->mainThreadEndSignal);
    dispatch_release(self->lifecycleQueue);
}

-(void)printErrors {
    if ([errors count]>0) {
        NSArray *toPrint;
        @synchronized (errors) {
            toPrint = errors;
            errors = [NSMutableArray array];
        }
        for (NSString *err in toPrint) {
            NSLog(@"JVM: %@", err);
        }
    }
}

-(void)close {
    void (^syncDestroy)() = ^() {
        if (!self.isShutdown) {
            [self printErrors];

            // PoisonPill block that sets shutdownRequested=YES so that main thread knows to terminate
            void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
                self.shutdownRequested = YES;
            };
            
            [self enqueueCommand:blockWithDone];
            
            dispatch_semaphore_wait(self->mainThreadEndSignal, DISPATCH_TIME_FOREVER);
            
            self.isShutdown = YES;
        }
    };
    
    // Call on serial queue to ensure that it happens only once despite multiple calls to close.
    dispatch_sync(self->lifecycleQueue, syncDestroy);
}

- (bool)createJvm:(NSError * __autoreleasing *)error {
    // R"(Maybe use raw strings?)";
    JavaVMInitArgs vm_args; /* JDK/JRE 6 VM initialization arguments */
    vm_args.version = JNI_VERSION_1_6;
    vm_args.nOptions = optionCount;
    vm_args.options = optionsArray;
    vm_args.ignoreUnrecognized = JNI_TRUE; // With this set to JNI_FALSE, the JVM initialization failed with settings like -Xmanagement:... and -XXrunjdwp:...

    NSLog(@"JVM Options:");
    for (int i=0; i<optionCount; ++i) {
        NSLog(@"%s", optionsArray[i].optionString);
    }

    /* load and initialize a Java VM, return a JNI interface pointer in env */
//    NSLog(@"Calling createJavaVM()");
    jint result = self->createJavaVM(&self->jvm, (void**)&self->env, &vm_args);
//    NSLog(@"Returned from createJavaVM()");
    if (result!=0) {
        NSString *msg = [NSString stringWithFormat:@"Failed to create JVM with error code: %d", result];
        NSLog(@"%@", msg);
        if (error!=nil) {
            *error = [NSError errorWithDomain:@"EmbeddedJvm" code:100 userInfo:@{@"msg": msg}];
        }
        for (int i=0; i<optionCount; ++i) {
            NSLog(@"%s", optionsArray[i].optionString);
        }
    }
    return result==0;
}

- (void)mainThreadLoop:(NSObject*)parameter {
    pthread_setname_np("EmbeddedJvm");
    NSLog(@"Starting EmbeddedJvm main thread (self=%@)", self);
    NSError *error = nil;
    [self createJvm:&error];
    if (error!=nil) {
        // TODO: Send error back to caller
        NSLog(@"Error creating JVM: %@", error);
        self.isShutdown = YES;
        self.startError = error;
        dispatch_semaphore_signal(self->mainThreadStartSignal);
        return;
    }
    NSLog(@"Created JVM in main thread");
    
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
    
    EJClass *output = [self connectNativeOutput];

    dispatch_semaphore_signal(self->mainThreadStartSignal);

    [self doCommand]; // Run all the commands queued while waiting for this thread to start.

    bool threadTerminated = false;
    while (!threadTerminated && !self.shutdownRequested) {
        @autoreleasepool {
            bool sourceOrTimeout = [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1]];
            if (!sourceOrTimeout) {
                NSLog(@"Failed to start run loop in EmbeddedJvm");
                threadTerminated = true;
            }
            [self doCommand];
        }
    }
    
    output = nil;
    self.isShutdown = YES;
    
    // Release runloop stuff
    CFRunLoopRemoveSource(self.runLoop, self.runLoopSource, kCFRunLoopDefaultMode);
    CFRelease(self.runLoopSource);
    self.runLoopSource = nil;
    self.runLoop = nil;
    
    /* We are done. */
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
    
    jint result = jvm->DetachCurrentThread();
    if (result!=0) {
        NSString *msg = [NSString stringWithFormat:@"Failed to detach EmbeddedJvm thread with error code: %d", result];
        NSLog(@"%@", msg);
    }
    result = jvm->DestroyJavaVM();
    if (result!=0) {
        NSString *msg = [NSString stringWithFormat:@"Failed to destroy JVM with error code: %d", result];
        NSLog(@"%@", msg);
    }
    
    if (jvmlib!=NULL) {
        dlclose(jvmlib);
        jvmlib = NULL;
    }
    if (jreBundle!=NULL) {
        CFBundleUnloadExecutable(jreBundle);
        CFRelease(jreBundle);
        jreBundle = NULL;
    }

    NSLog(@"Terminated EmbeddedJvm main thread");
    dispatch_semaphore_signal(self->mainThreadEndSignal);
}

#define NATIVE_OUTPUT_CLASS @"com/futurose/embeddedjvm/EmbeddedJvmOutputStream"

- (EJClass *)connectNativeOutput {
    static JNINativeMethod method_table[] = {
        EJ_JVM_NATIVE("nativeWrite", "([BII)V", EmbeddedJvmOutputStream_write),
        EJ_JVM_NATIVE("nativeOpen", "(Ljava/lang/String;)V", EmbeddedJvmOutputStream_open),
        EJ_JVM_NATIVE("nativeFlush", "()V", EmbeddedJvmOutputStream_flush),
        EJ_JVM_NATIVE("nativeClose", "()V", EmbeddedJvmOutputStream_close),
    };

    NSError *error = nil;
    EJClass *cls = [[EJClass alloc] initWithClassName:NATIVE_OUTPUT_CLASS env:env error:&error];
    if (cls==nil) {
        NSLog(@"Native output class \"%@\" unavailable.", NATIVE_OUTPUT_CLASS);
        NSLog(@"%@", [error description]);
    }
    else {
        BOOL success = [cls registerNativeMethods:method_table count:4 env:env error:&error];
        if (!success) {
            NSLog(@"Unable to register methods with output class \"%@\".", NATIVE_OUTPUT_CLASS);
            NSLog(@"%@", [error description]);
        }
        else {
            jmethodID redirect = [cls getStaticMethod:@"redirectStandardStreams" signature:@"()V" env:env error:&error];
            if (redirect==nil) {
                NSLog(@"Unable to redirect standard streams.");
                NSLog(@"%@", [error description]);
            }
            else {
                env->CallStaticVoidMethod(cls.theClass, redirect);
                if (env->ExceptionCheck()) {
                    env->ExceptionDescribe();
                    env->ExceptionClear();
                }
            }
        }
    }
    return cls;
}

-(void)doCommand {
//    NSLog(@"Run all enqueued commands");
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
//            NSLog(@"Picked a command from the JVM queue");
            void (^cmdBlock)(JNIEnv* env) = (__bridge void(^)(JNIEnv* env))((__bridge void*)(command));
            @try {
                cmdBlock(env);
            }
            @catch (NSException *e) {
                NSLog(@"ERROR: %@", e);
            }
            if (env->ExceptionCheck()) {
                NSLog(@"Unchecked Java exception in user block.  You should call env->ExceptionCheck() within the blocks you submit to doWithJvmThread.");
                env->ExceptionDescribe(); // Log exception details in case there is nothing else to do with it.
                // jthrowable ex = env->ExceptionOccurred(); // TODO: Send an error notification?
                env->ExceptionClear();
            }
            [self printErrors];
            command = nil; // Release the block
        }
    } while (!done);
//    NSLog(@"Done running commands");
}

- (void)enqueueCommand:(void(^)(JNIEnv *))block {
    //    NSLog(@"Enqueuing command to JVM queue");
    @synchronized(self.commands) {
        [self.commands addObject:block];
    }
    
    // Notify runLoop that it should wake up and process commands...
    if (self.runLoop!=nil && self.runLoopSource!=nil) {
        //        NSLog(@"Alerting JVM runloop about new command");
        CFRunLoopSourceSignal(self.runLoopSource);
        CFRunLoopWakeUp(self.runLoop);
    }
    else {
        //        NSLog(@"JVM runloop not yet started");
    }
}

- (void) callJvmSyncVoid:(void(^)(JNIEnv *))block {
    if (self.isShutdown) {
        return;
    }
    
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    
    void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
        block(blockEnv);
        dispatch_semaphore_signal(done);
    };
    
    [self enqueueCommand:blockWithDone];

    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    dispatch_release(done);
}

- (int) callJvmSyncInt:(int(^)(JNIEnv* env))block {
    if (self.isShutdown) {
        return 0;
    }
    
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    
    int __block ret = 0;
    void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
        ret = block(blockEnv);
        dispatch_semaphore_signal(done);
    };
    
    [self enqueueCommand:blockWithDone];
    
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    dispatch_release(done);
    return ret;
}

- (id) callJvmSyncObject:(id(^)(JNIEnv* env))block {
    if (self.isShutdown) {
        return nil;
    }
    
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    
    id __block ret = 0;
    void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
        ret = block(blockEnv);
        dispatch_semaphore_signal(done);
    };
    
    [self enqueueCommand:blockWithDone];
    
    dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
    dispatch_release(done);
    return ret;
}

- (void) callJvmAsyncVoid:(void(^)(JNIEnv* env))block completion:(void(^)())completion {
    if (self.isShutdown) {
        return completion();
    }
    
    void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
        block(blockEnv);
        if (completion!=nil) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), completion);
        }
    };
    
    [self enqueueCommand:blockWithDone];
}

- (void) callJvmAsyncInt:(int(^)(JNIEnv* env))block completion:(void(^)(int i))completion {
    if (self.isShutdown) {
        return completion(0);
    }
    
    void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
        int ret = block(blockEnv);
        void(^vcompletion)() = ^() {
            completion(ret);
        };
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), vcompletion);
    };
    
    [self enqueueCommand:blockWithDone];
}

- (void) callJvmAsyncObject:(id(^)(JNIEnv* env))block completion:(void(^)(id obj))completion {
    if (self.isShutdown) {
        return completion(nil);
    }
    
    void (^blockWithDone)(JNIEnv *) = ^(JNIEnv *blockEnv) {
        id ret = block(blockEnv);
        void(^vcompletion)() = ^() {
            completion(ret);
        };
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), vcompletion);
    };
    
    [self enqueueCommand:blockWithDone];
}

- (JNIEnv *) getEnv {
    JNIEnv *threadEnv = nil;
    jvm->GetEnv(reinterpret_cast<void**>(&threadEnv), JNI_VERSION_1_6);
    return threadEnv;
}
@end

static jint JNICALL my_vfprintf(FILE *fp, const char *format, va_list args)
{
    //NSLog(@"vfprintf %llx - %s", (long long)fp, format);
    char staticBuffer[5000];
    size_t size = sizeof(staticBuffer);
    int ret = vsnprintf(staticBuffer, size, format, args);
    char *msg = staticBuffer;

    char *allocated = NULL;
    NSString *err = nil;
    if (ret<0) {
        err = @"Encoding error attempting to vsnprintf string";
    }
    else if ((ret+1)>size) {
        size = ret + 1;
        allocated = reinterpret_cast<char *>(malloc(size));
        ret = vsnprintf(allocated, size, format, args);
        msg = allocated;
        if (ret<0) {
            err = @"Encoding error attempting to vsnprintf string";
        }
    }
    if (err==nil) {
        err = [NSString stringWithCString:msg encoding:NSASCIIStringEncoding];
    }
    if (allocated!=NULL) {
        free(allocated);
    }
    @synchronized (errors) {
        [errors addObject:err];
    }
    return 0;
}

JNIEXPORT void JNICALL EmbeddedJvmOutputStream_write(JNIEnv *env, jobject obj, jbyteArray bytes, jint offset, jint len) {
    NSData *data = EJJBytesToData(bytes, env);
    NSData *section = [data subdataWithRange:NSMakeRange(offset, len)];
    NSString *s = [[NSString alloc] initWithData:section encoding:NSUTF8StringEncoding];
    NSLog(@"%@", s);
}

JNIEXPORT void JNICALL EmbeddedJvmOutputStream_open(JNIEnv *env, jobject obj, jstring tag) {
    
}

JNIEXPORT void JNICALL EmbeddedJvmOutputStream_flush(JNIEnv *env, jobject obj) {
    
}

JNIEXPORT void JNICALL EmbeddedJvmOutputStream_close(JNIEnv *env, jobject obj) {
    
}


// C-linked functions used to wire up CFRunLoopSource
void RunLoopSourceScheduleRoutine (void *info, CFRunLoopRef rl, CFStringRef mode)
{
    EJJvm *host = (__bridge EJJvm*)(info);
    [host setRunLoop:rl];
}
void RunLoopSourcePerformRoutine (void *info)
{
    EJJvm *host = (__bridge EJJvm*)(info);
    [host doCommand];
}
void RunLoopSourceCancelRoutine (void *info, CFRunLoopRef rl, CFStringRef mode)
{
    EJJvm *host = (__bridge EJJvm*)(info);
    [host setRunLoop:nil];
    if (!host.shutdownRequested) {
        NSLog(@"Unexpected cancelation of run loop source");
    }
}

