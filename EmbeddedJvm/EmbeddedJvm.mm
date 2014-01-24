//
//  EmbeddedJvm.mm
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

NSData *jbytesToData(jbyteArray bytes, JNIEnv *env) {
    jsize length = env->GetArrayLength(bytes);
    jboolean isCopy = false;
    jbyte *jbytes = env->GetByteArrayElements(bytes, &isCopy);
    return [NSData dataWithBytes:jbytes length:length];
}

jbyteArray dataToJbytes(NSData *data, JNIEnv *env) {
    assert([data length]<=INT_MAX);
    jsize responseSize = (int)[data length];
    jbyteArray response = env->NewByteArray(responseSize);
    jbyte *jbytes = const_cast<jbyte*>(static_cast<const jbyte *>([data bytes]));
    env->SetByteArrayRegion(response, 0, responseSize, jbytes);
    return response;
}

typedef jint (*JNI_GetDefaultJavaVMInitArgs_t)(void *args);
typedef jint (*JNI_CreateJavaVM_t)(JavaVM **pvm, void **penv, void *args);
typedef jint (*JNI_GetCreatedJavaVMs_t)(JavaVM **, jsize, jsize *);
//typedef jint (*jni_DestroyJavaVM_t)(JavaVM *vm);

static jint JNICALL my_vfprintf(FILE *fp, const char *format, va_list args);
static NSMutableArray *errors = [NSMutableArray array];

// These are the CFRunLoopSourceRef callback functions.
void RunLoopSourceScheduleRoutine (void *info, CFRunLoopRef rl, CFStringRef mode);
void RunLoopSourcePerformRoutine (void *info);
void RunLoopSourceCancelRoutine (void *info, CFRunLoopRef rl, CFStringRef mode);

@interface EmbeddedJvm () {
    JavaVMOption* optionsArray;
    int optionCount;
    void *jvmlib;       /* The handle to the JVM library */
    JNI_CreateJavaVM_t createJavaVM;
    
    JavaVM *jvm;       /* denotes a Java VM */
    JNIEnv *env;       /* pointer to native method interface */

}
@property NSString *classpath;
@property NSThread* mainThread;
@property NSMutableArray* commands;
@property CFRunLoopRef runLoop;
@property CFRunLoopSourceRef runLoopSource;
-(void)doCommand;
@end

#define JRE_JVM_SHARED_LIB @"lib/server/libjvm.dylib"
#define JDK_JVM_SHARED_LIB @"jre/" JRE_JVM_SHARED_LIB

@implementation EmbeddedJvm
+(NSString *)readJvmPath {
    NSBundle* mainBundle = [NSBundle mainBundle];
    NSString *jvmBundle = (NSString *)[mainBundle objectForInfoDictionaryKey:@"EmbeddedJvm"];
    return jvmBundle;
}

+(NSString *)appendJvmToJre:(NSString *)javaHome {
    NSString *lib = JRE_JVM_SHARED_LIB;
    if ([javaHome rangeOfString:@"jre"].location == NSNotFound) {
        // Assume we have JDK
        lib = JDK_JVM_SHARED_LIB;
    }
    return [NSString stringWithFormat:@"%@/%@", javaHome, lib];
}

