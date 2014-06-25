//
//  EmbeddedJvmTests.m
//  EmbeddedJvmTests
//
//  Created by Frank on 2013/10/1.
//  Copyright (c) 2013 Futurose. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "EmbeddedJvm.h"
#import "EmbeddedJvmTests.h"

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

static EJJvm *jvm = nil;

@implementation EmbeddedJvmTests
+(EJJvm *)getJvm {
    @synchronized(self) {
        if (jvm==nil) {
            NSArray *jars = [EJJvm findJars:@"/Users/frank/Futurose/Frameworks/EmbeddedJvm/Java/target"];
            NSArray *libs = [EJJvm findJars:@"/Users/frank/Futurose/Frameworks/EmbeddedJvm/Java/target/lib"];
            NSMutableArray *cp = [NSMutableArray arrayWithArray:jars];
            [cp addObjectsFromArray:libs];
//            [cp addObject:@"/Users/frank/Futurose/Frameworks/EmbeddedJvm/Java/target/lib/*"];
            NSError *error = nil;
            jvm = [[EJJvm alloc] initWithClassPaths:cp options:@[] error:&error];
            XCTAssertNil(error, @"Should successfully create JVM for test");
        }
    }
    return jvm;
}

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
    //EJJvm *jvm = [[EJJvm alloc] initWithClassPaths:@[@"jre/lib/*.jar"] options:@[] error:&error];
    EJJvm *jvm = [EmbeddedJvmTests getJvm];
    XCTAssertNotNil(jvm, @"JVM should successfully initialize");
}

-(void)testDispatchingJvmBlock {
    EJJvm *jvm = [EmbeddedJvmTests getJvm];
    XCTAssertNotNil(jvm, @"JVM should successfully initialize");
    
    //Waiter *waiter = [[Waiter alloc] init];
    __block NSString *result = nil;
    __block jint mreturn = 0;
    
    [jvm callJvmSyncVoid:^(JNIEnv *env) {
        jclass cls = env->FindClass("com/futurose/embeddedjvm/TestClass");
        if (cls!=nil) {
            jmethodID mid = env->GetStaticMethodID(cls, "smethod2", "(Ljava/lang/String;)I");
            if (mid!=nil) {
                jstring param = env->NewStringUTF("This is a string");
                mreturn = env->CallStaticIntMethod(cls, mid, param);
                env->DeleteGlobalRef(param);
            }
            else {
                result = @"Could not find method";
            }
        }
        else {
            result = @"Could not find class";
        }
        //[waiter notify];
    }];
    //[waiter waitForSeconds:60];
    XCTAssertNil(result, @"Error result from JVM block");
    XCTAssertEqual(2, mreturn, @"Method2 return should be 2");
    //XCTFail(@"No implementation for \"%s\"", __PRETTY_FUNCTION__);
}

@end
