//
//  EJClassTest.m
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/23.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "EJJvm.h"
#import "EJClass.h"
#import "EmbeddedJvmTests.h"
#import "EmbeddedJvm.h"

NSString *method2Param = nil;
JNIEXPORT void method1(JNIEnv *env, jclass clazz) {
}
JNIEXPORT jint method2(JNIEnv *env, jclass clazz, jstring param) {
    return 2;
}
JNIEXPORT jobject method3(JNIEnv *env, jclass clazz, jstring param, jint i) {
    return param;
}

static JNINativeMethod method_table[] = {
    EJ_JVM_NATIVE("method1", "()V", method1),
    EJ_JVM_NATIVE("method2", "(Ljava/lang/String;)I", method2),
    EJ_JVM_NATIVE("method3", "(Ljava/lang/String;I)Ljava/lang/Object;", method3),
};

@interface EJClassTest : XCTestCase
@property EJJvm *jvm;
@end

@implementation EJClassTest

- (void)setUp
{
    [super setUp];
    self.jvm = [EmbeddedJvmTests getJvm];
}

- (void)tearDown
{
    //[self.jvm close];
    self.jvm = nil;
    [super tearDown];
}

- (void)testAttachClass
{
    __block NSError *error = nil;
    __block EJClass *cls = nil;
    [self.jvm callJvmSyncVoid:^(JNIEnv *env) {
        cls = [[EJClass alloc] initWithClassName:@"com/futurose/embeddedjvm/TestClass" env:env error:&error];
    }];
    
    XCTAssertNotNil(cls, @"EJClass object not nil");
    XCTAssertNil(error, @"Error should be nil");
}

- (void)testUnknownClass
{
    __block NSError *error = nil;
    __block EJClass *cls = nil;
    [self.jvm callJvmSyncVoid:^(JNIEnv *env) {
        cls = [[EJClass alloc] initWithClassName:@"com/futurose/embeddedjvm/XYZ" env:env error:&error];
    }];
    
    XCTAssertNil(cls, @"EJClass object should be nil");
    XCTAssertNotNil(error, @"Error should be set");
}

- (void)testNatives
{
    __block NSError *error = nil;
    __block EJClass *cls = nil;
    __block BOOL registered = NO;
    __block jobject obj;
    [self.jvm callJvmSyncVoid:^(JNIEnv *env) {
        cls = [[EJClass alloc] initWithClassName:@"com/futurose/embeddedjvm/TestClassWithNatives" env:env error:&error];
        registered = [cls registerNativeMethods:method_table count:3 env:env error:&error];
        obj = [cls createObject:env error:&error];
    }];
    
    XCTAssertNotNil(cls, @"EJClass object not nil");
    XCTAssertEqual(YES, registered, @"Successfully register");
    XCTAssertNotEqual(NULL, obj, @"Object should be created");
    XCTAssertNil(error, @"Error should be nil");
}

@end
