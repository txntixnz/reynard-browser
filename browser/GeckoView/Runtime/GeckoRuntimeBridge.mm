//
//  GeckoRuntimeBridge.mm
//  Reynard
//
//  Created by Minh Ton on 24/5/26.
//

#import "GeckoRuntimeBridge.h"

#import "mozilla-config.h"
#import <dlfcn.h>
#import <objc/runtime.h>
#import <unistd.h>

// Runtime-load private APIs only for entitled installs. RunningBoard signatures
// and the WebKit Background domain come from WebKit's 2022 iOS implementation:
// webkitgtk-2.38.0/Source/WebKit/{Platform/spi/ios/RunningBoardServicesSPI.h,
// UIProcess/ios/ProcessAssertionIOS.mm}. Keep BKS only as an older-OS fallback.
@protocol RYNProcessAssertion <NSObject>
- (BOOL)isValid;
- (void)invalidate;
@end

@protocol RYNRunningBoardTarget <NSObject>
+ (instancetype)targetWithPid:(pid_t)pid;
@end

@protocol RYNRunningBoardAttribute <NSObject>
+ (instancetype)attributeWithDomain:(NSString *)domain name:(NSString *)name;
@end

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
@end

static NSMutableSet<NSNumber *> *sBackgroundProcesses;
static NSMutableDictionary<NSNumber *, id<RYNProcessAssertion>> *sBackgroundAssertions;
static NSMutableSet<NSString *> *sBackgroundOwners;
static NSMutableDictionary<NSNumber *, NSUUID *> *sPendingAssertions;
static NSMutableArray<NSString *> *sDiagnosticEvents;
static const NSUInteger kDiagnosticEventLimit = 240;

static NSString *sHeadlessHelperIdentifier;
static NSHashTable *sHeadlessHelperExtensions;
static BOOL sHeadlessLifecycleHookInstalled;
static id (*sOriginalExtensionFactory)(id, SEL, NSString *, NSError **);

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

// These Gecko processes use the AR-viewer extension point as a bootstrap;
// they do not contain an extension UI. NSExtension's host background callbacks
// synchronously contact that UI and can wait on an already-suspended helper.
// LiveContainer removes the same two observers for its background processes:
// 4dbe0f9/MultitaskSupport/AppSceneViewController.m, setWillResignActiveNotificationEnabled:.
// Remove only those observers from exact helper objects returned by the
// factory. Preserve unrelated extensions and all other lifecycle notifications.
static void RemoveHeadlessHostBackgroundObservers(id extension) {
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center removeObserver:extension name:@"UIApplicationWillResignActiveNotification" object:nil];
    [center removeObserver:extension name:@"UIApplicationDidEnterBackgroundNotification" object:nil];
}

static id CreateHeadlessAwareExtension(id receiver, SEL selector, NSString *identifier, NSError **error) {
    id extension = sOriginalExtensionFactory(receiver, selector, identifier, error);
    if (extension && [identifier isEqualToString:sHeadlessHelperIdentifier]) {
        @synchronized (sHeadlessHelperExtensions) {
            [sHeadlessHelperExtensions addObject:extension];
        }
        RemoveHeadlessHostBackgroundObservers(extension);
        RecordDiagnostic(@"headless helper created; host background observers removed");
    }
    return extension;
}

static void InstallHeadlessLifecycleHook() {
    if (!sHeadlessHelperIdentifier || sHeadlessLifecycleHookInstalled) { return; }
    Class extensionClass = NSClassFromString(@"NSExtension");
    SEL selector = NSSelectorFromString(@"extensionWithIdentifier:error:");
    Method method = extensionClass ? class_getClassMethod(extensionClass, selector) : NULL;
    if (!method || method_getNumberOfArguments(method) != 4) { return; }
    char returnType[8] = {}, identifierType[8] = {}, errorType[8] = {};
    method_getReturnType(method, returnType, sizeof(returnType));
    method_getArgumentType(method, 2, identifierType, sizeof(identifierType));
    method_getArgumentType(method, 3, errorType, sizeof(errorType));
    if (returnType[0] != '@' || identifierType[0] != '@' || errorType[0] != '^' || errorType[1] != '@') { return; }
    sOriginalExtensionFactory = (id (*)(id, SEL, NSString *, NSError **))method_getImplementation(method);
    Class metaClass = object_getClass(extensionClass);
    // Add an override if the factory is inherited rather than changing its
    // superclass. Repeated setup never wraps the replacement recursively.
    if (!class_addMethod(metaClass, selector, (IMP)CreateHeadlessAwareExtension, method_getTypeEncoding(method))) {
        method_setImplementation(method, (IMP)CreateHeadlessAwareExtension);
    }
    sHeadlessLifecycleHookInstalled = YES;
    RecordDiagnostic(@"headless helper lifecycle hook installed");
}

