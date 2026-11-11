#import "NCFFmpegBridge.h"
#import <ffmpegkit/FFmpegKit.h>
#import <ffmpegkit/FFprobeKit.h>
#import <ffmpegkit/FFmpegSession.h>
#import <ffmpegkit/FFprobeSession.h>
#import <ffmpegkit/ReturnCode.h>
#import <ffmpegkit/Statistics.h>

@implementation NCFFmpegBridge
static FFmpegSession *currentConversion;

+ (void)probeFile:(NSString *)source
       completion:(void (^)(NSString * _Nullable, NSString * _Nullable))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        FFprobeSession *session = [FFprobeKit executeWithArguments:@[
            @"-hide_banner", @"-v", @"error",
            @"-print_format", @"json", @"-show_format", @"-show_streams",
            source
        ]];
        BOOL successful = [ReturnCode isSuccess:[session getReturnCode]];
        NSString *json = successful ? [session getOutput] : nil;
        NSString *error = successful ? nil : [session getAllLogsAsString];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(json, error);
        });
    });
}

+ (void)convertArguments:(NSArray<NSString *> *)arguments
                progress:(void (^)(double, int64_t))progress
              completion:(void (^)(BOOL, NSString * _Nullable))completion {
    @synchronized(self) {
        if (currentConversion != nil) {
            completion(NO, @"Another video conversion is already running.");
            return;
        }
        currentConversion = [FFmpegKit executeWithArgumentsAsync:arguments
            withCompleteCallback:^(FFmpegSession *session) {
                BOOL successful = [ReturnCode isSuccess:[session getReturnCode]];
                NSString *issue = nil;
                if (!successful) {
                    issue = [session getAllLogsAsString];
                    if (issue.length > 1200) {
                        issue = [issue substringFromIndex:issue.length - 1200];
                    }
                    if (issue.length == 0) {
                        issue = [ReturnCode isCancel:[session getReturnCode]]
                            ? @"Conversion cancelled." : @"FFmpeg could not process the video or audio track.";
                    }
                }
                @synchronized(self) {
                    if (currentConversion == session) currentConversion = nil;
                }
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(successful, issue);
                });
            }
            withLogCallback:nil
            withStatisticsCallback:^(Statistics *stats) {
                double milliseconds = [stats getTime];
                int64_t bytes = (int64_t)[stats getSize];
                dispatch_async(dispatch_get_main_queue(), ^{
                    progress(milliseconds, bytes);
                });
            }];
    }
}

+ (void)cancelActiveConversion {
    @synchronized(self) {
        [currentConversion cancel];
    }
}
@end