- (EmbeddedJvm*) initWithClassPaths:(NSArray*)paths options:(NSDictionary*)options error:(NSError**)error {
    if (self = [super init]) {
        if (const char *err = dlerror()) {
            NSLog(@"Flushing existing dl error: %s", err);
        }
        
        NSBundle *app = [NSBundle mainBundle];
        NSURL *exeUrl = [app executableURL];
        NSURL *appContents = [[app bundleURL] URLByAppendingPathComponent:@"Contents"];
        NSString *javaHome = [[[NSProcessInfo processInfo] environment] objectForKey:@"EMBEDDEDJVM_JAVA_HOME"];
        if (javaHome!=nil) {
            NSLog(@"Using EMBEDDEDJVM_JAVA_HOME environment variable: \"%@\"", javaHome);
        }
        else if ([[exeUrl lastPathComponent] isEqualToString:@"xctest"]) {
            // If we haven't been overridden and we're running tests, don't try to use embedded JVM.
            javaHome = [[[NSProcessInfo processInfo] environment] objectForKey:@"JAVA_HOME"];
            NSLog(@"Using JAVA_HOME environment variable for XCTest: \"%@\"", javaHome);
        }
        else {
            // app/Contents/PlugIns/jre1.7.0_51.jre/Contents/Home
            javaHome = [NSString stringWithFormat:@"%@/%@/Contents/Home", [app builtInPlugInsPath], [EmbeddedJvm readJvmPath]];
            NSLog(@"Using EmbeddedJvm with plugin name from Info.plist: \"%@\"", javaHome);
        }
        NSString *appJvm = [EmbeddedJvm appendJvmToJre:javaHome];

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
    
        jvmlib = dlopen([appJvm cStringUsingEncoding:NSASCIIStringEncoding], RTLD_NOW | RTLD_LOCAL); // Being strict
        
        if (jvmlib==nil) {
            const char *derror = dlerror();
            NSFileManager *fm = [[NSFileManager alloc] init];
            NSString *cwd = [fm currentDirectoryPath];
            NSString *msg = [NSString stringWithFormat:@"Error dl loading JVM: %s (from %@)", derror, cwd];
            NSLog(@"%@", msg);
            if (error!=nil) {
                *error = [NSError errorWithDomain:@"load" code:100 userInfo:@{@"msg": msg, @"jvm": appJvm, @"cwd": cwd}];
            }
            return self = nil;
        }
        
        createJavaVM = (JNI_CreateJavaVM_t)dlsym(jvmlib, "JNI_CreateJavaVM");
        if (createJavaVM==nil) {
            NSString *msg = @"Failed to load JNI_CreateJavaVM symbol";
            NSLog(@"%@", msg);
            if (error!=nil) {
                *error = [NSError errorWithDomain:@"load" code:100 userInfo:@{@"msg": msg, @"jvm": appJvm}];
            }
            return self = nil;
        }

        //    options[0].optionString = "-Djava.compiler=NONE";           /* disable JIT */
        //    options[1].optionString = "-Djava.class.path=c:\myclasses"; /* user classes */
        //    options[2].optionString = "-Djava.library.path=c:\mylibs";  /* set native library path */
        //    options[3].optionString = "-verbose:jni";                   /* print JNI-related messages */
        optionCount = 10; // 9;
        optionsArray = new JavaVMOption[optionCount];
        NSString *classpath = [paths componentsJoinedByString:@":"]; // Unix & OSX path separator
        NSLog(@"Classpath: %@", classpath);
        NSString *classpathDef = [NSString stringWithFormat:@"-Djava.class.path=%@", classpath];
        NSUInteger bufferSize = [classpathDef length] + 100; // Room for nul terminator (and 99 random bytes?)
        char *buffer = new char[bufferSize];
        [classpathDef getCString:buffer maxLength:bufferSize encoding:NSASCIIStringEncoding];
        optionsArray[0].optionString = buffer;
        optionsArray[1].optionString = const_cast<char *>("-verbose:class"); // class,gc,jni
        optionsArray[2].optionString = const_cast<char *>("-XX:MaxPermSize=256m");
        optionsArray[3].optionString = const_cast<char *>("-Xms200m");
        optionsArray[4].optionString = const_cast<char *>("-Xmx1500m");
        optionsArray[5].optionString = const_cast<char *>("vfprintf");
        optionsArray[5].extraInfo = (void *)my_vfprintf;
        optionsArray[6].optionString = const_cast<char *>("-XX:-PrintCommandLineFlags");
        optionsArray[7].optionString = const_cast<char *>("-XX:-TraceClassLoading");
        optionsArray[8].optionString = const_cast<char *>("-Xcheck:jni");
        optionsArray[9].optionString = const_cast<char *>("-Djava.compiler=NONE");
        
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

-(void)dealloc {
    NSLog(@"Deallocating EmbeddedJvm");
    [self printErrors];
    if (optionsArray!=nil) {
        delete[] optionsArray[0].optionString; // Classpath
        delete[] optionsArray;
    }
}

-(void)printErrors {
    if ([errors count]>0) {
        NSArray *toPrint;
        @synchronized (errors) {
            toPrint = errors;
            errors = [NSMutableArray array];
        }
        NSLog(@"JVM output ---------");
        for (NSString *err in toPrint) {
            NSLog(@"%@", err);
        }
        NSLog(@"JVM output ---------");
    }
}

-(void)close {
    
}

- (bool)createJvm:(NSError**)error {
    // R"(Maybe use raw strings?)";
    JavaVMInitArgs vm_args; /* JDK/JRE 6 VM initialization arguments */
    vm_args.version = JNI_VERSION_1_6;
    vm_args.nOptions = optionCount;
    vm_args.options = optionsArray;
    vm_args.ignoreUnrecognized = JNI_FALSE;

    /* load and initialize a Java VM, return a JNI interface pointer in env */
    //JNI_CreateJavaVM(&jvm, (void**)&env, &vm_args);
    //NSLog(@"JVM Options");
    //NSLog(@"-----------");
    //for (int i=0; i<optionCount; ++i) {
    //    NSLog(@"%s", optionsArray[i].optionString);
    //}
    NSLog(@"-----------");
    jint result = createJavaVM(&jvm, (void**)&env, &vm_args);
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
                NSLog(@"Unchecked Java exception in user block.  You should call env->ExceptionCheck() within the blocks you submit to doWithJvmThread.");
                env->ExceptionDescribe(); // Log exception details in case there is nothing else to do with it.
                // jthrowable ex = env->ExceptionOccurred(); // TODO: Send an error notification?
                env->ExceptionClear();
            }
            [self printErrors];
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

- (JNIEnv *) getEnv {
    JNIEnv *threadEnv = nil;
    jvm->GetEnv(reinterpret_cast<void**>(&threadEnv), JNI_VERSION_1_6);
    return threadEnv;
}

- (void) dumpClass:(jclass)cls {
    jclass methodClass = env->FindClass("java/lang/reflect/Method");
    jmethodID getGenericNameMethod = env->GetMethodID(methodClass, "toGenericString", "()Ljava/lang/String;");
    
    jclass classClass = env->FindClass("java/lang/Class");
    jmethodID getMethodsMethod = env->GetMethodID(classClass, "getDeclaredMethods", "()[Ljava/lang/reflect/Method;");
    
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

@end

static jint JNICALL my_vfprintf(FILE *fp, const char *format, va_list args)
{
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
