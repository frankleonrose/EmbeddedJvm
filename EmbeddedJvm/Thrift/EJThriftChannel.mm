//
//  EJThriftChannel.m
//  EmbeddedJvm
//
//  Created by Frank on 2014/6/19.
//  Copyright (c) 2014 Futurose. All rights reserved.
//

#import "EJThriftChannel.h"
#import "EJThriftChannelTransport.h"
#import "EmbeddedJvm.h"
#import "TMemoryBuffer.h"
#import "TBinaryProtocol.h"

//static int receiveCount = 0;
//static const int ddLogLevel = LOG_LEVEL_VERBOSE;
#define DDLogError(a, ...)
#define DDLogInfo(a, ...) 
#define DDLogDebug(a, ...)

@interface EJThriftChannel ()
@property (nonatomic) id<EJThriftChannelDelegate> delegate;
@property (nonatomic, strong) EJJvm *jvm;

@property (nonatomic) jobject channelCounterpart;
@property (nonatomic) jmethodID callHostToJvmMethod;
@property (nonatomic) jmethodID closeMethod;

@property (assign) dispatch_queue_t eventQueue;

-(jbyteArray)callJvmToHost:(jbyteArray)bytes env:(JNIEnv *)env;
-(void)disconnect;
@end

JNIEXPORT jbyteArray callJvmToHost(JNIEnv *env, jclass clazz, jlong channelObject, jbyteArray bytes) {
    EJThriftChannel *channel = (__bridge EJThriftChannel *)((void *)channelObject);
    return [channel callJvmToHost:bytes env:env];
}

static jlong channelObject = 0;
JNIEXPORT jlong getChannel(JNIEnv *env, jclass clazz, jobject counter) {
    jlong ret = channelObject;
    channelObject = 0;
    return ret;
}

JNIEXPORT void releaseChannel(JNIEnv *env, jclass clazz, jlong channelObject) {
    // Use bride_transfer to assume responsibility for object.
    EJThriftChannel *channel = (__bridge_transfer EJThriftChannel *)((void *)channelObject);
    [channel disconnect];
}

static JNINativeMethod method_table[] = {
    EJ_JVM_NATIVE("callJvmToHost", "(J[B)[B", callJvmToHost),
    EJ_JVM_NATIVE("getChannel", "(Ljava/lang/Object;)J", getChannel),
    EJ_JVM_NATIVE("releaseChannel", "(J)V", releaseChannel),
};

@implementation EJThriftChannel
-(id)initWithDelegate:(id<EJThriftChannelDelegate>)delegate jvm:(EJJvm *)jvm channelClass:(NSString *)classname error:(NSError * __autoreleasing *)error {
    self = [super init];
    if (self) {
        self.delegate = delegate;
        
        
        self.eventQueue = dispatch_queue_create("EJThriftChannel", DISPATCH_QUEUE_PRIORITY_DEFAULT);
        
        if (jvm==nil) {
            // Create default JVM
            jvm = [[EJJvm alloc] initWithClassPaths:nil options:nil error:error];
            if (jvm==nil) {
                return nil;
            }
        }
        self.jvm = jvm;
        
        NSError *err = (NSError *)[self.jvm callJvmSyncObject:^(JNIEnv *env) {
            NSError *error = nil;
            BOOL success = [self connect:env channelClass:classname error:&error];
            if (!success) {
                [self logException:env];
            }
            return error;
        }];
        if (err!=nil) {
            if (error!=nil) {
                *error = err;
            }
            return nil;
        }
    }
    return self;
}

-(void)dealloc {
    [self close];
    dispatch_release(self.eventQueue);
}

-(void)close {
    dispatch_sync(self.eventQueue, ^{
        if (self.jvm!=nil) {
            // Capture properties
            jmethodID closeMethod = self.closeMethod;
            jobject channelCounterpart = self.channelCounterpart;
            [self.jvm callJvmAsyncVoid:^(JNIEnv *env) {
                if (channelCounterpart!=NULL) {
                    if (closeMethod!=NULL) {
                        env->CallObjectMethod(channelCounterpart, closeMethod);
                    }
                    env->DeleteGlobalRef(channelCounterpart);
                }
            } completion:nil];
            self.jvm = nil;
        }
    });
}

