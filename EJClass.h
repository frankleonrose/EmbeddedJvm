//
//  EJClass.h
//  Pods
//
//  Created by Frank on 2014/2/28.
//
//

#import <Foundation/Foundation.h>
#import "jni.h"

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
