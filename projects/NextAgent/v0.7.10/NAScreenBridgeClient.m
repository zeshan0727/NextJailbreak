#import "NAScreenBridgeClient.h"
#import <CoreFoundation/CoreFoundation.h>

static CFStringRef const NABridgeServiceName =
    CFSTR("uk.zeshanbarvi.nextagent.bridge.v0710");

@implementation NAScreenBridgeClient

+ (NSDictionary *)request:(NSDictionary *)request timeout:(CFTimeInterval)timeout {
    if (![NSJSONSerialization isValidJSONObject:request]) {
        return @{@"success": @NO, @"error": @"invalid bridge request"};
    }

    NSData *body = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (!body) {
        return @{@"success": @NO, @"error": @"could not encode bridge request"};
    }

    CFMessagePortRef remote = CFMessagePortCreateRemote(
        kCFAllocatorDefault,
        NABridgeServiceName
    );
    if (!remote) {
        return @{
            @"success": @NO,
            @"error": @"SpringBoard direct bridge is unavailable. Install the matching RootHide 0.7.10 package and respring.",
            @"transport": @"cfmessageport"
        };
    }

    CFDataRef reply = NULL;
    SInt32 status = CFMessagePortSendRequest(
        remote,
        77,
        (__bridge CFDataRef)body,
        timeout,
        timeout,
        kCFRunLoopDefaultMode,
        &reply
    );
    CFRelease(remote);

    if (status != kCFMessagePortSuccess || !reply) {
        if (reply) CFRelease(reply);
        return @{
            @"success": @NO,
            @"error": [NSString stringWithFormat:@"SpringBoard direct bridge request failed (%d)", (int)status],
            @"transport": @"cfmessageport"
        };
    }

    NSData *replyData = CFBridgingRelease(reply);
    id decoded = [NSJSONSerialization JSONObjectWithData:replyData options:0 error:nil];
    if (![decoded isKindOfClass:NSDictionary.class]) {
        return @{
            @"success": @NO,
            @"error": @"SpringBoard direct bridge returned malformed JSON",
            @"transport": @"cfmessageport"
        };
    }

    NSMutableDictionary *result = [(NSDictionary *)decoded mutableCopy];
    NSString *base64 = [result[@"image_base64"] isKindOfClass:NSString.class]
        ? result[@"image_base64"] : nil;
    if (base64.length) {
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:base64
                                                                options:NSDataBase64DecodingIgnoreUnknownCharacters];
        [result removeObjectForKey:@"image_base64"];
        if (imageData.length) {
            result[@"image_data"] = imageData;
            result[@"transport_bytes"] = @(imageData.length);
        } else {
            result[@"success"] = @NO;
            result[@"error"] = @"Direct bridge image payload could not be decoded";
        }
    }
    result[@"transport"] = @"cfmessageport";
    return result;
}

+ (NSDictionary *)captureScreen {
    return [self request:@{@"action": @"capture"} timeout:5.0];
}

+ (NSDictionary *)ocrScreenFast:(BOOL)fast
                       languages:(NSArray<NSString *> *)languages
                        maxItems:(NSInteger)maxItems {
    NSInteger bounded = MAX(1, MIN(200, maxItems));
    return [self request:@{
        @"action": @"ocr",
        @"fast": @(fast),
        @"languages": languages ?: @[],
        @"max_items": @(bounded)
    } timeout:8.0];
}

+ (NSDictionary *)splitCapabilities {
    return [self request:@{@"action": @"split_capabilities"} timeout:2.0];
}

+ (NSDictionary *)openSplitWorkspaceWithPrimaryBundleID:(NSString *)primary
                                       secondaryBundleID:(NSString *)secondary {
    if (!primary.length || !secondary.length) {
        return @{@"success": @NO, @"error": @"missing split-workspace bundle identifier"};
    }
    return [self request:@{
        @"action": @"split_open",
        @"primary_bundle_id": primary,
        @"secondary_bundle_id": secondary
    } timeout:4.0];
}

+ (NSDictionary *)openSplitWorkspaceWithSecondaryBundleID:(NSString *)secondary {
    return [self openSplitWorkspaceWithPrimaryBundleID:@"uk.zeshanbarvi.nextagent"
                                     secondaryBundleID:secondary];
}

+ (NSDictionary *)splitWorkspaceStatus {
    return [self request:@{@"action": @"split_status"} timeout:2.0];
}

+ (NSDictionary *)closeSplitWorkspace {
    return [self request:@{@"action": @"split_close"} timeout:2.0];
}

@end
