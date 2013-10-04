//
//  EmbeddedJvm.h
//  EmbeddedJvm
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "jni.h"

@interface EmbeddedJvm : NSObject
- (EmbeddedJvm*) initWithClassPaths:(NSArray*)path options:(NSDictionary*)options error:(NSError**)error;
- (void) close;

- (void) doWithJvmThread:(void(^)(JNIEnv* env))block;

- (void) dumpClass:(jclass)cls;
@end
