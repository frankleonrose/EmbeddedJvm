//
//  EmbeddedJvm.h
//  EmbeddedJvm
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "jni.h"

#define EJ_JVM_NATIVE(name, signature, fn) { const_cast<char *>(name), const_cast<char *>(signature), (void *) fn }

NSData *jbytesToData(jbyteArray bytes, JNIEnv *env);
jbyteArray dataToJbytes(NSData *data, JNIEnv *env);

/**
 EJJvm presents a block-based interface to a JVM hosted in your app.
 */
@interface EJJvm : NSObject

/** @name Create and Close */

/**
 Create an embedded JVM.
 
 The default classpath will include all .jar files within the app/Contents/Java folder.
 
 @param path An optional set of paths that will be prepended to the standard paths.  May be nil.
 @param options A dictionary of options
 @param error Optional error reporting.
 
 // @see -dataTaskWithRequest:completionHandler:
 // @warning Some warning
 */
- (EJJvm*) initWithClassPaths:(NSArray*)path options:(NSDictionary*)options error:(NSError**)error;

- (void) close;

/** @name Running JVM Code */

/**
 The workhorse of EJJvm. xx
 
 Operations with a JNIEnv object may happen only on sanctioned JVM threads.
 This asynchronous method enqueues a block of work and then runs it on the 
 main thread maintained by EJJvm.
 
 @param block The block of work that needs to happen on the JVM thread.
 */
- (void) doWithJvmThread:(void(^)(JNIEnv* env))block;
//- (JNIEnv *) getEnv;
@end

/**
 EJClass wraps a jclass with simplified calls to some common methods.
 The original jclass is available in order to use the full power of the 
 JNIEnv API.
 */
@interface EJClass : NSObject
/**
 Create an EJClass for the given class name.

 @param className The fully qualified class name in path format com/mycompany/myproject/MyClassName
 @param env The JNIEnv for the current operation.  Presumably you passed a void(^)(JNIEnv* env) block to EJJvm 
            doWithJvmThread and you are now within that block with a valid JNIEnv.
 @param error Optional error reporting.  If this method returns nil, the NSError object will contain
                information about what happened.  Pass nil to ignore error report.
 
 @return the EJClass wrapper or nil on error.
 */
- (id) initWithClassName:(NSString *)className env:(JNIEnv *)env error:(NSError**)error;
- (jobject) createObject:(JNIEnv *)env error:(NSError**)error; // Support passing signature and variable arg lists
- (jmethodID) getObjectMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError**)error;
- (jmethodID) getStaticMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError**)error;
- (BOOL) registerNativeMethods:(JNINativeMethod *)methods count:(int)count env:(JNIEnv *)env error:(NSError**)error;
- (void) printMethods:(JNIEnv *)env;

/**
 The wrapped jclass.
 
 EJClass can do a few common things as a convenience, but often you will refer
 to theclass in order to get things done, like creating objects, getting and setting 
 static values, or any reflection work.
 */
@property (readonly) jclass theclass;
@end
