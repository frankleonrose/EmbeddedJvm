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
- (id) initWithClassName:(NSString *)className env:(JNIEnv *)env error:(NSError * __autoreleasing *)error;
/**
 Create an object of the represented class using the default (no parameter) constructor.
 
 @param env The JNIEnv for the current operation.  Presumably you passed a void(^)(JNIEnv* env) block to EJJvm
 doWithJvmThread and you are now within that block with a valid JNIEnv.
 @param error Optional error reporting.  If this method returns nil, the NSError object will contain
 information about what happened.  Pass nil to ignore error report.
 
 @return the newly created jobject or nil on error.
 */
- (jobject) createObject:(JNIEnv *)env error:(NSError * __autoreleasing *)error;
/**
 Create an object of the represented class using the default (no parameter) constructor.
 
 @param env The JNIEnv for the current operation.  Presumably you passed a void(^)(JNIEnv* env) block to EJJvm
 doWithJvmThread and you are now within that block with a valid JNIEnv.
 @param error Optional error reporting.  If this method returns nil, the NSError object will contain
 information about what happened.  Pass nil to ignore error report.
 @param signature Required constructor signature in JNI string format. Constructor signature return value must be 'V'.
 For example, "([L/java/lang/String;)V" is the signature of a constructor taking an array of String.
 @param ... Variable argument list of JNI types passed to constructor.
 
 @return the newly created jobject or nil on error.
 */
- (jobject) createObject:(JNIEnv *)env error:(NSError * __autoreleasing *)error signature:(NSString *)signature, ...;
/**
 Retrieve the jmethodID for an object method on the represented class.
 
 @param methodName the name of the method
 @param methodSignature the method signature in JNI string format.  For example, "(L/java/lang/String;I[B)V" is the signature of a method taking String, int, and an array of bytes, returning void.
 @param env The JNIEnv for the current operation.  @see initWithClassName:env:error:
 @param error Optional error reporting.  @see initWithClassName:env:error:
 
 @return the jmethodID or nil on error.
 */
- (jmethodID) getObjectMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError * __autoreleasing *)error;
/**
 Retrieve the jmethodID for a static method on the represented class.
 
 @param methodName the name of the method
 @param methodSignature the method signature in JNI string format.  For example, "(L/java/lang/String;I[B)V" is the signature of a method taking String, int, and an array of bytes, returning void.
 @param env The JNIEnv for the current operation.  @see initWithClassName:env:error:
 @param error Optional error reporting.  @see initWithClassName:env:error:
 
 @return the jmethodID or nil on error.
 */
- (jmethodID) getStaticMethod:(NSString *)methodName signature:(NSString *)methodSignature env:(JNIEnv *)env error:(NSError * __autoreleasing *)error;
/**
 Register C function calls to be linked to Java native methods.
 
 The following is an example of the method table to pass to registerNativeMethods.
 
<code>
 
     // Forward declaration of cFunction
     JNIEXPORT jbyteArray cFunction(JNIEnv *env, jobject obj, jbyteArray bytes);
 
     static JNINativeMethod method_table[] = {
         { const_cast<char *>("javaMethodName"), const_cast<char *>("([B)[B"), (void *) cFunction }
         // The identical entry using a convenience macro for all the casts
         EJ_JVM_NATIVE("javaMethodName", "([B)[B", cFunction),
     };
 
</code>
 
 @param methods an array of JNINativeMethod structures
 @param count the count of JNINativeMethod structures in the array
 @param env The JNIEnv for the current operation.  @see initWithClassName:env:error:
 @param error Optional error reporting.  @see initWithClassName:env:error:
 
 @return YES if successful, NO if unsuccessful.
 */
- (BOOL) registerNativeMethods:(JNINativeMethod *)methods count:(int)count env:(JNIEnv *)env error:(NSError * __autoreleasing *)error;
/**
 Print the names and signatures of the methods of the represented class.

 This method is useful when debugging signatures.
 
 @param env The JNIEnv for the current operation.  @see initWithClassName:env:error:
 */
- (void) printMethods:(JNIEnv *)env;

/**
 The wrapped jclass.
 
 EJClass can do a few common things as a convenience, but often you will refer
 to theclass in order to get things done, like creating objects, getting and setting
 static values, or any reflection work.
 */
@property (readonly) jclass theClass;
@end
