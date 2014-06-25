//
//  EJThriftTest.m
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/23.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "EJThriftChannel.h"
#import "EmbeddedJvmTests.h"
#import "EmbeddedJvmTest.h"

@interface EchoImpl : NSObject<TestJvmToHost>
@end

@implementation EchoImpl
- (NSString *) echoStringB: (NSString *) s {
    return s;
}
- (NSData *) echoBinaryB: (NSData *) b {
    return b;
}
- (void) throwExceptionB {
    @throw [[TException alloc] initWithName:@"TestException" reason:@"Specification" userInfo:@{}];
}
@end

@interface EchoDelegate : NSObject<EJThriftChannelDelegate>
@end

@implementation EchoDelegate
-(NSObject<TProcessor> *)makeProcessor {
    EchoImpl *echo = [[EchoImpl alloc] init];
    TestJvmToHostProcessor *processor = [[TestJvmToHostProcessor alloc] initWithTestJvmToHost:echo];
    return processor;
}
-(NSObject *)makeClientWithProtocol:(NSObject<TProtocol> *)protocol {
    TestHostToJvmClient *client = [[TestHostToJvmClient alloc] initWithProtocol:protocol];
    return client;
}
@end

@interface EJThriftTest : XCTestCase
@property EJJvm *jvm;
@end

@implementation EJThriftTest

- (void)setUp
{
    [super setUp];
    self.jvm = [EmbeddedJvmTests getJvm];
}

- (void)tearDown
{
    self.jvm = nil;
    [super tearDown];
}

- (void)testChannel
{
    EchoDelegate *delegate = [[EchoDelegate alloc] init];
    NSError *error = nil;
    EJThriftChannel *channel = [[EJThriftChannel alloc] initWithDelegate:delegate jvm:self.jvm channelClass:@"com/futurose/embeddedjvm/TestThriftChannel" error:&error];
    
    __block NSString *echo;
    [channel doWithClient:^(NSObject *c) {
        TestHostToJvmClient *client = (TestHostToJvmClient *)c;
        echo = [client echoString:@"string"];
    }];
    
    XCTAssertNotNil(channel, @"EJClass object should be initialized");
    XCTAssertNil(error, @"Error should be nil");
    XCTAssertTrue([echo isEqualToString:@"string"], @"Response should be true echo");
}

@end
