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
+ (void)registerBackgroundProcess:(int32_t)pid;
+ (void)removeBackgroundProcess:(int32_t)pid;
+ (void)beginBackgroundGrace;
+ (BOOL)hasBackgroundGrace;
+ (void)endBackgroundGrace;

@end

#endif /* GeckoRuntimeBridge_h */
