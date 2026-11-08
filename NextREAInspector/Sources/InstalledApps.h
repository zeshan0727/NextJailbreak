#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface InstalledApps : NSObject
+ (NSArray<NSDictionary<NSString *,NSString *> *> *)installedApplications;
@end
NS_ASSUME_NONNULL_END
