//
//  JvmHost.h
//  JvmHost
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface JvmHost : NSObject {
    JavaVM *jvm;       /* denotes a Java VM */
    JNIEnv *env;       /* pointer to native method interface */
}
- (JvmHost*) init;
- (JvmHost*) initWithOptions:(NSDictionary*)options;
- (void)destroy;
@end
