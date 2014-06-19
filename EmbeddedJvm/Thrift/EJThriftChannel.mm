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

static EJThriftChannel *channel = nil; // TODO: pass channel to receiveEvent method to eliminate this global

@interface EJThriftChannel ()
#define STATUS_INITIAL 0
#define STATUS_LOADED 1
#define STATUS_FAILED -1
@property int status;

@property (nonatomic) id<EJThriftChannelDelegate> delegate;
@property (nonatomic, strong) EJJvm *jvm;
@property (nonatomic) jobject channelCounterpart;
@property (nonatomic) jmethodID receiveCommandMethod;
@property (assign) dispatch_queue_t eventQueue;

-(jbyteArray)receiveEvent:(jbyteArray)bytes env:(JNIEnv *)env;
@end

JNIEXPORT jbyteArray receiveEvent(JNIEnv *env, jclass clazz, jbyteArray bytes) {
    return [channel receiveEvent:bytes env:env];
}

static JNINativeMethod method_table[] = {
    EJ_JVM_NATIVE("receiveEvent", "([B)[B", receiveEvent),
    //    { const_cast<char *>("receiveEvent"), const_cast<char *>("([B)[B"), (void *) receiveEvent }
};

@implementation EJThriftChannel
-(id)initWithDelegate:(id<EJThriftChannelDelegate>)delegate {
    self = [super init];
    if (self) {
        self.delegate = delegate;
        
        self.status = STATUS_INITIAL;
        self.eventQueue = dispatch_queue_create("EJThriftChannel", DISPATCH_QUEUE_PRIORITY_DEFAULT);
        
        NSError *error = nil;
        self.jvm = [[EJJvm alloc] initWithClassPaths:nil options:nil error:&error];
        if (self.jvm==nil) {
            DDLogError(@"Failed to load JVM: %@", error);
            return nil;
        }
        else {
            DDLogInfo(@"Loaded JVM");
        }
        [self.jvm callJvmSyncVoid:^(JNIEnv *env) {
            NSError *error = nil;
            int status = [self connect:env error:&error];
            if (status==STATUS_FAILED) {
                DDLogError([error description]);
                [self logException:env];
            }
        }];
        
        channel = self;
    }
    return self;
}

-(void)dealloc {
    self.jvm = nil;
    dispatch_release(self.eventQueue);
}

-(void)close {
    [self.jvm close];
    channel = nil;
}

-(void)logException:(JNIEnv *)env {
    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
}

#define ENGINE_COMMANDS_CLASS @"com/futurose/fotocounter/EngineApi"

-(int)connect:(JNIEnv *)env error:(NSError * __autoreleasing *)error {
    if (self.status==STATUS_INITIAL) {
        DDLogDebug(@"Connecting to Java class " ENGINE_COMMANDS_CLASS);
        BOOL loading = YES;
        
        EJClass *cls = [[EJClass alloc] initWithClassName:ENGINE_COMMANDS_CLASS env:env error:error];
        if (cls==nil) {
            loading = NO;
        }
        if (loading) {
            [cls printMethods:env];
            
            self.receiveCommandMethod = [cls getObjectMethod:@"receiveCommand" signature:@"([B)[B" env:env error:error];
            if (self.receiveCommandMethod==nil) {
                loading = NO;
            }
        }
        if (loading) {
            BOOL success = [cls registerNativeMethods:method_table count:1 env:env error:error];
            if (!success) {
                loading = NO;
            }
        }
        if (loading) {
            self.channelCounterpart = [cls createObject:env error:error];
            if (self.channelCounterpart==nil) {
                loading = NO;
            }
        }
        if (loading) {
            DDLogDebug(@"Connected successfully");
            self.status = STATUS_LOADED;
        }
        else {
            self.status = STATUS_FAILED;
        }
    }
    return self.status;
}

-(jbyteArray)receiveEvent:(jbyteArray)bytes env:(JNIEnv *)env {
    //    NSLog(@"receiveEvent BEGIN %d", ++receiveCount);
    NSData *data = EJJBytesToData(bytes, env);
    
    TMemoryBuffer *inTransport = [[TMemoryBuffer alloc] initWithData:data];
    TBinaryProtocol *inProtocol = [[TBinaryProtocol alloc] initWithTransport:inTransport];
    TMemoryBuffer *outTransport = [[TMemoryBuffer alloc] init];
    TBinaryProtocol *outProtocol = [[TBinaryProtocol alloc] initWithTransport:outTransport];
    
    // Try dispatching so that we're not running this code on a Java thread.
    // dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
    dispatch_sync(self.eventQueue, ^{
        id<TProcessor> processor = [self.delegate makeEventProcessor];
        [processor processOnInputProtocol:inProtocol outputProtocol:outProtocol];
    });
    
    NSData *outBytes = [outTransport getBuffer];
    jbyteArray response = EJDataToJBytes(outBytes, env);
    //    NSLog(@"receiveEvent END %d", receiveCount++);
    return response;
}

- (void)doWithClient:(void(^)(NSObject *client))block {
    [self.jvm callJvmSyncVoid:^(JNIEnv *env) {
        NSError *error = nil;
        int status = [self connect:env error:&error];
        if (error!=nil) {
            DDLogError([error description]);
            [self logException:env];
        }
        if (status==STATUS_LOADED) {
            TMemoryBuffer *transport = [[EJThriftChannelTransport alloc] initWithEnv:env receiver:self.channelCounterpart andMethod:self.receiveCommandMethod];
            TBinaryProtocol *protocol = [[TBinaryProtocol alloc] initWithTransport:transport];
            
            NSObject *client = [self.delegate makeCommandInterfaceWithProtocol:protocol];
            
            block(client);
        }
    }];
}

- (id)doWithClientReturnObject:(id(^)(NSObject *client))block {
    return [self.jvm callJvmSyncObject:^(JNIEnv *env) {
        NSError *error = nil;
        int status = [self connect:env error:&error];
        id ret = nil;
        if (error!=nil) {
            DDLogError([error description]);
            [self logException:env];
        }
        else if (status==STATUS_LOADED) {
            TMemoryBuffer *transport = [[EJThriftChannelTransport alloc] initWithEnv:env receiver:self.channelCounterpart andMethod:self.receiveCommandMethod];
            TBinaryProtocol *protocol = [[TBinaryProtocol alloc] initWithTransport:transport];
            
            NSObject *client = [self.delegate makeCommandInterfaceWithProtocol:protocol];
            
            ret = block(client);
        }
        return ret;
    }];
}

@end
