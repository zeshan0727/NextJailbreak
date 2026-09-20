#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NABackgroundAssertionController : NSObject

@property (nonatomic, readonly, getter=isActive) BOOL active;
@property (nonatomic, readonly, getter=isValid) BOOL valid;
@property (nonatomic, readonly) NSString *status;

+ (instancetype)sharedController;
- (BOOL)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
