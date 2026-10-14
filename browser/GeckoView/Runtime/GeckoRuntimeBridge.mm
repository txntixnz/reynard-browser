//
//  GeckoRuntimeBridge.mm
//  Reynard
//
//  Created by Minh Ton on 24/5/26.
//

#import "GeckoRuntimeBridge.h"

#import "mozilla-config.h"
#import <dlfcn.h>
#import <mach/mach.h>
#import <unistd.h>
#include <atomic>

// Runtime-load private APIs only for entitled installs. These are NSExtension
// processes, not Apple's WebKit services: a valid WebKit Background grant on
// iOS 16 did not prevent the socket helper from being suspended. Request the
// task-execution flag explicitly through RBSLegacyAttribute instead. Its
// factory is used by udevsharold/bakgrunnur; the flags and unbounded finish-task
// reason come from WebKit's f507bab/Platform/spi/ios/AssertionServicesSPI.h.
// Retain BKS only as an older-OS fallback and bound lifetime at the owner level.
@protocol RYNProcessAssertion <NSObject>
- (BOOL)isValid;
- (void)invalidate;
@end

@protocol RYNRunningBoardTarget <NSObject>
+ (instancetype)targetWithPid:(pid_t)pid;
@end

@protocol RYNRunningBoardTaskAttribute <NSObject>
+ (instancetype)attributeWithReason:(unsigned long long)reason flags:(unsigned long long)flags;
@end

static const unsigned long long kTaskExecutionFlags = 1 | 4; // PreventTaskSuspend | AllowIdleSleep
static const unsigned long long kUnboundedFinishTaskReason = 10004;

@protocol RYNRunningBoardAssertion <RYNProcessAssertion>
- (instancetype)initWithExplanation:(NSString *)explanation target:(id)target attributes:(NSArray *)attributes;
- (BOOL)acquireWithError:(NSError **)error;
@end

@protocol RYNBackgroundAssertion <RYNProcessAssertion>
- (instancetype)initWithPID:(int)pid flags:(unsigned int)flags
                     reason:(unsigned int)reason name:(NSString *)name
                withHandler:(void (^)(BOOL))handler;
@end

@interface GeckoRuntimeBridge ()
+ (void)beginBackgroundActivityForOwner:(NSString *)owner;
+ (void)endBackgroundActivityForOwner:(NSString *)owner;
+ (BOOL)hasCompleteBackgroundExecutionGrant;
@end

static NSMutableSet<NSNumber *> *sBackgroundProcesses;
static NSMutableDictionary<NSNumber *, id<RYNProcessAssertion>> *sBackgroundAssertions;
static NSMutableSet<NSString *> *sBackgroundOwners;
static NSMutableDictionary<NSNumber *, NSUUID *> *sPendingAssertions;
static NSMutableArray<NSString *> *sDiagnosticEvents;
static const NSUInteger kDiagnosticEventLimit = 240;
static char sDiagnosticQueueKey;
static std::atomic<uint64_t> sTaskInspectionGeneration { 0 };

static dispatch_queue_t DiagnosticQueue() {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.minh-ton.Reynard.connection-diagnostics", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(queue, &sDiagnosticQueueKey, &sDiagnosticQueueKey, NULL);
    });
    return queue;
}

static dispatch_queue_t AssertionQueue() {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.minh-ton.Reynard.background-assertions", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

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
    if (!dispatch_get_specific(&sDiagnosticQueueKey)) {
        NSString *copy = [message copy];
        dispatch_async(DiagnosticQueue(), ^{ RecordDiagnostic(copy); });
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

// Read task suspension state with existing access only. Do not suspend/resume
// tasks, attach a debugger, read process memory, or request new permissions.
// A denied task port is unknown state, never evidence of continued execution.
static NSString *ProcessTaskStateDiagnostic(int32_t pid) {
    if (pid <= 1) { return [NSString stringWithFormat:@"task-inspection pid=%d state=unknown invalid-pid", pid]; }
    BOOL ownTask = pid == getpid();
    mach_port_t task = mach_task_self();
    kern_return_t result = ownTask ? KERN_SUCCESS : task_for_pid(mach_task_self(), pid, &task);
    if (result != KERN_SUCCESS) {
        return [NSString stringWithFormat:@"task-inspection pid=%d state=unknown task-port-unavailable kernelCode=%d", pid, result];
    }
    mach_task_basic_info_data_t info = {};
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    result = task_info(task, MACH_TASK_BASIC_INFO, (task_info_t)&info, &count);
    if (!ownTask) { mach_port_deallocate(mach_task_self(), task); }
    if (result != KERN_SUCCESS) {
        return [NSString stringWithFormat:@"task-inspection pid=%d state=unknown task-info-failed kernelCode=%d", pid, result];
    }
    return [NSString stringWithFormat:@"task-inspection pid=%d state=%@ suspendCount=%d",
            pid, info.suspend_count > 0 ? @"suspended" : @"not-suspended", (int)info.suspend_count];
}

static void ScheduleTaskInspection(NSArray<NSNumber *> *pids) {
    uint64_t generation = sTaskInspectionGeneration.load();
    // One observation before the 10-second scene watchdog, not a keepalive or
    // renewal. It can be recorded while the UI thread is blocked in system IPC.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        if (sTaskInspectionGeneration.load() != generation) { return; }
        for (NSNumber *pid in pids) { RecordDiagnostic(ProcessTaskStateDiagnostic(pid.intValue)); }
    });
}

