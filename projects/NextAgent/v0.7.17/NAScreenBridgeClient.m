#import "NAScreenBridgeClient.h"
#import <CoreFoundation/CoreFoundation.h>

static CFStringRef const NABridgeServiceName =
    CFSTR("uk.zeshanbarvi.nextagent.bridge.v0717");

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
            @"error": @"SpringBoard direct bridge is unavailable. Install the matching RootHide 0.7.17 package and respring.",
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

+ (NSDictionary *)hidStatus {
    return [self request:@{@"action": @"hid_status"} timeout:2.0];
}

+ (NSDictionary *)hudStatus {
    return [self request:@{@"action": @"hud_status"} timeout:2.0];
}

+ (NSDictionary *)hudTest {
    return [self request:@{@"action": @"hud_test"} timeout:2.0];
}

+ (NSDictionary *)hidTapX:(double)x y:(double)y count:(NSInteger)count {
    return [self request:@{
        @"action": @"hid_tap",
        @"x": @(x),
        @"y": @(y),
        @"count": @(MAX(1, MIN(2, count)))
    } timeout:3.0];
}

+ (NSDictionary *)hidLongPressX:(double)x y:(double)y duration:(double)duration {
    return [self request:@{
        @"action": @"hid_long_press",
        @"x": @(x),
        @"y": @(y),
        @"duration": @(MAX(0.2, MIN(8.0, duration)))
    } timeout:10.0];
}

+ (NSDictionary *)hidSwipeX1:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2 duration:(double)duration {
    return [self request:@{
        @"action": @"hid_swipe",
        @"x1": @(x1), @"y1": @(y1),
        @"x2": @(x2), @"y2": @(y2),
        @"duration": @(MAX(0.1, MIN(5.0, duration)))
    } timeout:8.0];
}

+ (NSDictionary *)hidPressKey:(NSString *)key {
    return [self request:@{
        @"action": @"hid_key",
        @"key": key ?: @""
    } timeout:3.0];
}

+ (NSDictionary *)hidPasteShortcut {
    return [self request:@{@"action": @"hid_paste"} timeout:3.0];
}

+ (NSDictionary *)hidTypeText:(NSString *)text {
    if (!text.length || text.length > 4096) {
        return @{@"success": @NO, @"error": @"text length must be 1...4096"};
    }
    return [self request:@{
        @"action": @"hid_type_text",
        @"text": text
    } timeout:20.0];
}

@end
