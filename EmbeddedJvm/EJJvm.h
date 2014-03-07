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
- (EJJvm*) initWithClassPaths:(NSArray*)path options:(NSDictionary*)options error:(NSError * __autoreleasing *)error;

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

