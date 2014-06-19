//
//  EJThriftChannel.h
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/19.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import "TProcessor.h"

@protocol EJThriftChannelDelegate <NSObject>
-(NSObject<TProcessor> *)makeEventProcessor;
-(NSObject *)makeCommandInterfaceWithProtocol:(NSObject<TProtocol> *)protocol;
@end

@interface EJThriftChannel : NSObject
-(id)initWithDelegate:(id<EJThriftChannelDelegate>)delegate;
-(void)close;
-(void)doWithClient:(void(^)(NSObject *client))block;
-(id)doWithClientReturnObject:(id(^)(NSObject *client))block;
@end