-(void)disconnect {
    //NSLog(@"Calling disconnect");
}

-(void)logException:(JNIEnv *)env {
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
}

-(BOOL)connect:(JNIEnv *)env channelClass:(NSString *)classname error:(NSError * __autoreleasing *)error {
    DDLogDebug(@"Connecting to Java class %@" classname);
    BOOL loading = YES;
    
    EJClass *cls = [[EJClass alloc] initWithClassName:classname env:env error:error];
    if (cls==nil) {
        loading = NO;
    }
    if (loading) {
        [cls printMethods:env];
        
        self.callHostToJvmMethod = [cls getObjectMethod:@"callHostToJvm" signature:@"([B)[B" env:env error:error];
        if (self.callHostToJvmMethod==nil) {
            loading = NO;
        }
    }
    if (loading) {
        self.closeMethod = [cls getObjectMethod:@"close" signature:@"()V" env:env error:error];
        if (self.closeMethod==nil) {
            loading = NO;
        }
    }
    if (loading) {
        loading = [cls registerNativeMethods:method_table count:3 env:env error:error];
    }
    if (loading) {
        assert(sizeof(EJThriftChannel *)<=sizeof(jobject)); // jobject memo type is at least as large as what we're putting in it
        channelObject = (jlong)((__bridge_retained jobject)self);
        self.channelCounterpart = [cls createObject:env error:error signature:@"()V"];
        if (self.channelCounterpart==nil) {
            loading = NO;
        }
    }
    return loading; // YES means Loaded
}

-(jbyteArray)callJvmToHost:(jbyteArray)bytes env:(JNIEnv *)env {
    //    NSLog(@"receiveEvent BEGIN %d", ++receiveCount);
    NSData *data = EJJBytesToData(bytes, env);
    
    TMemoryBuffer *inTransport = [[TMemoryBuffer alloc] initWithData:data];
    TBinaryProtocol *inProtocol = [[TBinaryProtocol alloc] initWithTransport:inTransport];
    TMemoryBuffer *outTransport = [[TMemoryBuffer alloc] init];
    TBinaryProtocol *outProtocol = [[TBinaryProtocol alloc] initWithTransport:outTransport];
    
    // Try dispatching so that we're not running this code on a Java thread.
    // dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    dispatch_sync(self.eventQueue, ^{
        id<TProcessor> processor = [self.delegate makeProcessor];
        [processor processOnInputProtocol:inProtocol outputProtocol:outProtocol];
    });
    
    NSData *outBytes = [outTransport getBuffer];
    jbyteArray response = EJDataToJBytes(outBytes, env);
    //    NSLog(@"receiveEvent END %d", receiveCount++);
    return response;
}

- (void)doWithClient:(void(^)(NSObject *client))block {
    [self.jvm callJvmSyncVoid:^(JNIEnv *env) {
        TMemoryBuffer *transport = [[EJThriftChannelTransport alloc] initWithEnv:env receiver:self.channelCounterpart andMethod:self.callHostToJvmMethod];
        TBinaryProtocol *protocol = [[TBinaryProtocol alloc] initWithTransport:transport];
        
        NSObject *client = [self.delegate makeClientWithProtocol:protocol];
        
        block(client);
    }];
}

- (id)doWithClientReturnObject:(id(^)(NSObject *client))block {
    return [self.jvm callJvmSyncObject:^(JNIEnv *env) {
        id ret = nil;
        TMemoryBuffer *transport = [[EJThriftChannelTransport alloc] initWithEnv:env receiver:self.channelCounterpart andMethod:self.callHostToJvmMethod];
        TBinaryProtocol *protocol = [[TBinaryProtocol alloc] initWithTransport:transport];
        
        NSObject *client = [self.delegate makeClientWithProtocol:protocol];
        
        ret = block(client);
        return ret;
    }];
}

@end
