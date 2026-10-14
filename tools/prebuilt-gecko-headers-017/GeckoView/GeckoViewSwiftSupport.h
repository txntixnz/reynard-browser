/* clang-format off */
/* clang-format on */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this file,
 * You can obtain one at http://mozilla.org/MPL/2.0/. */

#ifndef GeckoView_GeckoViewSwiftSupport_h
#define GeckoView_GeckoViewSwiftSupport_h

/* This header needs to stay valid Objective-C (not Objective-C++) when
 * built independently because it is used for Swift bridging too. */
#ifdef MOZILLA_CLIENT
#  include <mozilla/Types.h>
#else
#  define MOZ_EXPORT
#  define MOZ_BEGIN_EXTERN_C
#  define MOZ_END_EXTERN_C
#endif

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <xpc/xpc.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SwiftEventDispatcher;

typedef NS_ENUM(NSInteger, GeckoInputHandling) {
  GeckoInputHandlingUnhandled = 0,
  GeckoInputHandlingBrowser = 1,
  GeckoInputHandlingContent = 2,
};

typedef NS_OPTIONS(NSUInteger, GeckoScrollableEdges) {
  GeckoScrollableEdgeTop = 1 << 0,
  GeckoScrollableEdgeRight = 1 << 1,
  GeckoScrollableEdgeBottom = 1 << 2,
  GeckoScrollableEdgeLeft = 1 << 3,
};

typedef NS_OPTIONS(NSUInteger, GeckoOverscrollAxes) {
  GeckoOverscrollAxisHorizontal = 1 << 0,
  GeckoOverscrollAxisVertical = 1 << 1,
};

typedef NS_OPTIONS(NSUInteger, GeckoEdgeSwipeDirections) {
  GeckoEdgeSwipeDirectionLeft = 1 << 0,
  GeckoEdgeSwipeDirectionRight = 1 << 1,
};

typedef NS_ENUM(NSUInteger, GeckoOrientationLockResult) {
  GeckoOrientationLockResultSuccess,
  GeckoOrientationLockResultRejected,
  GeckoOrientationLockResultNotSupported,
};

@protocol GeckoViewInteractionDelegate <NSObject>
- (void)touchSequenceDidBegin:(uint64_t)sequenceId;
- (void)touchSequence:(uint64_t)sequenceId
    didResolveHandling:(GeckoInputHandling)handling
       scrollableEdges:(GeckoScrollableEdges)scrollableEdges
        overscrollAxes:(GeckoOverscrollAxes)overscrollAxes;
- (void)touchSequenceDidEnd:(uint64_t)sequenceId;
- (void)trackpadScrollDidBegin:(CGPoint)delta;
- (void)trackpadScrollDidUpdate:(CGPoint)delta;
- (void)trackpadScrollDidEnd;
- (void)trackpadScrollDidCancel;
- (void)compositorScrollPositionDidChange:(double)scrollY zoom:(double)zoom;
- (GeckoEdgeSwipeDirections)allowedEdgeSwipeDirections;
- (void)edgeSwipeDidStart:(GeckoEdgeSwipeDirections)direction;
- (void)edgeSwipeDidUpdate:(double)progress;
- (void)edgeSwipeDidComplete:(GeckoEdgeSwipeDirections)direction;
- (void)edgeSwipeDidEnd;
@end

@protocol SwiftGeckoViewRuntime <NSObject>
- (id<SwiftEventDispatcher>)runtimeDispatcher;
- (id<SwiftEventDispatcher>)dispatcherByName:(const char*)name;
- (void)lockScreenOrientation:(NSUInteger)orientationMask
                   completion:
                       (void (^)(GeckoOrientationLockResult result))completion;
- (void)unlockScreenOrientation;
@optional
- (void)childProcessDidStartWithPID:(int32_t)pid
                        processType:(NSString*)processType;
@end

@protocol GeckoProcessExtension <NSObject>
- (void)lockdownSandbox:(NSString*)revision;
@end

@protocol EventCallback <NSObject>
- (void)sendSuccess:(nullable id)response;
- (void)sendError:(nullable id)response;
@end

@protocol GeckoEventDispatcher <NSObject>
- (void)dispatchToGecko:(NSString*)type
                message:(nullable id)message
               callback:(nullable id<EventCallback>)callback;
- (BOOL)hasListener:(NSString*)type;
@end

@protocol SwiftEventDispatcher <NSObject>
- (void)attach:(nullable id<GeckoEventDispatcher>)gecko;
- (void)dispatchToSwift:(NSString*)type
                message:(nullable id)message
               callback:(nullable id<EventCallback>)callback;
- (BOOL)hasListener:(NSString*)type;
// Called when GeckoView is ready to receive dispatched events from Swift.
- (void)activate;
@end

@protocol GeckoViewWindow <NSObject>
// Window
- (nullable UIView*)view;
- (void)close;

// Interaction
- (void)setInteractionDelegate:
    (nullable id<GeckoViewInteractionDelegate>)delegate;

// Layout
- (void)setDynamicToolbarMaxHeight:(CGFloat)height minHeight:(CGFloat)minHeight;
- (void)setContentOffsets:(CGFloat)top
                   bottom:(CGFloat)bottom
                 topInset:(CGFloat)topInset
              bottomInset:(CGFloat)bottomInset
      contentTranslationY:(CGFloat)contentTranslationY;
- (void)updateScreenOrientation:(NSInteger)interfaceOrientation;

// Keyboard
- (void)dismissSoftwareKeyboard;
- (BOOL)focusForHardwareKeyboard;
- (BOOL)isInHardwareKeyboardMode;

// Printing
- (void)printToPDFWithBrowsingContextId:(nullable NSNumber*)browsingContextId
                             completion:(void (^_Nonnull)(
                                            NSURL* _Nullable fileURL,
                                            NSError* _Nullable error))completion
    NS_SWIFT_NAME(printToPDF(browsingContextId:completion:));
- (void)savePDFDocumentAtURL:(nonnull NSString*)sourceURL
                  completion:
                      (void (^_Nonnull)(NSURL* _Nullable fileURL,
                                        NSError* _Nullable error))completion
    NS_SWIFT_NAME(savePDFDocument(sourceURL:completion:));
@end

MOZ_BEGIN_EXTERN_C

MOZ_EXPORT id<GeckoViewWindow> GeckoViewOpenWindow(
    NSString* _Nullable aId, id<SwiftEventDispatcher> aDispatcher,
    NSDictionary* aInitData, bool aPrivateMode);

MOZ_END_EXTERN_C

NS_ASSUME_NONNULL_END

#endif /* GeckoView_GeckoViewSwiftSupport_h */
