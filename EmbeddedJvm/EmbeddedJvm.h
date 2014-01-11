//
//  EmbeddedJvm.h
//  EmbeddedJvm
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "jni.h"

NSData *jbytesToData(jbyteArray bytes, JNIEnv *env);
jbyteArray dataToJbytes(NSData *data, JNIEnv *env);

@interface EmbeddedJvm : NSObject
- (EmbeddedJvm*) initWithClassPaths:(NSArray*)path options:(NSDictionary*)options error:(NSError**)error;
- (void) close;

- (void) doWithJvmThread:(void(^)(JNIEnv* env))block;
- (JNIEnv *) getEnv;

- (void) dumpClass:(jclass)cls;
@end