static void AcquireBackgroundAssertion(int32_t pid) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        for (NSString *framework in @[@"AssertionServices", @"RunningBoardServices"]) {
            NSString *path = [NSString stringWithFormat:@"/System/Library/PrivateFrameworks/%@.framework/%@", framework, framework];
            void *handle = dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL);
            RecordDiagnostic([NSString stringWithFormat:@"background framework %@ %@", framework, handle ? @"loaded" : @"unavailable"]);
        }
    });
    id<RYNProcessAssertion> existing = sBackgroundAssertions[@(pid)];
    if ([existing isValid]) { return; }
    if (sPendingAssertions[@(pid)]) { return; }
    [existing invalidate];
    [sBackgroundAssertions removeObjectForKey:@(pid)];

    Class runningClass = NSClassFromString(@"RBSAssertion");
    Class targetClass = NSClassFromString(@"RBSTarget");
    Class attributeClass = NSClassFromString(@"RBSLegacyAttribute");
    BOOL hasRunningBoard = runningClass && targetClass && attributeClass &&
        [targetClass respondsToSelector:@selector(targetWithPid:)] &&
        [attributeClass respondsToSelector:@selector(attributeWithReason:flags:)] &&
        [runningClass instancesRespondToSelector:@selector(initWithExplanation:target:attributes:)] &&
        [runningClass instancesRespondToSelector:@selector(acquireWithError:)] &&
        [runningClass instancesRespondToSelector:@selector(isValid)] &&
        [runningClass instancesRespondToSelector:@selector(invalidate)];
    if (hasRunningBoard) {
        id target = [(Class<RYNRunningBoardTarget>)targetClass targetWithPid:pid];
        id attribute = [(Class<RYNRunningBoardTaskAttribute>)attributeClass attributeWithReason:kUnboundedFinishTaskReason flags:kTaskExecutionFlags];
        if (!target || !attribute) {
            RecordDiagnostic([NSString stringWithFormat:@"RunningBoard target/attribute creation failed pid=%d", pid]);
            return;
        }
        RecordDiagnostic([NSString stringWithFormat:@"RunningBoard task request pid=%d attribute=%@", pid, attribute]);
        id<RYNRunningBoardAssertion> assertion = [(id<RYNRunningBoardAssertion>)[runningClass alloc]
            initWithExplanation:@"Reynard background network activity" target:target attributes:@[attribute]];
        if (!sPendingAssertions) { sPendingAssertions = [NSMutableDictionary dictionary]; }
        NSUUID *request = [NSUUID UUID];
        sPendingAssertions[@(pid)] = request;
        // RunningBoard acquisition can wait for an IPC reply. Keep it off the
        // UI thread while UIKit protects the transition. Never retain a late
        // grant after the owner ended or the target process exited/restarted.
        dispatch_async(AssertionQueue(), ^{
            NSError *error = nil;
            BOOL acquired = [assertion acquireWithError:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL valid = acquired && [assertion isValid];
                RecordDiagnostic([NSString stringWithFormat:@"RunningBoard task-unbounded pid=%d acquired=%d valid=%d errorDomain=%@ code=%ld reason=%@",
                                  pid, acquired, valid, error.domain ?: @"none", (long)error.code, error.localizedFailureReason ?: error.localizedDescription ?: @"none"]);
                if (sPendingAssertions[@(pid)] != request || sBackgroundOwners.count == 0) {
                    [assertion invalidate];
                    RecordDiagnostic([NSString stringWithFormat:@"RunningBoard late grant released pid=%d", pid]);
                    return;
                }
                [sPendingAssertions removeObjectForKey:@(pid)];
                if (valid) { sBackgroundAssertions[@(pid)] = assertion; }
                else { [assertion invalidate]; }
            });
        });
        // Do not silently substitute an old API after an explicit OS denial.
        return;
    }
    RecordDiagnostic([NSString stringWithFormat:@"RunningBoard API unavailable assertionClass=%d targetClass=%d attributeClass=%d", !!runningClass, !!targetClass, !!attributeClass]);
    Class assertionClass = NSClassFromString(@"BKSProcessAssertion");
    if (!assertionClass ||
        ![assertionClass instancesRespondToSelector:@selector(initWithPID:flags:reason:name:withHandler:)] ||
        ![assertionClass instancesRespondToSelector:@selector(isValid)] ||
        ![assertionClass instancesRespondToSelector:@selector(invalidate)]) {
        RecordDiagnostic([NSString stringWithFormat:@"BKS API unavailable class=%d init=%d valid=%d invalidate=%d", !!assertionClass,
                          [assertionClass instancesRespondToSelector:@selector(initWithPID:flags:reason:name:withHandler:)],
                          [assertionClass instancesRespondToSelector:@selector(isValid)],
                          [assertionClass instancesRespondToSelector:@selector(invalidate)]]);
        return;
    }
    // PreventTaskSuspend | AllowIdleSleep. Do not request foreground GPU/UI
    // priority or keep the screen awake while continuing the page's network work.
    id<RYNBackgroundAssertion> assertion = [(id<RYNBackgroundAssertion>)[assertionClass alloc]
        initWithPID:pid flags:(unsigned int)kTaskExecutionFlags reason:(unsigned int)kUnboundedFinishTaskReason name:@"Reynard network activity"
        withHandler:^(BOOL acquired) {
            NSLog(@"Reynard: background assertion PID %d %@", pid,
                  acquired ? @"acquired" : @"denied");
            RecordDiagnostic([NSString stringWithFormat:@"BKS background assertion pid=%d %@", pid,
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
                      [sBackgroundAssertions[@(getpid())] isValid] ? @"valid" : sPendingAssertions[@(getpid())] ? @"pending" : @"absent-or-invalid"]];
    [parts addObject:@"requestedPolicy=prevent-task-suspend"];
    for (NSNumber *pid in [sBackgroundProcesses.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"child=%@ assertion=%@", pid,
                          [sBackgroundAssertions[pid] isValid] ? @"valid" : sPendingAssertions[pid] ? @"pending" : @"absent-or-invalid"]];
    }
    return [parts componentsJoinedByString:@"; "];
}

