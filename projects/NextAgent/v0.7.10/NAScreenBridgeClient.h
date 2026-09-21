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
@end

NS_ASSUME_NONNULL_END
