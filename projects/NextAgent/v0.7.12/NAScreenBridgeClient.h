#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NAScreenBridgeClient : NSObject
+ (NSDictionary *)captureScreen;
+ (NSDictionary *)ocrScreenFast:(BOOL)fast
                       languages:(NSArray<NSString *> *)languages
                        maxItems:(NSInteger)maxItems NS_SWIFT_NAME(ocrScreen(fast:languages:maxItems:));
+ (NSDictionary *)splitCapabilities NS_SWIFT_NAME(splitCapabilities());
+ (NSDictionary *)openSplitWorkspaceWithPrimaryBundleID:(NSString *)primary
                                       secondaryBundleID:(NSString *)secondary;
+ (NSDictionary *)openSplitWorkspaceWithSecondaryBundleID:(NSString *)secondary NS_SWIFT_NAME(openSplitWorkspace(secondary:));
+ (NSDictionary *)splitWorkspaceStatus;
+ (NSDictionary *)closeSplitWorkspace;
+ (NSDictionary *)hidStatus NS_SWIFT_NAME(hidStatus());
+ (NSDictionary *)hidTapX:(double)x y:(double)y count:(NSInteger)count NS_SWIFT_NAME(hidTap(x:y:count:));
+ (NSDictionary *)hidLongPressX:(double)x y:(double)y duration:(double)duration NS_SWIFT_NAME(hidLongPress(x:y:duration:));
+ (NSDictionary *)hidSwipeX1:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration NS_SWIFT_NAME(hidSwipe(x1:y1:x2:y2:duration:));
+ (NSDictionary *)hidPressKey:(NSString *)key NS_SWIFT_NAME(hidPressKey(_:));
+ (NSDictionary *)hidPasteShortcut NS_SWIFT_NAME(hidPasteShortcut());
+ (NSDictionary *)hidTypeText:(NSString *)text NS_SWIFT_NAME(hidTypeText(_:));
@end

NS_ASSUME_NONNULL_END