+ (NSString *)diagnosticReport {
    NSAssert([NSThread isMainThread], @"Diagnostics export must use the main thread");
    __block NSString *events;
    dispatch_sync(DiagnosticQueue(), ^{
        LoadDiagnosticEvents();
        events = [sDiagnosticEvents componentsJoinedByString:@"\n"];
    });
    return [NSString stringWithFormat:@"Current state: %@\n\nRecent lifecycle events:\n%@\n",
            [self backgroundDiagnosticSnapshot], events];
}

+ (NSString *)version {
    return @MOZILLA_VERSION;
}

+ (void)registerBackgroundProcess:(int32_t)pid {
    NSAssert([NSThread isMainThread], @"Background process registry must use the main thread");
    if (pid <= 1) { return; }
    if (!sBackgroundProcesses) { sBackgroundProcesses = [NSMutableSet set]; }
    [sBackgroundProcesses addObject:@(pid)];
    if (sBackgroundOwners.count > 0) {
        AcquireBackgroundAssertion(pid);
        ScheduleTaskInspection(@[@(pid)]);
    }
}

+ (void)removeBackgroundProcess:(int32_t)pid {
    NSAssert([NSThread isMainThread], @"Background process registry must use the main thread");
    [sBackgroundProcesses removeObject:@(pid)];
    [sPendingAssertions removeObjectForKey:@(pid)];
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
    BOOL firstOwner = sBackgroundOwners.count == 0;
    if (!sBackgroundOwners) { sBackgroundOwners = [NSMutableSet set]; }
    [sBackgroundOwners addObject:owner];
    if (!sBackgroundAssertions) { sBackgroundAssertions = [NSMutableDictionary dictionary]; }
    AcquireBackgroundAssertion(getpid());
    for (NSNumber *pid in sBackgroundProcesses) {
        AcquireBackgroundAssertion(pid.intValue);
    }
    if (firstOwner) {
        sTaskInspectionGeneration.fetch_add(1);
        ScheduleTaskInspection([@[@(getpid())] arrayByAddingObjectsFromArray:sBackgroundProcesses.allObjects ?: @[]]);
    }
}

+ (BOOL)hasBackgroundGrace {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    return [sBackgroundOwners containsObject:@"live-page"] && [self hasCompleteBackgroundExecutionGrant];
}

+ (BOOL)hasCompleteBackgroundExecutionGrant {
    if (![sBackgroundAssertions[@(getpid())] isValid]) { return NO; }
    // A host-only grant cannot keep the page or socket runtime executing.
    // If any required helper is denied, use the finite UIKit fallback rather
    // than retaining only the host after that fallback expires.
    for (NSNumber *pid in sBackgroundProcesses) {
        if (![sBackgroundAssertions[pid] isValid]) { return NO; }
    }
    return YES;
}

+ (void)endBackgroundGrace {
    [self endBackgroundActivityForOwner:@"live-page"];
}

+ (BOOL)hasBackgroundDownloadGrace {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    return [sBackgroundOwners containsObject:@"downloads"] && [self hasCompleteBackgroundExecutionGrant];
}

+ (void)endBackgroundDownloadGrace {
    [self endBackgroundActivityForOwner:@"downloads"];
}

+ (void)endBackgroundActivityForOwner:(NSString *)owner {
    NSAssert([NSThread isMainThread], @"Background assertions must use the main thread");
    [sBackgroundOwners removeObject:owner];
    if (sBackgroundOwners.count > 0) { return; }
    sTaskInspectionGeneration.fetch_add(1);
    [sPendingAssertions removeAllObjects];
    for (id<RYNProcessAssertion> assertion in sBackgroundAssertions.allValues) {
        [assertion invalidate];
    }
    [sBackgroundAssertions removeAllObjects];
}

@end
