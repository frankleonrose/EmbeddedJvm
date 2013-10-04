//
//  EmbeddedJvmTests.m
//  EmbeddedJvmTests
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "EmbeddedJvm.h"

// One shot waiter.  Create a new one to wait again so that there are no notify messages coming in from prior async calls.
@interface Waiter : NSObject 
-(id)init;
-(BOOL)waitForSeconds:(NSTimeInterval)seconds;
-(void)notify;
@property BOOL done;
@end

@implementation Waiter
-(id)init {
    if (self = [super init]) {
        self.done = false;
    }
    return self;
}

-(BOOL)waitForSeconds:(NSTimeInterval)seconds {
    assert(seconds>0.0);
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while(!self.done && timeout==[timeout laterDate:[NSDate date]]) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
    }
    return self.done;
}

-(void)notify {
    self.done = true;
}
@end

@interface EmbeddedJvmTests : XCTestCase

@end

@implementation EmbeddedJvmTests

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)testJvmCreation
{
    NSError *error = nil;
    EmbeddedJvm *jvm = [[EmbeddedJvm alloc] initWithClassPaths:@[@"jre/lib/*.jar"] options:@{} error:&error];
    XCTAssertNotNil(jvm, @"JVM should successfully initialize");
}

-(void)testDispatchingJvmBlock {
    NSError *error = nil;
    EmbeddedJvm *jvm = [[EmbeddedJvm alloc] initWithClassPaths:@[@"jre/lib/*"] options:@{} error:&error];
    XCTAssertNotNil(jvm, @"JVM should successfully initialize");
    if (jvm==nil) { return; }

    Waiter *waiter = [[Waiter alloc] init];
    __block NSString *result;
    
    [jvm doWithJvmThread:^(JNIEnv *env) {
        /* invoke the Main.test method using the JNI */
        jclass cls = env->FindClass("com/futurose/filaware/App");
        if (cls!=nil) {
            [jvm dumpClass:cls];
            jmethodID mid = env->GetStaticMethodID(cls, "test", "(I)V");
            if (mid!=nil) {
                env->CallStaticVoidMethod(cls, mid, 100);
            }
            else {
                result = @"Could not find method";
            }
        }
        else {
            result = @"Could not find class";
        }
        [waiter notify];
    }];
    [waiter waitForSeconds:60];
    XCTAssertNil(result, @"Error result from JVM block");
    //XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

@end
