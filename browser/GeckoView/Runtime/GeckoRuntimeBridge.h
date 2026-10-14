//
//  GeckoRuntimeBridge.h
//  Reynard
//
//  Created by Minh Ton on 24/5/26.
//

#ifndef GeckoRuntimeBridge_h
#define GeckoRuntimeBridge_h

#import <Foundation/Foundation.h>

@interface GeckoRuntimeBridge : NSObject

+ (NSString *)version;
+ (void)configureHeadlessExtensionLifecycle:(NSString *)helperIdentifier;
+ (void)registerBackgroundProcess:(int32_t)pid;
+ (void)removeBackgroundProcess:(int32_t)pid;
+ (void)beginBackgroundGrace;
+ (BOOL)hasBackgroundGrace;
+ (void)endBackgroundGrace;
+ (void)beginBackgroundDownloadGrace;
+ (BOOL)hasBackgroundDownloadGrace;
+ (void)endBackgroundDownloadGrace;
+ (void)recordDiagnostic:(NSString *)message;
+ (NSString *)backgroundDiagnosticSnapshot;
+ (NSString *)diagnosticReport;

@end

#endif /* GeckoRuntimeBridge_h */
