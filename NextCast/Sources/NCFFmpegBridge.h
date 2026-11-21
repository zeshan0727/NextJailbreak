#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Isolated wrapper around the maintained FFmpegKit 8.1.2 binary.
/// Neither FFmpeg command-line entry points nor the proprietary reference
/// application's binaries are copied into the Next Cast source.
@interface NCFFmpegBridge : NSObject
+ (void)probeFile:(NSString *)source
       completion:(void (^)(NSString * _Nullable json, NSString * _Nullable error))completion;
+ (void)convertArguments:(NSArray<NSString *> *)arguments
                progress:(void (^)(double milliseconds, int64_t outputBytes))progress
              completion:(void (^)(BOOL success, NSString * _Nullable error))completion;
+ (void)cancelActiveConversion;
@end

NS_ASSUME_NONNULL_END