static void PrepareHeadlessHelperLifecycle() {
    InstallHeadlessLifecycleHook();
    NSArray *extensions;
    @synchronized (sHeadlessHelperExtensions) {
        extensions = sHeadlessHelperExtensions.allObjects;
    }
    // Request startup may register observers again after the factory returns.
    // Repeat removal when the child is ready and before the background window.
    for (id extension in extensions) { RemoveHeadlessHostBackgroundObservers(extension); }
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
    Class attributeClass = NSClassFromString(@"RBSDomainAttribute");
    BOOL hasRunningBoard = runningClass && targetClass && attributeClass &&
        [targetClass respondsToSelector:@selector(targetWithPid:)] &&
        [attributeClass respondsToSelector:@selector(attributeWithDomain:name:)] &&
        [runningClass instancesRespondToSelector:@selector(initWithExplanation:target:attributes:)] &&
        [runningClass instancesRespondToSelector:@selector(acquireWithError:)] &&
        [runningClass instancesRespondToSelector:@selector(isValid)] &&
        [runningClass instancesRespondToSelector:@selector(invalidate)];
    if (hasRunningBoard) {
        id target = [(Class<RYNRunningBoardTarget>)targetClass targetWithPid:pid];
        id attribute = [(Class<RYNRunningBoardAttribute>)attributeClass attributeWithDomain:@"com.apple.webkit" name:@"Background"];
        if (!target || !attribute) {
            RecordDiagnostic([NSString stringWithFormat:@"RunningBoard target/attribute creation failed pid=%d", pid]);
            return;
        }
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
                RecordDiagnostic([NSString stringWithFormat:@"RunningBoard pid=%d acquired=%d valid=%d errorDomain=%@ code=%ld reason=%@",
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
        initWithPID:pid flags:5 reason:10004 name:@"Reynard network activity"
        withHandler:^(BOOL acquired) {
            NSLog(@"Reynard: background assertion PID %d %@", pid,
                  acquired ? @"acquired" : @"denied");
            RecordDiagnostic([NSString stringWithFormat:@"BKS background assertion pid=%d %@", pid,
                              acquired ? @"acquired" : @"denied"]);
        }];
    if (assertion) { sBackgroundAssertions[@(pid)] = assertion; }
}

@implementation GeckoRuntimeBridge

+ (void)configureHeadlessExtensionLifecycle:(NSString *)helperIdentifier {
    NSAssert([NSThread isMainThread], @"Headless lifecycle setup must use the main thread");
    if (helperIdentifier.length == 0) { return; }
    // Configured once by the entitled host before it launches Gecko helpers.
    if (sHeadlessHelperIdentifier) {
        if ([sHeadlessHelperIdentifier isEqualToString:helperIdentifier]) { InstallHeadlessLifecycleHook(); }
        return;
    }
    sHeadlessHelperIdentifier = [helperIdentifier copy];
    if (!sHeadlessHelperExtensions) { sHeadlessHelperExtensions = [NSHashTable weakObjectsHashTable]; }
    InstallHeadlessLifecycleHook();
}

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
    [parts addObject:[NSString stringWithFormat:@"headlessLifecycle=%@",
                      sHeadlessLifecycleHookInstalled ? @"installed" : sHeadlessHelperIdentifier ? @"unavailable" : @"off"]];
    for (NSNumber *pid in [sBackgroundProcesses.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        [parts addObject:[NSString stringWithFormat:@"child=%@ assertion=%@", pid,
                          [sBackgroundAssertions[pid] isValid] ? @"valid" : sPendingAssertions[pid] ? @"pending" : @"absent-or-invalid"]];
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
    PrepareHeadlessHelperLifecycle();
    if (!sBackgroundProcesses) { sBackgroundProcesses = [NSMutableSet set]; }
    [sBackgroundProcesses addObject:@(pid)];
    if (sBackgroundOwners.count > 0) { AcquireBackgroundAssertion(pid); }
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
    PrepareHeadlessHelperLifecycle();
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
    [sPendingAssertions removeAllObjects];
    for (id<RYNProcessAssertion> assertion in sBackgroundAssertions.allValues) {
        [assertion invalidate];
    }
    [sBackgroundAssertions removeAllObjects];
}

@end
