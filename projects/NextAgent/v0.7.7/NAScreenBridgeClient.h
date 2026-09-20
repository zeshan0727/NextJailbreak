#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NAScreenBridgeClient : NSObject
+ (NSDictionary *)captureScreen;
+ (NSDictionary *)openSplitWorkspaceWithPrimaryBundleID:(NSString *)primary
                                       secondaryBundleID:(NSString *)secondary;
+ (NSDictionary *)openSplitWorkspaceWithSecondaryBundleID:(NSString *)secondary NS_SWIFT_NAME(openSplitWorkspace(secondary:));
+ (NSDictionary *)splitWorkspaceStatus;
+ (NSDictionary *)closeSplitWorkspace;
@end

NS_ASSUME_NONNULL_END
