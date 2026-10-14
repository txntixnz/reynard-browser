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
static NSMutableArray<NSString *> *sDiagnosticEvents;
static const NSUInteger kDiagnosticEventLimit = 240;

static NSString *DiagnosticLogPath() {
    NSString *directory = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [directory stringByAppendingPathComponent:@"ReynardConnectionDiagnostics.log"];
}

static void LoadDiagnosticEvents() {
    if (sDiagnosticEvents) { return; }
    sDiagnosticEvents = [NSMutableArray array];
    NSString *previous = [NSString stringWithContentsOfFile:DiagnosticLogPath()
                                                 encoding:NSUTF8StringEncoding error:NULL];
    for (NSString *line in [previous componentsSeparatedByString:@"\n"]) {
        if (line.length > 0) { [sDiagnosticEvents addObject:line]; }
    }
    if (sDiagnosticEvents.count > kDiagnosticEventLimit) {
        [sDiagnosticEvents removeObjectsInRange:NSMakeRange(0, sDiagnosticEvents.count - kDiagnosticEventLimit)];
    }
}

// Only internal lifecycle/process labels belong here, never webpage text,
// request URLs, headers, cookies or credentials. Retain a bounded last session
// across an OS termination, so a force quit does not erase the evidence.
static void RecordDiagnostic(NSString *message) {
    if (![NSThread isMainThread]) {
        NSString *copy = [message copy];
        dispatch_async(dispatch_get_main_queue(), ^{ RecordDiagnostic(copy); });
        return;
    }
    LoadDiagnosticEvents();
    NSString *singleLine = [[message componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsJoinedByString:@" "];
    if (singleLine.length > 1024) { singleLine = [singleLine substringToIndex:1024]; }
    [sDiagnosticEvents addObject:[NSString stringWithFormat:@"%@ uptime=%.0f %@",
                                 [NSDate date], NSProcessInfo.processInfo.systemUptime, singleLine]];
    if (sDiagnosticEvents.count > kDiagnosticEventLimit) { [sDiagnosticEvents removeObjectAtIndex:0]; }
    NSString *report = [[sDiagnosticEvents componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    [report writeToFile:DiagnosticLogPath() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

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
        RecordDiagnostic(@"background assertion API unavailable");
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
            RecordDiagnostic([NSString stringWithFormat:@"background assertion pid=%d %@", pid,
                              acquired ? @"acquired" : @"denied"]);
        }];
    if (assertion) { sBackgroundAssertions[@(pid)] = assertion; }
}

@implementation GeckoRuntimeBridge

+ (void)recordDiagnostic:(NSString *)message {
    RecordDiagnostic(message);
}

+ (NSString *)backgroundDiagnosticSnapshot {
    NSAssert([NSThread isMainThread], @"Background diagnostics must use the main thread");
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSString *owners = [[sBackgroundOwners.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","];
    [parts addObject:[NSString stringWithFormat:@"owners=%@ hostAssertion=%@",
                      owners.length ? owners : @"none",
                      [sBackgroundAssertions[@(getpid())] isValid] ? @"valid" : @"absent-or-invalid"]];
    for (NSNumber *pid in [sBackgroundProcesses.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"child=%@ assertion=%@", pid,
                          [sBackgroundAssertions[pid] isValid] ? @"valid" : @"absent-or-invalid"]];
    }
    return [parts componentsJoinedByString:@"; "];
}

+ (NSString *)diagnosticReport {
    NSAssert([NSThread isMainThread], @"Diagnostics export must use the main thread");
    LoadDiagnosticEvents();
    return [NSString stringWithFormat:@"Current state: %@\n\nRecent lifecycle events:\n%@\n",
            [self backgroundDiagnosticSnapshot], [sDiagnosticEvents componentsJoinedByString:@"\n"]];
}

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
