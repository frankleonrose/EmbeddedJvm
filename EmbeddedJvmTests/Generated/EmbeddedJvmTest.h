/**
 * Autogenerated by Thrift Compiler (1.0.0-dev)
 *
 * DO NOT EDIT UNLESS YOU ARE SURE THAT YOU KNOW WHAT YOU ARE DOING
 *  @generated
 */

#import <Foundation/Foundation.h>

#import "TProtocol.h"
#import "TApplicationException.h"
#import "TProtocolException.h"
#import "TProtocolUtil.h"
#import "TProcessor.h"
#import "TObjective-C.h"
#import "TBase.h"


@protocol TestHostToJvm <NSObject>
- (NSString *) echoString: (NSString *) s;  // throws TException
- (NSData *) echoBinary: (NSData *) b;  // throws TException
- (void) throwException;  // throws TException
@end

@interface TestHostToJvmClient : NSObject <TestHostToJvm> {
  id <TProtocol> inProtocol;
  id <TProtocol> outProtocol;
}
- (id) initWithProtocol: (id <TProtocol>) protocol;
- (id) initWithInProtocol: (id <TProtocol>) inProtocol outProtocol: (id <TProtocol>) outProtocol;
@end

@interface TestHostToJvmProcessor : NSObject <TProcessor> {
  id <TestHostToJvm> mService;
  NSDictionary * mMethodMap;
}
- (id) initWithTestHostToJvm: (id <TestHostToJvm>) service;
- (id<TestHostToJvm>) service;
@end

@protocol TestJvmToHost <NSObject>
- (NSString *) echoStringB: (NSString *) s;  // throws TException
- (NSData *) echoBinaryB: (NSData *) b;  // throws TException
- (void) throwExceptionB;  // throws TException
@end

@interface TestJvmToHostClient : NSObject <TestJvmToHost> {
id <TProtocol> inProtocol;
id <TProtocol> outProtocol;
}
- (id) initWithProtocol: (id <TProtocol>) protocol;
- (id) initWithInProtocol: (id <TProtocol>) inProtocol outProtocol: (id <TProtocol>) outProtocol;
@end

@interface TestJvmToHostProcessor : NSObject <TProcessor> {
id <TestJvmToHost> mService;
NSDictionary * mMethodMap;
}
- (id) initWithTestJvmToHost: (id <TestJvmToHost>) service;
- (id<TestJvmToHost>) service;
@end

@interface EmbeddedJvmTestConstants : NSObject {
}
@end
