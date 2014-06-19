//
//  EJThriftChannelTransport.h
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/18.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "TMemoryBuffer.h"
#import "EmbeddedJvm.h"

@interface EJThriftChannelTransport : TMemoryBuffer {
    JNIEnv *env;
    jobject receiver;
    jmethodID method; // Method that takes a byte array as parameter and returns a byte array.
}
- (id)initWithEnv:(JNIEnv *)env receiver:(jobject)rcv andMethod:(jmethodID)method;
- (void)flush;
@end
