//
//  GeckoRuntimeBridge.mm
//  Reynard
//
//  Created by Minh Ton on 24/5/26.
//

#import "GeckoRuntimeBridge.h"

#import "mozilla-config.h"
#import <dlfcn.h>
#import <unistd.h>

// AssertionServices is loaded only for the entitled TrollStore background
// window. These selectors are runtime checked; ordinary installs use UIKit.
// SPI signatures: nst/iOS-Runtime-Headers, AssertionServices/BKSProcessAssertion.h
// Flags/reason: WebKit's AssertionServicesSPI.h (FinishTaskUnbounded).
@protocol RYNBackgroundAssertion <NSObject>
- (instancetype)initWithPID:(int)pid flags:(unsigned int)flags
                     reason:(unsigned int)reason name:(NSString *)name
                withHandler:(void (^)(BOOL))handler;
- (BOOL)isValid;
- (void)invalidate;
@end

@interface GeckoRuntimeBridge ()
+ (void)beginBackgroundActivityForOwner:(NSString *)owner;
+ (void)endBackgroundActivityForOwner:(NSString *)owner;
@end

static NSMutableSet<NSNumber *> *sBackgroundProcesses;
static NSMutableDictionary<NSNumber *, id<RYNBackgroundAssertion>> *sBackgroundAssertions;
static NSMutableSet<NSString *> *sBackgroundOwners;

static void AcquireBackgroundAssertion(int32_t pid) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices", RTLD_LAZY);
    });
    Class assertionClass = NSClassFromString(@"BKSProcessAssertion");
    if (!assertionClass ||
        ![assertionClass instancesRespondToSelector:@selector(initWithPID:flags:reason:name:withHandler:)] ||
        ![assertionClass instancesRespondToSelector:@selector(isValid)] ||
        ![assertionClass instancesRespondToSelector:@selector(invalidate)]) {
        NSLog(@"Reynard: background assertion API unavailable");
        return;
    }
    if (sBackgroundAssertions[@(pid)]) { return; }
    // PreventTaskSuspend | AllowIdleSleep. Do not request foreground GPU/UI
    // priority or keep the screen awake while continuing the page's network work.
    id<RYNBackgroundAssertion> assertion = [(id<RYNBackgroundAssertion>)[assertionClass alloc]
        initWithPID:pid flags:5 reason:10004 name:@"Reynard network activity"
        withHandler:^(BOOL acquired) {
            NSLog(@"Reynard: background assertion PID %d %@", pid,
                  acquired ? @"acquired" : @"denied");
        }];
    if (assertion) { sBackgroundAssertions[@(pid)] = assertion; }
}

@implementation GeckoRuntimeBridge

+ (NSString *)version {
    return @MOZILLA_VERSION;
}

+ (void)registerBackgroundProcess:(int32_t)pid {
    NSAssert([NSThread isMainThread], @"Background process registry must use the main thread");
    if (pid <= 1) { return; }
    if (!sBackgroundProcesses) { sBackgroundProcesses = [NSMutableSet set]; }
    [sBackgroundProcesses addObject:@(pid)];
    if (sBackgroundOwners.count > 0) { AcquireBackgroundAssertion(pid); }
}

+ (void)removeBackgroundProcess:(int32_t)pid {
    NSAssert([NSThread isMainThread], @"Background process registry must use the main thread");
    [sBackgroundProcesses removeObject:@(pid)];
    [sBackgroundAssertions[@(pid)] invalidate];
    [sBackgroundAssertions removeObjectForKey:@(pid)];
}

+ (void)beginBackgroundGrace {
    [self beginBackgroundActivityForOwner:@"live-page"];
}

+ (void)beginBackgroundDownloadGrace {
    [self beginBackgroundActivityForOwner:@"downloads"];
}

+ (void)beginBackgroundActivityForOwner:(NSString *)owner {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    if (!sBackgroundOwners) { sBackgroundOwners = [NSMutableSet set]; }
    [sBackgroundOwners addObject:owner];
    if (!sBackgroundAssertions) { sBackgroundAssertions = [NSMutableDictionary dictionary]; }
    AcquireBackgroundAssertion(getpid());
    for (NSNumber *pid in sBackgroundProcesses) {
        AcquireBackgroundAssertion(pid.intValue);
    }
}

+ (BOOL)hasBackgroundGrace {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    return [sBackgroundOwners containsObject:@"live-page"] && [sBackgroundAssertions[@(getpid())] isValid];
}

+ (void)endBackgroundGrace {
    [self endBackgroundActivityForOwner:@"live-page"];
}

+ (BOOL)hasBackgroundDownloadGrace {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    return [sBackgroundOwners containsObject:@"downloads"] && [sBackgroundAssertions[@(getpid())] isValid];
}

+ (void)endBackgroundDownloadGrace {
    [self endBackgroundActivityForOwner:@"downloads"];
}

+ (void)endBackgroundActivityForOwner:(NSString *)owner {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    [sBackgroundOwners removeObject:owner];
    if (sBackgroundOwners.count > 0) { return; }
    for (id<RYNBackgroundAssertion> assertion in sBackgroundAssertions.allValues) {
        [assertion invalidate];
    }
    [sBackgroundAssertions removeAllObjects];
}

@end
