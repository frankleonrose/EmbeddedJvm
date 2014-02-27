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

@interface EmbeddedJvm : NSObject
- (EmbeddedJvm*) initWithClassPaths:(NSArray*)path options:(NSDictionary*)options error:(NSError**)error;
- (void) close;

- (void) doWithJvmThread:(void(^)(JNIEnv* env))block;
- (JNIEnv *) getEnv;
@end

@interface JvmClass : NSObject
- (id) initWithClassName:(NSString *)className env:(JNIEnv *)env error:(NSError**)error;
- (jobject) createObject:(JNIEnv *)env error:(NSError**)error;
- (jmethodID) getObjectMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError**)error;
- (jmethodID) getStaticMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError**)error;
- (BOOL) registerNativeMethods:(JNINativeMethod *)methods count:(int)count env:(JNIEnv *)env error:(NSError**)error;
- (void) printMethods:(JNIEnv *)env;
@property (readonly) jclass jclass;
@end
