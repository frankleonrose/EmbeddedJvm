//
//  EJThriftChannel.h
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/19.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import "TProcessor.h"

@class EJJvm;

@protocol EJThriftChannelDelegate <NSObject>
-(NSObject<TProcessor> *)makeProcessor;
-(NSObject *)makeClientWithProtocol:(NSObject<TProtocol> *)protocol;
@end

@interface EJThriftChannel : NSObject
-(id)initWithDelegate:(id<EJThriftChannelDelegate>)delegate jvm:(EJJvm *)jvm channelClass:(NSString *)classname error:(NSError * __autoreleasing *)error;
-(void)close;

-(void)doWithClient:(void(^)(NSObject *client))block;
-(id)doWithClientReturnObject:(id(^)(NSObject *client))block;
@end
