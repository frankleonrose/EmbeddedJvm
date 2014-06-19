//
//  EJThriftChannelTransport.m
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/18.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import "EJThriftChannelTransport.h"
#import "TProtocolException.h"

@implementation EJThriftChannelTransport
- (id)initWithEnv:(JNIEnv *)e receiver:(jobject)rcv andMethod:(jmethodID)mth {
    if (self = [super init]) {
        env = e;
        receiver = rcv;
        method = mth;
    }
    return self;
}

- (void)flush {
    [super flush];
    
    // Get bytes written by protocol and make a Java byte array.
    NSData *data = [self getBuffer];
    jbyteArray bytes = EJDataToJBytes(data, env);
    
    // Pass protocol written bytes to processor function in Java land...
    jbyteArray response = (jbyteArray)env->CallObjectMethod(receiver, method, bytes);
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        // Error in communication sending command to client.
        @throw [TProtocolException exceptionWithName: @"TProtocolException"
                                              reason: @"Exception in Engine's Thrift receiver"];
    }
    
    // Convert response byte array into an NSData buffer to be read by protocol receiver
    data = EJJBytesToData(response, env);
    mBuffer = [data mutableCopy];
    mOffset = 0;
}
@end
