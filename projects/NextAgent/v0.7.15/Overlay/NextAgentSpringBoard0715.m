#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Vision/Vision.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreVideo/CoreVideo.h>

static NSString * const NAProgressPath = @"/var/mobile/Library/NextAgent/progress.json";
static NSString * const NAOverlayStatusPath = @"/var/mobile/Library/NextAgent/overlay.status.json";
static NSString * const NAScreenRequestPath = @"/var/mobile/Library/NextAgent/screen.request.json";
static NSString * const NAScreenResponsePath = @"/var/mobile/Library/NextAgent/screen.response.json";
static NSString * const NACaptureDirectory = @"/var/mobile/Library/NextAgent/Captures";
static NSString * const NABundleID = @"uk.zeshanbarvi.nextagent";

static const char *NAProgressNotification = "uk.zeshanbarvi.nextagent.progress.changed";
static const char *NAScreenRequestNotification = "uk.zeshanbarvi.nextagent.screen.capture.request";
static const char *NAScreenDoneNotification = "uk.zeshanbarvi.nextagent.screen.capture.done";
static const char *NAHUDStateNotification = "uk.zeshanbarvi.nextagent.hud.state";
static int NAHUDStateToken = -1;
static NSDictionary *NAOCRCachePayload = nil;
static NSTimeInterval NAOCRCacheAt = 0.0;
static BOOL NAOCRCacheFast = YES;
static NSString *NAOCRCacheLanguageKey = nil;
static NSInteger NAOCRCacheMaxItems = 0;

static void NAInvalidateOCRCache(void) {
    NAOCRCachePayload = nil;
    NAOCRCacheAt = 0.0;
    NAOCRCacheLanguageKey = nil;
    NAOCRCacheMaxItems = 0;
}


typedef void (*NACARenderServerRenderDisplay)(mach_port_t, CFStringRef, IOSurfaceRef, int32_t, int32_t);
typedef UIImage * NS_RETURNS_RETAINED (*NAUICreateScreenUIImage)(void);

typedef void *NAHIDEventRef;
typedef void *NAHIDEventSystemClientRef;

typedef NAHIDEventSystemClientRef (*NAHIDClientCreateFn)(CFAllocatorRef);
typedef NAHIDEventSystemClientRef (*NAHIDClientCreateSimpleFn)(CFAllocatorRef);
typedef NAHIDEventSystemClientRef (*NAHIDClientCreateWithTypeFn)(CFAllocatorRef, uint32_t, CFDictionaryRef);
typedef void (*NAHIDClientScheduleFn)(NAHIDEventSystemClientRef, CFRunLoopRef, CFRunLoopMode);
typedef NAHIDEventRef (*NAHIDDigitizerCreateFn)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t,
    uint32_t, double, double, double, double, double, Boolean, Boolean, uint32_t
);
typedef NAHIDEventRef (*NAHIDFingerCreateFn)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t,
    double, double, double, double, double, Boolean, Boolean, uint32_t
);
typedef NAHIDEventRef (*NAHIDKeyboardCreateFn)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, Boolean, uint32_t
);
typedef void (*NAHIDAppendFn)(NAHIDEventRef, NAHIDEventRef, uint32_t);
typedef void (*NAHIDSetIntegerFn)(NAHIDEventRef, uint32_t, int64_t);
typedef void (*NAHIDSetSenderFn)(NAHIDEventRef, uint64_t);
typedef void (*NAHIDDispatchFn)(NAHIDEventSystemClientRef, NAHIDEventRef);

static NAHIDClientCreateFn NAHIDCreateClient = NULL;
static NAHIDClientCreateSimpleFn NAHIDCreateSimpleClient = NULL;
static NAHIDClientCreateWithTypeFn NAHIDCreateClientWithType = NULL;
static NAHIDClientScheduleFn NAHIDScheduleClient = NULL;
static NAHIDDigitizerCreateFn NAHIDCreateDigitizer = NULL;
static NAHIDFingerCreateFn NAHIDCreateFinger = NULL;
static NAHIDKeyboardCreateFn NAHIDCreateKeyboard = NULL;
static NAHIDAppendFn NAHIDAppend = NULL;
static NAHIDSetIntegerFn NAHIDSetInteger = NULL;
static NAHIDSetSenderFn NAHIDSetSender = NULL;
static NAHIDDispatchFn NAHIDDispatch = NULL;
static NAHIDEventSystemClientRef NAHIDTouchClient = NULL;
static NAHIDEventSystemClientRef NAHIDKeyboardClient = NULL;
static BOOL NAHIDLoaded = NO;
static NSString *NAHIDClientKind = @"none";

static void NAHIDLoad(void) {
    if (NAHIDLoaded) return;
    NAHIDLoaded = YES;

    void *handle = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit",
        RTLD_NOW | RTLD_GLOBAL
    );
    if (!handle) return;

    NAHIDCreateClient = (NAHIDClientCreateFn)dlsym(handle, "IOHIDEventSystemClientCreate");
    NAHIDCreateSimpleClient = (NAHIDClientCreateSimpleFn)dlsym(handle, "IOHIDEventSystemClientCreateSimpleClient");
    NAHIDCreateClientWithType = (NAHIDClientCreateWithTypeFn)dlsym(handle, "IOHIDEventSystemClientCreateWithType");
    NAHIDScheduleClient = (NAHIDClientScheduleFn)dlsym(handle, "IOHIDEventSystemClientScheduleWithRunLoop");
    NAHIDCreateDigitizer = (NAHIDDigitizerCreateFn)dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    NAHIDCreateFinger = (NAHIDFingerCreateFn)dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
    NAHIDCreateKeyboard = (NAHIDKeyboardCreateFn)dlsym(handle, "IOHIDEventCreateKeyboardEvent");
    NAHIDAppend = (NAHIDAppendFn)dlsym(handle, "IOHIDEventAppendEvent");
    NAHIDSetInteger = (NAHIDSetIntegerFn)dlsym(handle, "IOHIDEventSetIntegerValue");
    NAHIDSetSender = (NAHIDSetSenderFn)dlsym(handle, "IOHIDEventSetSenderID");
    NAHIDDispatch = (NAHIDDispatchFn)dlsym(handle, "IOHIDEventSystemClientDispatchEvent");

    // Touch path follows established SpringBoard injection implementations.
    if (NAHIDCreateClient) {
        NAHIDTouchClient = NAHIDCreateClient(kCFAllocatorDefault);
    }
    if (!NAHIDTouchClient && NAHIDCreateSimpleClient) {
        NAHIDTouchClient = NAHIDCreateSimpleClient(kCFAllocatorDefault);
    }

    // Prefer the admin event-system client for keyboard delivery, then fall
    // back to the default/simple client on builds where type 2 is unavailable.
    if (NAHIDCreateClientWithType) {
        NAHIDKeyboardClient = NAHIDCreateClientWithType(kCFAllocatorDefault, 2, NULL);
        if (NAHIDKeyboardClient) NAHIDClientKind = @"admin_type_2";
    }
    if (!NAHIDKeyboardClient && NAHIDCreateClient) {
        NAHIDKeyboardClient = NAHIDCreateClient(kCFAllocatorDefault);
        if (NAHIDKeyboardClient) NAHIDClientKind = @"default";
    }
    if (!NAHIDKeyboardClient && NAHIDCreateSimpleClient) {
        NAHIDKeyboardClient = NAHIDCreateSimpleClient(kCFAllocatorDefault);
        if (NAHIDKeyboardClient) NAHIDClientKind = @"simple";
    }

    if (NAHIDScheduleClient) {
        if (NAHIDTouchClient) {
            NAHIDScheduleClient(NAHIDTouchClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        }
        if (NAHIDKeyboardClient && NAHIDKeyboardClient != NAHIDTouchClient) {
            NAHIDScheduleClient(NAHIDKeyboardClient, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        }
    }
}

static NSDictionary *NAHIDStatusPayload(void) {
    NAHIDLoad();
    BOOL touchSymbols =
        NAHIDCreateDigitizer && NAHIDCreateFinger && NAHIDAppend && NAHIDDispatch;
    BOOL keyboardSymbols = NAHIDCreateKeyboard && NAHIDDispatch;
    return @{
        @"success": @(touchSymbols && keyboardSymbols && NAHIDTouchClient && NAHIDKeyboardClient),
        @"bridge_version": @"0.7.15",
        @"process": @"SpringBoard",
        @"touch_client": @(NAHIDTouchClient != NULL),
        @"keyboard_client": @(NAHIDKeyboardClient != NULL),
        @"keyboard_admin_client": @(NAHIDKeyboardClient != NULL),
        @"touch_symbols": @(touchSymbols),
        @"keyboard_symbols": @(keyboardSymbols),
        @"dispatch_signature": @"void",
        @"timestamp_source": @"mach_absolute_time",
        @"keyboard_client_type": NAHIDClientKind ?: @"none",
        @"path": @"springboard_iohid_v0715"
    };
}

static BOOL NAHIDDispatchPoint(double x, double y, BOOL down) {
    NAHIDLoad();
    if (!NAHIDTouchClient || !NAHIDCreateDigitizer || !NAHIDCreateFinger ||
        !NAHIDAppend || !NAHIDDispatch) return NO;
    if (x < 0.0 || x > 1.0 || y < 0.0 || y > 1.0) return NO;

    // Same digitizer structure used by working SpringBoard HID injectors:
    // hand transducer (3), integrated-display identity, normalized coordinates.
    const uint32_t kRange = 1u;
    const uint32_t kTouch = 2u;
    const uint32_t kPosition = 4u;
    const uint32_t kIdentity = 32u;

    uint32_t parentMask = kRange | kTouch | kIdentity;
    if (!down) parentMask |= kPosition;
    uint32_t childMask = kRange | kTouch;

    uint64_t now = mach_absolute_time();
    NAHIDEventRef parent = NAHIDCreateDigitizer(
        kCFAllocatorDefault,
        now,
        3,
        1u << 22,
        1,
        parentMask,
        0,
        x,
        y,
        0.0,
        down ? 1.0 : 0.0,
        0.0,
        true,
        down,
        0
    );
    NAHIDEventRef child = NAHIDCreateFinger(
        kCFAllocatorDefault,
        now,
        3,
        2,
        childMask,
        x,
        y,
        0.0,
        down ? 1.0 : 0.0,
        0.0,
        true,
        down,
        0
    );

    if (!parent || !child) {
        if (parent) CFRelease(parent);
        if (child) CFRelease(child);
        return NO;
    }

    if (NAHIDSetInteger) {
        // Built-in + display-integrated digitizer fields.
        NAHIDSetInteger(parent, 4u, 1);
        NAHIDSetInteger(parent, (11u << 16) + 25u, 1);
    }
    if (NAHIDSetSender) {
        NAHIDSetSender(parent, 0x8000000817319375ULL);
    }

    NAHIDAppend(parent, child, 0);
    NAHIDDispatch(NAHIDTouchClient, parent); // private API returns void
    CFRelease(child);
    CFRelease(parent);
    return YES;
}

static BOOL NAHIDKeyboardEvent(uint32_t usage, BOOL down) {
    NAHIDLoad();
    if (!NAHIDKeyboardClient || !NAHIDCreateKeyboard || !NAHIDDispatch) return NO;

    NAHIDEventRef event = NAHIDCreateKeyboard(
        kCFAllocatorDefault,
        mach_absolute_time(),
        0x07u,
        usage,
        down,
        0
    );
    if (!event) return NO;

    if (NAHIDSetSender) {
        NAHIDSetSender(event, 0x8000000817319375ULL);
    }
    NAHIDDispatch(NAHIDKeyboardClient, event); // private API returns void
    CFRelease(event);
    return YES;
}

static int NAHIDUsageForKey(NSString *key) {
    NSString *name = key.lowercaseString ?: @"";
    if ([name isEqualToString:@"enter"] || [name isEqualToString:@"return"]) return 0x28;
    if ([name isEqualToString:@"escape"] || [name isEqualToString:@"esc"]) return 0x29;
    if ([name isEqualToString:@"backspace"] || [name isEqualToString:@"delete"]) return 0x2A;
    if ([name isEqualToString:@"tab"]) return 0x2B;
    if ([name isEqualToString:@"space"]) return 0x2C;
    if ([name isEqualToString:@"right"]) return 0x4F;
    if ([name isEqualToString:@"left"]) return 0x50;
    if ([name isEqualToString:@"down"]) return 0x51;
    if ([name isEqualToString:@"up"]) return 0x52;
    return -1;
}

static BOOL NAHIDUsageForCharacter(unichar c, uint32_t *usage, BOOL *shift) {
    if (!usage || !shift) return NO;
    *shift = NO;

    if (c >= 'a' && c <= 'z') {
        *usage = 0x04u + (uint32_t)(c - 'a');
        return YES;
    }
    if (c >= 'A' && c <= 'Z') {
        *usage = 0x04u + (uint32_t)(c - 'A');
        *shift = YES;
        return YES;
    }
    if (c >= '1' && c <= '9') {
        *usage = 0x1Eu + (uint32_t)(c - '1');
        return YES;
    }
    if (c == '0') {
        *usage = 0x27u;
        return YES;
    }

    switch (c) {
        case ' ': *usage = 0x2Cu; return YES;
        case '\t': *usage = 0x2Bu; return YES;
        case '\n':
        case '\r': *usage = 0x28u; return YES;
        case '-': *usage = 0x2Du; return YES;
        case '=': *usage = 0x2Eu; return YES;
        case '[': *usage = 0x2Fu; return YES;
        case ']': *usage = 0x30u; return YES;
        case '\\': *usage = 0x31u; return YES;
        case ';': *usage = 0x33u; return YES;
        case '\'': *usage = 0x34u; return YES;
        case '`': *usage = 0x35u; return YES;
        case ',': *usage = 0x36u; return YES;
        case '.': *usage = 0x37u; return YES;
        case '/': *usage = 0x38u; return YES;

        case '!': *usage = 0x1Eu; *shift = YES; return YES;
        case '@': *usage = 0x1Fu; *shift = YES; return YES;
        case '#': *usage = 0x20u; *shift = YES; return YES;
        case '$': *usage = 0x21u; *shift = YES; return YES;
        case '%': *usage = 0x22u; *shift = YES; return YES;
        case '^': *usage = 0x23u; *shift = YES; return YES;
        case '&': *usage = 0x24u; *shift = YES; return YES;
        case '*': *usage = 0x25u; *shift = YES; return YES;
        case '(': *usage = 0x26u; *shift = YES; return YES;
        case ')': *usage = 0x27u; *shift = YES; return YES;
        case '_': *usage = 0x2Du; *shift = YES; return YES;
        case '+': *usage = 0x2Eu; *shift = YES; return YES;
        case '{': *usage = 0x2Fu; *shift = YES; return YES;
        case '}': *usage = 0x30u; *shift = YES; return YES;
        case '|': *usage = 0x31u; *shift = YES; return YES;
        case ':': *usage = 0x33u; *shift = YES; return YES;
        case '"': *usage = 0x34u; *shift = YES; return YES;
        case '~': *usage = 0x35u; *shift = YES; return YES;
        case '<': *usage = 0x36u; *shift = YES; return YES;
        case '>': *usage = 0x37u; *shift = YES; return YES;
        case '?': *usage = 0x38u; *shift = YES; return YES;
        default: return NO;
    }
}

static NSDictionary *NAHIDTapPayload(double x, double y, NSInteger count) {
    NAInvalidateOCRCache();
    NSInteger taps = MAX(1, MIN(2, count));
    for (NSInteger i = 0; i < taps; i++) {
        if (!NAHIDDispatchPoint(x, y, YES)) {
            return @{
                @"success": @NO,
                @"error": @"SpringBoard touch-down construction/dispatch failed"
            };
        }
        usleep(55000);
        if (!NAHIDDispatchPoint(x, y, NO)) {
            return @{
                @"success": @NO,
                @"error": @"SpringBoard touch-up construction/dispatch failed"
            };
        }
        if (i + 1 < taps) usleep(90000);
    }
    return @{
        @"success": @YES,
        @"bridge_version": @"0.7.15",
        @"path": @"springboard_iohid_v0715",
        @"count": @(taps)
    };
}

static NSDictionary *NAHIDLongPressPayload(double x, double y, double duration) {
    NAInvalidateOCRCache();
    if (!NAHIDDispatchPoint(x, y, YES)) {
        return @{@"success": @NO, @"error": @"SpringBoard long-press down failed"};
    }
    usleep((useconds_t)(MAX(0.2, MIN(8.0, duration)) * 1000000.0));
    if (!NAHIDDispatchPoint(x, y, NO)) {
        return @{@"success": @NO, @"error": @"SpringBoard long-press up failed"};
    }
    return @{
        @"success": @YES,
        @"bridge_version": @"0.7.15",
        @"path": @"springboard_iohid_v0715"
    };
}

static NSDictionary *NAHIDSwipePayload(
    double x1, double y1, double x2, double y2, double duration
) {
    NAInvalidateOCRCache();
    double clampedDuration = MAX(0.1, MIN(5.0, duration));
    if (!NAHIDDispatchPoint(x1, y1, YES)) {
        return @{@"success": @NO, @"error": @"SpringBoard swipe start failed"};
    }

    NSInteger steps = MAX(8, MIN(60, (NSInteger)llround(clampedDuration * 30.0)));
    useconds_t delay = (useconds_t)((clampedDuration / (double)steps) * 1000000.0);
    for (NSInteger i = 1; i <= steps; i++) {
        double t = (double)i / (double)steps;
        double x = x1 + (x2 - x1) * t;
        double y = y1 + (y2 - y1) * t;
        usleep(delay);
        if (!NAHIDDispatchPoint(x, y, YES)) {
            NAHIDDispatchPoint(x, y, NO);
            return @{@"success": @NO, @"error": @"SpringBoard swipe move failed"};
        }
    }
    usleep(18000);
    if (!NAHIDDispatchPoint(x2, y2, NO)) {
        return @{@"success": @NO, @"error": @"SpringBoard swipe end failed"};
    }
    return @{
        @"success": @YES,
        @"bridge_version": @"0.7.15",
        @"path": @"springboard_iohid_v0715"
    };
}

static NSDictionary *NAHIDKeyPayload(NSString *key) {
    NAInvalidateOCRCache();
    int usage = NAHIDUsageForKey(key);
    if (usage < 0) {
        return @{@"success": @NO, @"error": @"unsupported key"};
    }
    if (!NAHIDKeyboardEvent((uint32_t)usage, YES)) {
        return @{@"success": @NO, @"error": @"SpringBoard keyboard key-down failed"};
    }
    usleep(30000);
    if (!NAHIDKeyboardEvent((uint32_t)usage, NO)) {
        return @{@"success": @NO, @"error": @"SpringBoard keyboard key-up failed"};
    }
    return @{
        @"success": @YES,
        @"bridge_version": @"0.7.15",
        @"path": @"springboard_iohid_v0715"
    };
}

static NSDictionary *NAHIDPastePayload(void) {
    NAInvalidateOCRCache();
    if (!NAHIDKeyboardEvent(0xE3u, YES)) {
        return @{@"success": @NO, @"error": @"SpringBoard command key-down failed"};
    }
    usleep(18000);
    if (!NAHIDKeyboardEvent(0x19u, YES)) {
        NAHIDKeyboardEvent(0xE3u, NO);
        return @{@"success": @NO, @"error": @"SpringBoard V key-down failed"};
    }
    usleep(30000);
    NAHIDKeyboardEvent(0x19u, NO);
    usleep(18000);
    NAHIDKeyboardEvent(0xE3u, NO);

    return @{
        @"success": @YES,
        @"bridge_version": @"0.7.15",
        @"path": @"springboard_iohid_v0715_cmd_v"
    };
}

static NSDictionary *NAHIDTypeTextPayload(NSString *text) {
    NAInvalidateOCRCache();
    if (!text.length || text.length > 4096) {
        return @{@"success": @NO, @"error": @"text length must be 1...4096"};
    }

    NSUInteger typed = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        uint32_t usage = 0;
        BOOL shift = NO;

        if (!NAHIDUsageForCharacter(c, &usage, &shift)) {
            return @{
                @"success": @NO,
                @"error": [NSString stringWithFormat:@"unsupported direct HID character at index %lu", (unsigned long)i],
                @"typed_characters": @(typed)
            };
        }

        if (shift && !NAHIDKeyboardEvent(0xE1u, YES)) {
            return @{@"success": @NO, @"error": @"shift key-down failed", @"typed_characters": @(typed)};
        }

        BOOL downOK = NAHIDKeyboardEvent(usage, YES);
        usleep(4500);
        BOOL upOK = NAHIDKeyboardEvent(usage, NO);

        if (shift) {
            usleep(2500);
            NAHIDKeyboardEvent(0xE1u, NO);
        }
        if (!downOK || !upOK) {
            return @{@"success": @NO, @"error": @"character HID dispatch failed", @"typed_characters": @(typed)};
        }

        typed++;
        usleep(5500);
    }

    return @{
        @"success": @YES,
        @"bridge_version": @"0.7.15",
        @"path": @"springboard_iohid_v0715_direct_text",
        @"typed_characters": @(typed)
    };
}

static uint64_t NAHUDPackedState(NSString *mode, NSString *message, CGFloat progress) {
    uint64_t modeCode = 0;
    if ([mode isEqualToString:@"working"]) modeCode = 1;
    else if ([mode isEqualToString:@"complete"]) modeCode = 2;
    else if ([mode isEqualToString:@"failed"]) modeCode = 3;
    else if ([mode isEqualToString:@"stopped"]) modeCode = 4;

    NSString *lower = message.lowercaseString ?: @"";
    uint64_t detailCode = 0;
    if ([lower containsString:@"opening"]) detailCode = 1;
    else if ([lower containsString:@"reading"] || [lower containsString:@"screen"]) detailCode = 2;
    else if ([lower containsString:@"typing"]) detailCode = 3;
    else if ([lower containsString:@"tap"] || [lower containsString:@"interact"]) detailCode = 4;
    else if ([lower containsString:@"planning"]) detailCode = 5;
    else if ([lower containsString:@"resum"] || [lower containsString:@"waiting"]) detailCode = 6;
    else if ([lower containsString:@"checking"]) detailCode = 7;
    else if ([lower containsString:@"thinking"]) detailCode = 8;
    else if ([lower containsString:@"return"]) detailCode = 9;

    uint64_t progressCode = (uint64_t)llround(MAX(0.0, MIN(1.0, progress)) * 1000.0);
    return (modeCode << 56) | (detailCode << 48) | progressCode;
}

static void NABroadcastHUDState(NSString *mode, NSString *message, CGFloat progress) {
    if (NAHUDStateToken < 0) {
        notify_register_check(NAHUDStateNotification, &NAHUDStateToken);
    }
    if (NAHUDStateToken >= 0) {
        notify_set_state(NAHUDStateToken, NAHUDPackedState(mode, message, progress));
    }
    notify_post(NAHUDStateNotification);
}

static id NARBSAssertion = nil;
static id NABKSAssertion = nil;
static pid_t NAProtectedPID = 0;
static NSString *NAProtectionMethod = @"none";
static NSString *NAProtectionDetail = @"not acquired";
static pid_t NALastProtectedPID = 0;
static NSString *NALastProtectionMethod = @"none";
static NSString *NALastProtectionDetail = @"not attempted";
static NSString *NALastProtectionFailure = @"";
static NSTimeInterval NALastProtectionAcquiredAt = 0.0;
static NSTimeInterval NALastProtectionReleasedAt = 0.0;

static BOOL NAObjectValid(id assertion) {
    if (!assertion) return NO;
    SEL valid = NSSelectorFromString(@"valid");
    if ([assertion respondsToSelector:valid]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(assertion, valid);
    }
    SEL isValid = NSSelectorFromString(@"isValid");
    if ([assertion respondsToSelector:isValid]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(assertion, isValid);
    }
    return YES;
}

static void NAReleaseProtection(void) {
    if (NAProtectedPID > 1) {
        NALastProtectedPID = NAProtectedPID;
        NALastProtectionMethod = NAProtectionMethod ?: @"none";
        NALastProtectionDetail = NAProtectionDetail ?: @"";
    }
    for (id assertion in @[NARBSAssertion ?: NSNull.null, NABKSAssertion ?: NSNull.null]) {
        if (assertion == (id)NSNull.null) continue;
        SEL invalidate = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:invalidate]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
        }
    }
    NARBSAssertion = nil;
    NABKSAssertion = nil;
    NAProtectedPID = 0;
    NAProtectionMethod = @"none";
    NAProtectionDetail = @"released";
    NALastProtectionReleasedAt = [[NSDate date] timeIntervalSince1970];
}

static BOOL NAAcquireRBSProtection(pid_t pid) {
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    if (!handle) {
        NAProtectionDetail = @"RunningBoardServices unavailable";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    Class targetClass = NSClassFromString(@"RBSTarget");
    Class legacyClass = NSClassFromString(@"RBSLegacyAttribute");
    Class assertionClass = NSClassFromString(@"RBSAssertion");
    if (!targetClass || !legacyClass || !assertionClass) {
        NAProtectionDetail = @"RBS classes unavailable";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    id target = nil;
    SEL targetWithPid = NSSelectorFromString(@"targetWithPid:");
    if ([targetClass respondsToSelector:targetWithPid]) {
        target = ((id (*)(id, SEL, int))objc_msgSend)((id)targetClass, targetWithPid, pid);
    }
    if (!target) {
        Class identifierClass = NSClassFromString(@"RBSProcessIdentifier");
        SEL identifierWithPid = NSSelectorFromString(@"identifierWithPid:");
        SEL targetWithIdentifier = NSSelectorFromString(@"targetWithProcessIdentifier:");
        if (identifierClass &&
            [identifierClass respondsToSelector:identifierWithPid] &&
            [targetClass respondsToSelector:targetWithIdentifier]) {
            id identifier = ((id (*)(id, SEL, int))objc_msgSend)(
                (id)identifierClass, identifierWithPid, pid
            );
            if (identifier) {
                target = ((id (*)(id, SEL, id))objc_msgSend)(
                    (id)targetClass, targetWithIdentifier, identifier
                );
            }
        }
    }
    if (!target) {
        NAProtectionDetail = @"RBSTarget could not be created from pid or process identifier";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    // Same legacy assertion flags used by established jailbreak backgrounders:
    // prevent suspend, prevent task throttle, foreground resource priority and UI throttle.
    const unsigned int flags = (1u << 0) | (1u << 1) | (1u << 3) | (1u << 5);
    SEL attrSel = NSSelectorFromString(@"attributeWithReason:flags:");
    if (![legacyClass respondsToSelector:attrSel]) {
        NAProtectionDetail = @"RBSLegacyAttribute selector unavailable";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }
    typedef id (*AttrFn)(id, SEL, unsigned int, unsigned int);
    id legacy = ((AttrFn)objc_msgSend)((id)legacyClass, attrSel, 7u, flags);
    if (!legacy) {
        NAProtectionDetail = @"RBSLegacyAttribute creation failed";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    NSMutableArray *attributes = [NSMutableArray arrayWithObject:legacy];

    Class socketGrantClass = NSClassFromString(@"RBSAppNapPreventBackgroundSocketsGrant");
    if (socketGrantClass && [socketGrantClass respondsToSelector:@selector(grant)]) {
        id grant = ((id (*)(id, SEL))objc_msgSend)((id)socketGrantClass, @selector(grant));
        if (grant) [attributes addObject:grant];
    }

    id assertionObject = ((id (*)(id, SEL))objc_msgSend)((id)assertionClass, @selector(alloc));
    SEL initSel = NSSelectorFromString(@"initWithExplanation:target:attributes:");
    if (!assertionObject || ![assertionObject respondsToSelector:initSel]) {
        NAProtectionDetail = @"RBSAssertion initializer unavailable";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    typedef id (*InitFn)(id, SEL, id, id, id);
    id assertion = ((InitFn)objc_msgSend)(
        assertionObject,
        initSel,
        @"Next Agent active automation",
        target,
        attributes
    );
    if (!assertion) {
        NAProtectionDetail = @"RBSAssertion creation failed";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    NSError *error = nil;
    BOOL acquired = NO;
    SEL acquireSel = NSSelectorFromString(@"acquireWithError:");
    if ([assertion respondsToSelector:acquireSel]) {
        typedef BOOL (*AcquireFn)(id, SEL, NSError **);
        acquired = ((AcquireFn)objc_msgSend)(assertion, acquireSel, &error);
    } else {
        SEL acquire = NSSelectorFromString(@"acquire");
        if ([assertion respondsToSelector:acquire]) {
            acquired = ((BOOL (*)(id, SEL))objc_msgSend)(assertion, acquire);
        }
    }

    if (!acquired || !NAObjectValid(assertion)) {
        SEL invalidate = NSSelectorFromString(@"invalidate");
        if ([assertion respondsToSelector:invalidate]) {
            ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
        }
        NAProtectionDetail = error.localizedDescription ?: @"RBS assertion was not valid";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    NARBSAssertion = assertion;
    NAProtectedPID = pid;
    NAProtectionMethod = @"RBSAssertion";
    NAProtectionDetail = @"SpringBoard-held RBS assertion active";
    NALastProtectedPID = pid;
    NALastProtectionMethod = NAProtectionMethod;
    NALastProtectionDetail = NAProtectionDetail;
    NALastProtectionFailure = @"";
    NALastProtectionAcquiredAt = [[NSDate date] timeIntervalSince1970];
    return YES;
}

static BOOL NAAcquireBKSFallback(pid_t pid) {
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    if (!handle) {
        NAProtectionDetail = @"AssertionServices unavailable";
        return NO;
    }

    Class cls = NSClassFromString(@"BKSProcessAssertion");
    if (!cls) {
        NAProtectionDetail = @"BKSProcessAssertion unavailable";
        return NO;
    }

    const unsigned int flags = (1u << 0) | (1u << 1) | (1u << 3) | (1u << 5);
    id object = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(alloc));
    if (!object) return NO;

    id assertion = nil;

    SEL bundlePid = NSSelectorFromString(
        @"initWithBundleIdentifier:pid:flags:reason:name:withHandler:acquire:"
    );
    if ([object respondsToSelector:bundlePid]) {
        typedef id (*BundlePidFn)(id, SEL, id, int, unsigned int, unsigned int, id, id, BOOL);
        assertion = ((BundlePidFn)objc_msgSend)(
            object, bundlePid, NABundleID, pid, flags, 10005u,
            @"NextAgentSpringBoardFallback", nil, YES
        );
    }

    if (!assertion || !NAObjectValid(assertion)) {
        id secondObject = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(alloc));
        SEL six = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:acquire:");
        if ([secondObject respondsToSelector:six]) {
            typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id, id, BOOL);
            assertion = ((Fn)objc_msgSend)(
                secondObject, six, pid, flags, 10005u,
                @"NextAgentSpringBoardFallback", nil, YES
            );
        }
    }

    if (!assertion || !NAObjectValid(assertion)) {
        NAProtectionDetail = @"BKS fallback could not be acquired";
        NALastProtectionFailure = NAProtectionDetail;
        return NO;
    }

    NABKSAssertion = assertion;
    NAProtectedPID = pid;
    NAProtectionMethod = @"BKSProcessAssertion";
    NAProtectionDetail = @"SpringBoard-held BKS fallback active";
    NALastProtectedPID = pid;
    NALastProtectionMethod = NAProtectionMethod;
    NALastProtectionDetail = NAProtectionDetail;
    NALastProtectionFailure = @"";
    NALastProtectionAcquiredAt = [[NSDate date] timeIntervalSince1970];
    return YES;
}

static BOOL NAEnsureProcessProtection(pid_t pid) {
    if (pid <= 1 || kill(pid, 0) != 0) {
        NAReleaseProtection();
        return NO;
    }

    if (NAProtectedPID == pid &&
        ((NARBSAssertion && NAObjectValid(NARBSAssertion)) ||
         (NABKSAssertion && NAObjectValid(NABKSAssertion)))) {
        return YES;
    }

    NAReleaseProtection();
    if (NAAcquireRBSProtection(pid)) return YES;
    return NAAcquireBKSFallback(pid);
}

static void NAEnsureDirectory(NSString *path) {
    [[NSFileManager defaultManager] createDirectoryAtPath:path
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions:@0755}
                                                    error:nil];
}

static BOOL NAWriteJSON(NSDictionary *dictionary, NSString *path) {
    if (!dictionary || !path) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    if (!data) return NO;
    NSString *dir = [path stringByDeletingLastPathComponent];
    NAEnsureDirectory(dir);
    return [data writeToFile:path options:NSDataWritingAtomic error:nil];
}

static NSDictionary *NAReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data.length) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

@interface NAPassThroughWindow : UIWindow
@end

@implementation NAPassThroughWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return NO;
}
- (BOOL)canBecomeKeyWindow {
    return NO;
}
@end

@interface NAProgressOverlay : NSObject
@property(nonatomic,strong) NAPassThroughWindow *window;
@property(nonatomic,strong) UIView *pill;
@property(nonatomic,strong) UILabel *iconLabel;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) UIView *track;
@property(nonatomic,strong) UIView *fill;
@property(nonatomic,strong) NSLayoutConstraint *fillWidth;
@property(nonatomic,strong) NSTimer *pollTimer;
@property(nonatomic,assign) BOOL visible;
@property(nonatomic,copy) NSString *lastCaptureSource;
@property(nonatomic,strong) id systemHUDController;
@property(nonatomic,strong) id systemHUDSession;
@property(nonatomic,strong) UIViewController *systemHUDViewController;
@property(nonatomic,strong) UIView *systemHUDPill;
@property(nonatomic,strong) UILabel *systemHUDTitle;
@property(nonatomic,strong) UILabel *systemHUDIcon;
@property(nonatomic,strong) UIActivityIndicatorView *systemHUDSpinner;
@property(nonatomic,assign) BOOL systemHUDAvailable;
@property(nonatomic,assign) BOOL systemHUDVisible;
@property(nonatomic,assign) BOOL captureHadSystemHUD;
@property(nonatomic,copy) NSString *hudFailureStage;
@property(nonatomic,copy) NSString *hudFailureDetail;
+ (instancetype)shared;
- (void)refresh;
- (void)ensureSystemHUD;
- (BOOL)showSystemHUD;
- (void)hideSystemHUD;
- (void)updateSystemHUDMode:(NSString *)mode message:(NSString *)message progress:(CGFloat)progress;
- (void)setCapturePresentationSuppressed:(BOOL)suppressed;
- (NSDictionary *)hudStatusPayload;
- (void)captureRequested;
- (UIImage *)captureDisplayWithSource:(NSString **)sourceOut
                              quality:(NSDictionary **)qualityOut;
- (NSDictionary *)directCapturePayload;
- (NSDictionary *)directOCRPayloadFast:(BOOL)fast
                              languages:(NSArray<NSString *> *)languages
                               maxItems:(NSInteger)maxItems;
@end

@implementation NAProgressOverlay

+ (instancetype)shared {
    static NAProgressOverlay *value;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ value = [NAProgressOverlay new]; });
    return value;
}

- (BOOL)systemHUDSessionVisible {
    id session = self.systemHUDSession;
    if (!session) return NO;
    for (NSString *name in @[@"isVisible", @"isPresented", @"isPresenting"]) {
        SEL sel = NSSelectorFromString(name);
        if ([session respondsToSelector:sel] &&
            ((BOOL (*)(id, SEL))objc_msgSend)(session, sel)) {
            return YES;
        }
    }
    if (self.systemHUDController) {
        SEL any = NSSelectorFromString(@"anyHUDsVisible");
        if ([self.systemHUDController respondsToSelector:any]) {
            return ((BOOL (*)(id, SEL))objc_msgSend)(self.systemHUDController, any);
        }
    }
    return NO;
}

- (void)ensureSystemHUD {
    if (self.systemHUDController && self.systemHUDSession && self.systemHUDViewController) return;

    self.hudFailureStage = @"starting";
    self.hudFailureDetail = @"";

    @try {
        Class workspaceClass = NSClassFromString(@"SBMainWorkspace");
        if (!workspaceClass) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"workspace_class";
            self.hudFailureDetail = @"SBMainWorkspace class unavailable";
            return;
        }

        id workspace = nil;
        SEL ifExists = NSSelectorFromString(@"sharedInstanceIfExists");
        SEL shared = NSSelectorFromString(@"sharedInstance");
        if ([workspaceClass respondsToSelector:ifExists]) {
            workspace = ((id (*)(id, SEL))objc_msgSend)((id)workspaceClass, ifExists);
        }
        if (!workspace && [workspaceClass respondsToSelector:shared]) {
            workspace = ((id (*)(id, SEL))objc_msgSend)((id)workspaceClass, shared);
        }
        if (!workspace) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"workspace_instance";
            self.hudFailureDetail = @"SBMainWorkspace instance unavailable";
            return;
        }

        SEL hudSelector = NSSelectorFromString(@"HUDController");
        if (![workspace respondsToSelector:hudSelector]) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"hud_controller_selector";
            self.hudFailureDetail = @"SBMainWorkspace does not expose HUDController";
            return;
        }

        id hudController = ((id (*)(id, SEL))objc_msgSend)(workspace, hudSelector);
        if (!hudController) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"hud_controller_instance";
            self.hudFailureDetail = @"HUDController returned nil";
            return;
        }

        SEL sessionSelector = NSSelectorFromString(@"HUDSessionForViewController:identifier:");
        if (![hudController respondsToSelector:sessionSelector]) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"hud_session_selector";
            self.hudFailureDetail = @"HUDSessionForViewController:identifier: unavailable";
            return;
        }

        // Use SBHUDViewController when present, but do not make it mandatory.
        // Some iOS 16 builds do not export that class even though SBHUDController
        // can host a plain UIViewController through HUDSessionForViewController.
        Class nativeHUDClass = NSClassFromString(@"SBHUDViewController");
        UIViewController *controller = nil;
        if (nativeHUDClass) {
            id allocated = ((id (*)(id, SEL))objc_msgSend)((id)nativeHUDClass, @selector(alloc));
            if (allocated) {
                controller = ((id (*)(id, SEL))objc_msgSend)(allocated, @selector(init));
            }
        }
        if (!controller) {
            controller = [UIViewController new];
            controller.preferredContentSize = CGSizeMake(238.0, 48.0);
        }
        if (!controller) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"hud_view_controller";
            self.hudFailureDetail = @"Could not create HUD view controller";
            return;
        }

        // Configure native properties when available. Plain-controller fallback
        // still gets a compact custom view.
        SEL titleSel = NSSelectorFromString(@"setTitle:");
        SEL subtitleSel = NSSelectorFromString(@"setSubtitle:");
        SEL progressSel = NSSelectorFromString(@"setProgress:");
        SEL showsProgressSel = NSSelectorFromString(@"setShowsProgress:");
        SEL imageSel = NSSelectorFromString(@"setImage:");

        if ([controller respondsToSelector:titleSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, titleSel, @"Next Agent");
        }
        if ([controller respondsToSelector:subtitleSel]) {
            ((void (*)(id, SEL, id))objc_msgSend)(controller, subtitleSel, @"Working…");
        }
        if ([controller respondsToSelector:progressSel]) {
            ((void (*)(id, SEL, double))objc_msgSend)(controller, progressSel, 0.05);
        }
        if ([controller respondsToSelector:showsProgressSel]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, showsProgressSel, YES);
        }
        if ([controller respondsToSelector:imageSel]) {
            UIImage *image = [UIImage systemImageNamed:@"bolt.horizontal.circle.fill"];
            if (image) ((void (*)(id, SEL, id))objc_msgSend)(controller, imageSel, image);
        }

        if (!nativeHUDClass) {
            controller.view.backgroundColor = UIColor.clearColor;
            UIView *pill = [[UIView alloc] initWithFrame:CGRectMake(3, 4, 232, 40)];
            pill.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.96];
            pill.layer.cornerRadius = 20.0;
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, 4, 208, 32)];
            label.text = @"Next Agent • Working";
            label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
            label.textColor = UIColor.whiteColor;
            label.textAlignment = NSTextAlignmentCenter;
            [pill addSubview:label];
            [controller.view addSubview:pill];
            self.systemHUDPill = pill;
            self.systemHUDTitle = label;
        }

        id session = ((id (*)(id, SEL, id, id))objc_msgSend)(
            hudController,
            sessionSelector,
            controller,
            @"uk.zeshanbarvi.nextagent.status.v0715"
        );
        if (!session) {
            self.systemHUDAvailable = NO;
            self.hudFailureStage = @"hud_session_create";
            self.hudFailureDetail = @"HUD session creation returned nil";
            return;
        }

        self.systemHUDController = hudController;
        self.systemHUDSession = session;
        self.systemHUDViewController = controller;
        self.systemHUDAvailable = YES;
        self.hudFailureStage = @"ready";
        self.hudFailureDetail = nativeHUDClass
            ? @"SBHUDViewController session created"
            : @"plain UIViewController HUD session created";
    } @catch (NSException *exception) {
        self.systemHUDAvailable = NO;
        self.hudFailureStage = @"exception";
        self.hudFailureDetail = [NSString stringWithFormat:@"%@: %@",
            exception.name ?: @"NSException",
            exception.reason ?: @"unknown"];
    }
}

- (BOOL)showSystemHUD {
    [self ensureSystemHUD];
    if (!self.systemHUDAvailable || !self.systemHUDSession) return NO;

    @try {
        if (![self systemHUDSessionVisible]) {
            SEL presentInterval = NSSelectorFromString(@"presentWithDismissalInterval:animated:");
            if ([self.systemHUDSession respondsToSelector:presentInterval]) {
                ((void (*)(id, SEL, double, BOOL))objc_msgSend)(
                    self.systemHUDSession,
                    presentInterval,
                    3600.0,
                    NO
                );
            } else {
                SEL direct = NSSelectorFromString(@"_presentHUD:animated:");
                if (![self.systemHUDController respondsToSelector:direct]) return NO;
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                    self.systemHUDController,
                    direct,
                    self.systemHUDSession,
                    NO
                );
            }
        }

        BOOL visible = [self systemHUDSessionVisible];
        self.systemHUDVisible = visible;
        if (!visible) {
            self.hudFailureStage = @"present_not_visible";
            self.hudFailureDetail = @"HUD session accepted presentation request but did not become visible";
        } else {
            self.hudFailureStage = @"visible";
            self.hudFailureDetail = @"Native SpringBoard HUD visible";
        }
        return visible;
    } @catch (NSException *exception) {
        self.systemHUDAvailable = NO;
        self.systemHUDVisible = NO;
        self.hudFailureStage = @"present_exception";
        self.hudFailureDetail = [NSString stringWithFormat:@"%@: %@",
            exception.name ?: @"NSException",
            exception.reason ?: @"unknown"];
        return NO;
    }
}

- (void)hideSystemHUD {
    if (!self.systemHUDSession) {
        self.systemHUDVisible = NO;
        return;
    }
    @try {
        SEL dismiss = NSSelectorFromString(@"dismissAnimated:");
        if ([self.systemHUDSession respondsToSelector:dismiss]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(self.systemHUDSession, dismiss, NO);
        } else {
            SEL direct = NSSelectorFromString(@"_dismissHUD:animated:");
            if (self.systemHUDController && [self.systemHUDController respondsToSelector:direct]) {
                ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                    self.systemHUDController,
                    direct,
                    self.systemHUDSession,
                    NO
                );
            }
        }
    } @catch (__unused NSException *exception) {
    }
    self.systemHUDVisible = NO;
}

- (void)updateSystemHUDMode:(NSString *)mode message:(NSString *)message progress:(CGFloat)progress {
    [self ensureSystemHUD];
    id controller = self.systemHUDViewController;
    if (!self.systemHUDAvailable || !controller) return;

    NSString *text = message.length ? message : @"Working…";
    NSString *subtitle = text;
    UIImage *image = nil;
    BOOL working = [mode isEqualToString:@"working"];

    if (working) {
        image = [UIImage systemImageNamed:@"bolt.horizontal.circle.fill"];
    } else if ([mode isEqualToString:@"complete"]) {
        image = [UIImage systemImageNamed:@"checkmark.circle.fill"];
        subtitle = message.length ? message : @"Task complete";
    } else if ([mode isEqualToString:@"stopped"]) {
        image = [UIImage systemImageNamed:@"stop.circle.fill"];
        subtitle = message.length ? message : @"Task stopped";
    } else {
        image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        subtitle = message.length ? message : @"Action failed";
    }

    SEL titleSel = NSSelectorFromString(@"setTitle:");
    SEL subtitleSel = NSSelectorFromString(@"setSubtitle:");
    SEL showsProgressSel = NSSelectorFromString(@"setShowsProgress:");
    SEL progressSel = NSSelectorFromString(@"setProgress:");
    SEL imageSel = NSSelectorFromString(@"setImage:");

    if ([controller respondsToSelector:titleSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, titleSel, @"Next Agent");
    }
    if ([controller respondsToSelector:subtitleSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, subtitleSel, subtitle);
    }
    if ([controller respondsToSelector:showsProgressSel]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(controller, showsProgressSel, working);
    }
    if ([controller respondsToSelector:progressSel]) {
        ((void (*)(id, SEL, double))objc_msgSend)(
            controller,
            progressSel,
            MAX(0.02, MIN(1.0, progress))
        );
    }
    if (image && [controller respondsToSelector:imageSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(controller, imageSel, image);
    }
}

- (void)setCapturePresentationSuppressed:(BOOL)suppressed {
    self.pill.hidden = suppressed || self.systemHUDVisible;

    if (suppressed) {
        self.captureHadSystemHUD = self.systemHUDVisible || [self systemHUDSessionVisible];
        if (self.captureHadSystemHUD) [self hideSystemHUD];
        return;
    }

    if (self.captureHadSystemHUD && self.visible) {
        [self showSystemHUD];
    }
    self.captureHadSystemHUD = NO;
    self.pill.hidden = self.systemHUDVisible;
}

- (NSDictionary *)hudStatusPayload {
    [self ensureSystemHUD];

    id session = self.systemHUDSession;
    id controller = self.systemHUDViewController;
    id hudWindow = nil;
    SEL windowSel = NSSelectorFromString(@"HUDWindow");
    if (self.systemHUDController && [self.systemHUDController respondsToSelector:windowSel]) {
        hudWindow = ((id (*)(id, SEL))objc_msgSend)(self.systemHUDController, windowSel);
    }

    BOOL visible = [self systemHUDSessionVisible];
    BOOL isPresented = NO;
    BOOL isPresenting = NO;
    SEL presentedSel = NSSelectorFromString(@"isPresented");
    SEL presentingSel = NSSelectorFromString(@"isPresenting");
    if (session && [session respondsToSelector:presentedSel]) {
        isPresented = ((BOOL (*)(id, SEL))objc_msgSend)(session, presentedSel);
    }
    if (session && [session respondsToSelector:presentingSel]) {
        isPresenting = ((BOOL (*)(id, SEL))objc_msgSend)(session, presentingSel);
    }

    BOOL windowHidden = YES;
    double windowLevel = 0.0;
    if ([hudWindow isKindOfClass:UIWindow.class]) {
        UIWindow *w = (UIWindow *)hudWindow;
        windowHidden = w.hidden;
        windowLevel = w.windowLevel;
    }

    return @{
        @"success": @(self.systemHUDAvailable),
        @"bridge_version": @"0.7.15",
        @"hud_view_controller_class_available": @(NSClassFromString(@"SBHUDViewController") != nil),
        @"hud_controller_class": self.systemHUDController ? NSStringFromClass([self.systemHUDController class]) : @"",
        @"hud_view_controller_class": controller ? NSStringFromClass([controller class]) : @"",
        @"hud_session_class": session ? NSStringFromClass([session class]) : @"",
        @"session_visible": @(visible),
        @"session_presented": @(isPresented),
        @"session_presenting": @(isPresenting),
        @"hud_window_exists": @(hudWindow != nil),
        @"hud_window_hidden": @(windowHidden),
        @"hud_window_level": @(windowLevel),
        @"fallback_window_ready": @(self.window != nil),
        @"fallback_window_visible": @(self.window != nil && !self.window.hidden),
        @"status_surface_generation": @"native_sbhud_v0715",
        @"hud_failure_stage": self.hudFailureStage ?: @"",
        @"hud_failure_detail": self.hudFailureDetail ?: @"",
        @"foreground_hud_fallback_expected": @YES,
        @"foreground_hud_fallback_path": @"/usr/lib/TweakInject/NextAgentForegroundHUD0714.dylib"
    };
}

- (UIWindowScene *)preferredWindowScene {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (!fallback) fallback = windowScene;
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                return windowScene;
            }
        }
        return fallback;
    }
    return nil;
}

- (void)ensureUI {
    if (self.window) return;

    UIScreen *screen = UIScreen.mainScreen;

    // IMPORTANT: this window belongs to SpringBoard itself, not to the
    // SpringBoard home-screen UIWindowScene. A scene-bound window can vanish
    // from the compositor when another application becomes foreground.
    // A process-level SpringBoard window at a system-high level remains
    // available while Notes/Settings/etc. are frontmost.
    NAPassThroughWindow *window = [[NAPassThroughWindow alloc] initWithFrame:screen.bounds];
    window.screen = screen;
    window.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    window.windowLevel = 10000.0;

    SEL secureSelector = NSSelectorFromString(@"_setSecure:");
    if ([window respondsToSelector:secureSelector]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(window, secureSelector, YES);
    }
    window.backgroundColor = UIColor.clearColor;
    window.opaque = NO;
    window.userInteractionEnabled = NO;
    window.hidden = YES;

    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    controller.view.userInteractionEnabled = NO;
    window.rootViewController = controller;

    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    pill.layer.cornerRadius = 18.0;
    pill.layer.masksToBounds = YES;
    pill.layer.borderWidth = 0.75;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    pill.layer.shadowColor = [UIColor colorWithRed:0.1 green:0.78 blue:1 alpha:1].CGColor;
    pill.layer.shadowOpacity = 0.30;
    pill.layer.shadowRadius = 10.0;
    pill.layer.shadowOffset = CGSizeZero;
    [controller.view addSubview:pill];

    [NSLayoutConstraint activateConstraints:@[
        [pill.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:4.0],
        [pill.widthAnchor constraintLessThanOrEqualToConstant:220.0],
        [pill.widthAnchor constraintGreaterThanOrEqualToConstant:170.0],
        [pill.heightAnchor constraintEqualToConstant:36.0]
    ]];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.transform = CGAffineTransformMakeScale(0.70, 0.70);
    spinner.color = [UIColor colorWithRed:0.20 green:0.88 blue:1.0 alpha:1.0];
    [pill addSubview:spinner];

    UILabel *icon = [UILabel new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.textColor = [UIColor colorWithRed:0.26 green:0.96 blue:0.64 alpha:1.0];
    icon.hidden = YES;
    [pill addSubview:icon];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:11.8 weight:UIFontWeightSemibold];
    title.textColor = UIColor.whiteColor;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    title.textAlignment = NSTextAlignmentCenter;
    [pill addSubview:title];

    UIView *track = [UIView new];
    track.translatesAutoresizingMaskIntoConstraints = NO;
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    track.layer.cornerRadius = 1.0;
    [pill addSubview:track];

    UIView *fill = [UIView new];
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    fill.backgroundColor = [UIColor colorWithRed:0.17 green:0.83 blue:1 alpha:1.0];
    fill.layer.cornerRadius = 1.0;
    [track addSubview:fill];

    NSLayoutConstraint *fillWidth = [fill.widthAnchor constraintEqualToConstant:2.0];

    [NSLayoutConstraint activateConstraints:@[
        [spinner.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10.0],
        [spinner.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1.0],
        [spinner.widthAnchor constraintEqualToConstant:18.0],
        [spinner.heightAnchor constraintEqualToConstant:18.0],

        [icon.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10.0],
        [icon.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1.0],
        [icon.widthAnchor constraintEqualToConstant:18.0],
        [icon.heightAnchor constraintEqualToConstant:18.0],

        [title.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:33.0],
        [title.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10.0],
        [title.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-2.0],

        [track.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:12.0],
        [track.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-12.0],
        [track.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-4.0],
        [track.heightAnchor constraintEqualToConstant:2.0],

        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        fillWidth
    ]];

    self.window = window;
    self.pill = pill;
    self.spinner = spinner;
    self.iconLabel = icon;
    self.titleLabel = title;
    self.track = track;
    self.fill = fill;
    self.fillWidth = fillWidth;

    [controller.view layoutIfNeeded];
    [self writeOverlayStatus];
}

- (void)writeOverlayStatus {
    NSDictionary *progressState = NAReadJSON(NAProgressPath);
    NSString *progressMode = [progressState[@"state"] isKindOfClass:NSString.class]
        ? progressState[@"state"] : @"idle";
    NSString *progressUpdated = [progressState[@"updated_at"] isKindOfClass:NSString.class]
        ? progressState[@"updated_at"] : @"";
    NSDictionary *state = @{
        @"progress_state": progressMode,
        @"progress_updated_at": progressUpdated,
        @"loaded": @YES,
        @"overlay_generation": @"0.7.15",
        @"pid": @(getpid()),
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"window_ready": @(self.window != nil),
        @"window_level": @(self.window ? self.window.windowLevel : 0.0),
        @"visible": @(self.visible),
        @"system_hud_available": @(self.systemHUDAvailable),
        @"status_surface_generation": @"native_sbhud_v0715",
        @"system_hud_visible": @(self.systemHUDVisible),
        @"status_surface": self.systemHUDVisible ? @"springboard_hud" : (self.visible ? @"window_fallback" : @"none"),
        @"protected_pid": @(NAProtectedPID),
        @"assertion_valid": @((NARBSAssertion && NAObjectValid(NARBSAssertion)) ||
                              (NABKSAssertion && NAObjectValid(NABKSAssertion))),
        @"protection_method": NAProtectionMethod ?: @"none",
        @"protection_detail": NAProtectionDetail ?: @"",
        @"last_protected_pid": @(NALastProtectedPID),
        @"last_protection_method": NALastProtectionMethod ?: @"none",
        @"last_protection_detail": NALastProtectionDetail ?: @"",
        @"last_protection_failure": NALastProtectionFailure ?: @"",
        @"last_protection_acquired_at": @(NALastProtectionAcquiredAt),
        @"last_protection_released_at": @(NALastProtectionReleasedAt),
        @"hud_failure_stage": self.hudFailureStage ?: @"",
        @"hud_failure_detail": self.hudFailureDetail ?: @"",
        @"foreground_hud_fallback_expected": @YES,
        @"last_capture_source": self.lastCaptureSource ?: @"",
        @"updated_at": @([[NSDate date] timeIntervalSince1970])
    };
    NAWriteJSON(state, NAOverlayStatusPath);
}

- (void)setProgress:(CGFloat)value animated:(BOOL)animated {
    [self ensureUI];
    CGFloat clamped = MAX(0.02, MIN(1.0, value));
    [self.pill layoutIfNeeded];
    CGFloat width = MAX(2.0, self.pill.bounds.size.width - 24.0);
    self.fillWidth.constant = width * clamped;
    if (animated) {
        [UIView animateWithDuration:0.22 animations:^{
            [self.pill layoutIfNeeded];
        }];
    } else {
        [self.pill layoutIfNeeded];
    }
}

- (void)show {
    [self ensureUI];
    BOOL systemShown = [self showSystemHUD];
    if (systemShown) {
        self.window.hidden = YES;
        self.pill.hidden = YES;
    } else {
        self.window.hidden = NO;
        self.window.alpha = 1.0;
        self.pill.hidden = NO;
    }
    self.visible = YES;
    [self writeOverlayStatus];
}

- (void)hide {
    [self hideSystemHUD];
    if (self.window) self.window.hidden = YES;
    self.visible = NO;
    [self writeOverlayStatus];
}

- (void)startPermanentPolling {
    if (self.pollTimer) return;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                     target:self
                                                   selector:@selector(refresh)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)returnToNextAgent {
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) return;
    id workspace = ((id (*)(id, SEL))objc_msgSend)((id)workspaceClass, NSSelectorFromString(@"defaultWorkspace"));
    SEL open = NSSelectorFromString(@"openApplicationWithBundleID:");
    if (workspace && [workspace respondsToSelector:open]) {
        ((BOOL (*)(id, SEL, id))objc_msgSend)(workspace, open, NABundleID);
    }
}

- (UIImage *)bitmapImageFromCGImage:(CGImageRef)cgImage {
    if (!cgImage) return nil;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width < 2 || height < 2) return nil;

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) return nil;

    CGContextRef context = CGBitmapContextCreate(
        NULL, width, height, 8, width * 4, colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    );
    CGColorSpaceRelease(colorSpace);
    if (!context) return nil;

    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGImageRef copy = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    if (!copy) return nil;

    UIImage *image = [UIImage imageWithCGImage:copy scale:UIScreen.mainScreen.scale orientation:UIImageOrientationUp];
    CGImageRelease(copy);
    return image;
}

- (NSDictionary *)analyzePixels:(const uint8_t *)bytes
                        bytesPerRow:(size_t)bytesPerRow
                              width:(size_t)width
                             height:(size_t)height
                      renderChanged:(BOOL)renderChanged {
    if (!bytes || width < 8 || height < 8) {
        return @{
            @"valid": @NO,
            @"render_changed": @(renderChanged),
            @"samples": @0,
            @"dynamic_range": @0,
            @"chroma_samples": @0
        };
    }

    const size_t columns = 18;
    const size_t rows = 30;
    NSUInteger samples = 0;
    NSUInteger chromaSamples = 0;
    NSUInteger blackSamples = 0;
    NSUInteger whiteSamples = 0;
    uint8_t minLuma = 255;
    uint8_t maxLuma = 0;

    for (size_t gy = 0; gy < rows; gy++) {
        size_t y = MIN(height - 1, ((gy * 2 + 1) * height) / (rows * 2));
        const uint8_t *row = bytes + y * bytesPerRow;
        for (size_t gx = 0; gx < columns; gx++) {
            size_t x = MIN(width - 1, ((gx * 2 + 1) * width) / (columns * 2));
            const uint8_t *p = row + x * 4;
            uint8_t b = p[0];
            uint8_t g = p[1];
            uint8_t r = p[2];
            uint8_t high = MAX(r, MAX(g, b));
            uint8_t low = MIN(r, MIN(g, b));
            uint8_t luma = (uint8_t)(((uint32_t)77 * r + (uint32_t)150 * g + (uint32_t)29 * b) >> 8);

            minLuma = MIN(minLuma, luma);
            maxLuma = MAX(maxLuma, luma);
            if ((NSUInteger)(high - low) >= 10) chromaSamples++;
            if (luma <= 6) blackSamples++;
            if (luma >= 249) whiteSamples++;
            samples++;
        }
    }

    NSUInteger dynamicRange = (NSUInteger)(maxLuma - minLuma);
    double blackRatio = samples ? (double)blackSamples / (double)samples : 1.0;
    double whiteRatio = samples ? (double)whiteSamples / (double)samples : 1.0;

    BOOL valid = renderChanged &&
        samples > 0 &&
        dynamicRange >= 10 &&
        blackRatio < 0.985 &&
        whiteRatio < 0.985;

    return @{
        @"valid": @(valid),
        @"render_changed": @(renderChanged),
        @"samples": @(samples),
        @"luma_min": @(minLuma),
        @"luma_max": @(maxLuma),
        @"dynamic_range": @(dynamicRange),
        @"chroma_samples": @(chromaSamples),
        @"black_ratio": @(blackRatio),
        @"white_ratio": @(whiteRatio)
    };
}

- (UIImage *)imageFromPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) return nil;
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixelBuffer);
    if (!surface) return nil;

    if (IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) != KERN_SUCCESS) {
        return nil;
    }

    const uint8_t *src = (const uint8_t *)IOSurfaceGetBaseAddress(surface);
    size_t srcBPR = IOSurfaceGetBytesPerRow(surface);
    size_t width = IOSurfaceGetWidth(surface);
    size_t height = IOSurfaceGetHeight(surface);
    UIImage *image = nil;

    if (src && width > 1 && height > 1) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = colorSpace ? CGBitmapContextCreate(
            NULL,
            width,
            height,
            8,
            width * 4u,
            colorSpace,
            kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little
        ) : NULL;
        if (colorSpace) CGColorSpaceRelease(colorSpace);

        if (context) {
            uint8_t *dst = (uint8_t *)CGBitmapContextGetData(context);
            size_t dstBPR = CGBitmapContextGetBytesPerRow(context);
            if (dst) {
                size_t rowBytes = MIN(width * 4u, srcBPR);
                for (size_t y = 0; y < height; y++) {
                    memcpy(dst + y * dstBPR, src + y * srcBPR, rowBytes);
                }
                CGImageRef cg = CGBitmapContextCreateImage(context);
                if (cg) {
                    CGFloat scale = UIScreen.mainScreen.scale > 0.0 ? UIScreen.mainScreen.scale : 1.0;
                    image = [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp];
                    CGImageRelease(cg);
                }
            }
            CGContextRelease(context);
        }
    }

    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    return image;
}

- (UIImage *)captureDisplayWithSource:(NSString **)sourceOut
                              quality:(NSDictionary **)qualityOut {
    void *qc = dlopen(
        "/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
        RTLD_NOW | RTLD_LOCAL
    );
    NACARenderServerRenderDisplay renderDisplay = (NACARenderServerRenderDisplay)dlsym(
        qc ?: RTLD_DEFAULT,
        "CARenderServerRenderDisplay"
    );

    if (renderDisplay) {
        UIScreen *screen = UIScreen.mainScreen;
        CGRect nativeBounds = screen.nativeBounds;
        size_t width = (size_t)llround(CGRectGetWidth(nativeBounds));
        size_t height = (size_t)llround(CGRectGetHeight(nativeBounds));

        if (width < 320 || height < 640) {
            CGFloat scale = screen.scale > 0.0 ? screen.scale : 1.0;
            width = (size_t)llround(CGRectGetWidth(screen.bounds) * scale);
            height = (size_t)llround(CGRectGetHeight(screen.bounds) * scale);
        }

        NSDictionary *attributes = @{
            (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (__bridge NSString *)kCVPixelBufferMetalCompatibilityKey: @YES,
            (__bridge NSString *)kCVPixelBufferBytesPerRowAlignmentKey: @64
        };

        CVPixelBufferRef pixelBuffer = NULL;
        CVReturn cvResult = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            (__bridge CFDictionaryRef)attributes,
            &pixelBuffer
        );

        IOSurfaceRef surface = pixelBuffer ? CVPixelBufferGetIOSurface(pixelBuffer) : NULL;
        if (cvResult == kCVReturnSuccess && surface) {
            BOOL prepared = NO;
            if (IOSurfaceLock(surface, 0, NULL) == KERN_SUCCESS) {
                void *base = IOSurfaceGetBaseAddress(surface);
                size_t allocSize = IOSurfaceGetAllocSize(surface);
                if (base && allocSize) {
                    memset(base, 0xA5, allocSize);
                    prepared = YES;
                }
                IOSurfaceUnlock(surface, 0, NULL);
            }

            if (prepared && IOSurfaceLock(surface, 0, NULL) == KERN_SUCCESS) {
                renderDisplay(MACH_PORT_NULL, CFSTR("LCD"), surface, 0, 0);
                IOSurfaceUnlock(surface, 0, NULL);
            }

            BOOL renderChanged = NO;
            NSDictionary *quality = nil;
            if (IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) == KERN_SUCCESS) {
                const uint8_t *bytes = (const uint8_t *)IOSurfaceGetBaseAddress(surface);
                size_t length = IOSurfaceGetAllocSize(surface);
                for (size_t offset = 0; bytes && offset < length; offset += 4096) {
                    if (bytes[offset] != 0xA5) {
                        renderChanged = YES;
                        break;
                    }
                }
                quality = [self analyzePixels:bytes
                                 bytesPerRow:IOSurfaceGetBytesPerRow(surface)
                                       width:IOSurfaceGetWidth(surface)
                                      height:IOSurfaceGetHeight(surface)
                               renderChanged:renderChanged];
                IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
            }

            if (qualityOut) *qualityOut = quality ?: @{};
            if ([quality[@"valid"] boolValue]) {
                UIImage *image = [self imageFromPixelBuffer:pixelBuffer];
                if (image) {
                    if (sourceOut) *sourceOut = @"render_server_cvbuffer";
                    CVPixelBufferRelease(pixelBuffer);
                    if (qc) dlclose(qc);
                    return image;
                }
            }
        }

        if (pixelBuffer) CVPixelBufferRelease(pixelBuffer);
    }

    // SpringBoard UIKit fallback. Validate that this fallback is not a blank
    // surface before declaring success.
    NAUICreateScreenUIImage uiCapture = (NAUICreateScreenUIImage)dlsym(
        RTLD_DEFAULT,
        "_UICreateScreenUIImage"
    );
    if (uiCapture) {
        UIImage *image = uiCapture();
        if (image && image.CGImage &&
            CGImageGetWidth(image.CGImage) >= 2 &&
            CGImageGetHeight(image.CGImage) >= 2) {
            size_t width = CGImageGetWidth(image.CGImage);
            size_t height = CGImageGetHeight(image.CGImage);
            CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
            CGContextRef ctx = cs ? CGBitmapContextCreate(
                NULL, width, height, 8, width * 4u, cs,
                kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little
            ) : NULL;
            if (cs) CGColorSpaceRelease(cs);
            if (ctx) {
                CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image.CGImage);
                const uint8_t *bytes = (const uint8_t *)CGBitmapContextGetData(ctx);
                NSDictionary *quality = [self analyzePixels:bytes
                                               bytesPerRow:CGBitmapContextGetBytesPerRow(ctx)
                                                     width:width
                                                    height:height
                                             renderChanged:YES];
                CGContextRelease(ctx);
                if (qualityOut) *qualityOut = quality ?: @{};
                if ([quality[@"valid"] boolValue]) {
                    if (sourceOut) *sourceOut = @"springboard_uicreate_validated";
                    if (qc) dlclose(qc);
                    return image;
                }
            }
        }
    }

    if (qc) dlclose(qc);
    if (sourceOut) *sourceOut = @"unavailable";
    return nil;
}

- (UIImage *)bridgeTransportImage:(UIImage *)image maxDimension:(CGFloat)maxDimension {
    if (!image || maxDimension <= 0) return image;
    CGFloat pixelWidth = image.size.width * image.scale;
    CGFloat pixelHeight = image.size.height * image.scale;
    CGFloat largest = MAX(pixelWidth, pixelHeight);
    if (largest <= maxDimension) return image;

    CGFloat ratio = maxDimension / largest;
    CGSize target = CGSizeMake(MAX(1.0, floor(pixelWidth * ratio)),
                               MAX(1.0, floor(pixelHeight * ratio)));
    UIGraphicsBeginImageContextWithOptions(target, YES, 1.0);
    [image drawInRect:CGRectMake(0, 0, target.width, target.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled ?: image;
}

- (NSDictionary *)directCapturePayload {
    BOOL wasVisible = self.visible;
    BOOL wasSystemHUDVisible = self.systemHUDVisible;
    if (wasVisible || wasSystemHUDVisible) {
        [self setCapturePresentationSuppressed:YES];
        [self.window layoutIfNeeded];
    }

    notify_post("uk.zeshanbarvi.nextagent.capture.begin");

    NSString *source = nil;
    NSDictionary *quality = nil;
    UIImage *image = [self captureDisplayWithSource:&source quality:&quality];

    notify_post("uk.zeshanbarvi.nextagent.capture.end");

    if (wasVisible || wasSystemHUDVisible) {
        [self setCapturePresentationSuppressed:NO];
        if (wasSystemHUDVisible) self.pill.hidden = YES;
    }

    if (!image) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unavailable",
            @"quality": quality ?: @{},
            @"error": @"SpringBoard compositor did not return a validated frame",
            @"transport_version": @"0.7.15-cfmessageport1"
        };
    }

    UIImage *transportImage = [self bridgeTransportImage:image maxDimension:1900.0];
    NSData *jpeg = UIImageJPEGRepresentation(transportImage, 0.86);
    if (jpeg.length > 950 * 1024) {
        jpeg = UIImageJPEGRepresentation(transportImage, 0.70);
    }
    if (jpeg.length > 1200 * 1024) {
        transportImage = [self bridgeTransportImage:image maxDimension:1450.0];
        jpeg = UIImageJPEGRepresentation(transportImage, 0.76);
    }
    if (!jpeg.length) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unknown",
            @"quality": quality ?: @{},
            @"error": @"validated frame could not be encoded for direct IPC",
            @"transport_version": @"0.7.15-cfmessageport1"
        };
    }

    self.lastCaptureSource = source ?: @"unknown";
    return @{
        @"success": @YES,
        @"source": source ?: @"unknown",
        @"quality": quality ?: @{},
        @"format": @"jpeg",
        @"image_base64": [jpeg base64EncodedStringWithOptions:0],
        @"encoded_bytes": @(jpeg.length),
        @"pixel_width": @(lrint(transportImage.size.width * transportImage.scale)),
        @"pixel_height": @(lrint(transportImage.size.height * transportImage.scale)),
        @"native_pixel_width": @(lrint(image.size.width * image.scale)),
        @"native_pixel_height": @(lrint(image.size.height * image.scale)),
        @"transport_version": @"0.7.15-cfmessageport1",
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
}

- (NSDictionary *)directOCRPayloadFast:(BOOL)fast
                              languages:(NSArray<NSString *> *)languages
                               maxItems:(NSInteger)maxItems {
    NSInteger bounded = MAX(1, MIN(200, maxItems));
    NSString *languageKey = languages.count ? [languages componentsJoinedByString:@"|"] : @"";
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (NAOCRCachePayload &&
        (now - NAOCRCacheAt) <= 0.55 &&
        NAOCRCacheFast == fast &&
        NAOCRCacheMaxItems == bounded &&
        [NAOCRCacheLanguageKey ?: @"" isEqualToString:languageKey]) {
        NSMutableDictionary *cached = [NAOCRCachePayload mutableCopy];
        cached[@"cached"] = @YES;
        return cached;
    }

    BOOL wasVisible = self.visible;
    BOOL wasSystemHUDVisible = self.systemHUDVisible;
    if (wasVisible || wasSystemHUDVisible) {
        [self setCapturePresentationSuppressed:YES];
    }

    NSString *source = nil;
    NSDictionary *quality = nil;
    UIImage *image = [self captureDisplayWithSource:&source quality:&quality];

    if (wasVisible || wasSystemHUDVisible) {
        [self setCapturePresentationSuppressed:NO];
        if (wasSystemHUDVisible) self.pill.hidden = YES;
    }
    if (!image || !image.CGImage) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unavailable",
            @"quality": quality ?: @{},
            @"error": @"SpringBoard compositor did not return a validated frame",
            @"transport_version": @"0.7.15-springboard-vision1"
        };
    }

    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = fast ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fast;
    request.minimumTextHeight = 0.005;
    if (languages.count) request.recognitionLanguages = languages;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
    NSError *error = nil;
    BOOL performed = [handler performRequests:@[request] error:&error];
    BOOL fellBackToFast = NO;

    // Accurate text recognition can fail inside SpringBoard on some iOS 16
    // devices with "Error computing NN outputs." Fast recognition is already
    // proven to work on-device, so transparently retry there rather than
    // reporting OCR unavailable.
    if ((!performed || error) && !fast) {
        request = [VNRecognizeTextRequest new];
        request.recognitionLevel = VNRequestTextRecognitionLevelFast;
        request.usesLanguageCorrection = NO;
        request.minimumTextHeight = 0.005;
        if (languages.count) request.recognitionLanguages = languages;

        handler = [[VNImageRequestHandler alloc] initWithCGImage:image.CGImage options:@{}];
        error = nil;
        performed = [handler performRequests:@[request] error:&error];
        fellBackToFast = performed && !error;
    }

    if (!performed || error) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unknown",
            @"quality": quality ?: @{},
            @"error": error.localizedDescription ?: @"Vision OCR request failed",
            @"transport_version": @"0.7.15-springboard-vision1"
        };
    }

    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        if (items.count >= (NSUInteger)bounded) break;
        VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
        if (!candidate.string.length) continue;

        CGRect b = observation.boundingBox;
        CGFloat x = b.origin.x;
        CGFloat y = 1.0 - CGRectGetMaxY(b);
        CGFloat width = b.size.width;
        CGFloat height = b.size.height;

        [items addObject:@{
            @"text": candidate.string,
            @"confidence": @(candidate.confidence),
            @"x": @(x),
            @"y": @(y),
            @"width": @(width),
            @"height": @(height),
            @"center_x": @(x + width * 0.5),
            @"center_y": @(y + height * 0.5)
        }];
    }

    [items sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        double ay = [a[@"y"] doubleValue];
        double by = [b[@"y"] doubleValue];
        if (fabs(ay - by) > 0.015) {
            return ay < by ? NSOrderedAscending : NSOrderedDescending;
        }
        double ax = [a[@"x"] doubleValue];
        double bx = [b[@"x"] doubleValue];
        if (ax == bx) return NSOrderedSame;
        return ax < bx ? NSOrderedAscending : NSOrderedDescending;
    }];

    NSDictionary *payload = @{
        @"success": @(items.count > 0),
        @"source": source ?: @"unknown",
        @"quality": quality ?: @{},
        @"items": items,
        @"count": @(items.count),
        @"coordinate_space": @"normalized top-left; x/y range 0...1",
        @"recognition_level": fellBackToFast ? @"fast_fallback" : (fast ? @"fast" : @"accurate"),
        @"transport_version": @"0.7.15-springboard-vision1",
        @"cached": @NO,
        @"error": items.count ? @"" : @"Vision completed but returned zero text observations"
    };

    if (items.count > 0) {
        NAOCRCachePayload = payload;
        NAOCRCacheAt = [[NSDate date] timeIntervalSince1970];
        NAOCRCacheFast = fast;
        NAOCRCacheLanguageKey = [languageKey copy];
        NAOCRCacheMaxItems = bounded;
    }
    return payload;
}

- (void)captureRequested {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *request = NAReadJSON(NAScreenRequestPath);
        NSString *requestID = [request[@"request_id"] isKindOfClass:NSString.class] ? request[@"request_id"] : @"";
        if (!requestID.length) return;

        BOOL wasVisible = self.visible;
        if (wasVisible) {
            self.pill.hidden = YES;
            [self.window layoutIfNeeded];
        }

        notify_post("uk.zeshanbarvi.nextagent.capture.begin");
        usleep(80 * 1000);

        NSString *source = nil;
        NSDictionary *quality = nil;
        UIImage *image = [self captureDisplayWithSource:&source quality:&quality];

        notify_post("uk.zeshanbarvi.nextagent.capture.end");

        if (wasVisible) {
            self.pill.hidden = NO;
        }

        NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{
            @"request_id": requestID,
            @"success": @(image != nil),
            @"source": source ?: @"unavailable",
            @"quality": quality ?: @{},
            @"timestamp": @([[NSDate date] timeIntervalSince1970])
        }];

        if (image) {
            NAEnsureDirectory(NACaptureDirectory);
            NSString *safeID = [[requestID componentsSeparatedByCharactersInSet:
                [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
            NSString *path = [NACaptureDirectory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"screen-%@.png", safeID]];
            NSData *png = UIImagePNGRepresentation(image);
            BOOL written = png.length && [png writeToFile:path options:NSDataWritingAtomic error:nil];
            if (written) {
                response[@"path"] = path;
                response[@"bytes"] = @(png.length);
                response[@"pixel_width"] = @(lrint(image.size.width * image.scale));
                response[@"pixel_height"] = @(lrint(image.size.height * image.scale));
                response[@"point_width"] = @(image.size.width);
                response[@"point_height"] = @(image.size.height);
                self.lastCaptureSource = source ?: @"unknown";
            } else {
                response[@"success"] = @NO;
                response[@"error"] = @"capture could not be saved";
            }
        } else {
            response[@"error"] = @"SpringBoard display capture returned no image";
        }

        NAWriteJSON(response, NAScreenResponsePath);
        [self writeOverlayStatus];
        notify_post(NAScreenDoneNotification);
    });
}

- (void)refresh {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }

    NSDictionary *state = NAReadJSON(NAProgressPath);
    NSString *mode = [state[@"state"] isKindOfClass:NSString.class] ? state[@"state"] : @"idle";
    NSString *message = [state[@"message"] isKindOfClass:NSString.class] ? state[@"message"] : @"";
    CGFloat progress = [state[@"progress"] respondsToSelector:@selector(doubleValue)] ? [state[@"progress"] doubleValue] : 0;
    BOOL returnToApp = [state[@"return_to_app"] boolValue];
    pid_t agentPID = [state[@"pid"] respondsToSelector:@selector(intValue)] ? [state[@"pid"] intValue] : 0;

    NABroadcastHUDState(state ? mode : @"idle", message, progress);

    if (!state || [mode isEqualToString:@"idle"]) {
        NAReleaseProtection();
        [self hide];
        [self writeOverlayStatus];
        return;
    }

    [self updateSystemHUDMode:mode message:(message.length ? message : @"Next Agent working") progress:progress];
    [self show];
    self.titleLabel.text = message.length ? message : @"Next Agent working";

    if ([mode isEqualToString:@"working"]) {
        NAEnsureProcessProtection(agentPID);
        self.spinner.hidden = NO;
        self.iconLabel.hidden = YES;
        [self.spinner startAnimating];
        self.fill.backgroundColor = [UIColor colorWithRed:0.17 green:0.83 blue:1 alpha:1.0];
        [self setProgress:MAX(0.05, progress) animated:YES];
        [self writeOverlayStatus];
        return;
    }

    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    self.iconLabel.hidden = NO;

    if ([mode isEqualToString:@"complete"]) {
        NAReleaseProtection();
        self.iconLabel.text = @"✓";
        self.iconLabel.textColor = [UIColor colorWithRed:0.26 green:0.96 blue:0.64 alpha:1.0];
        self.fill.backgroundColor = self.iconLabel.textColor;
        self.titleLabel.text = message.length ? message : @"Complete";
        [self updateSystemHUDMode:@"complete" message:(message.length ? message : @"Complete") progress:1.0];
        [self setProgress:1.0 animated:YES];

        if (returnToApp) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self returnToNextAgent];
            });
        }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self hide];
        });
        [self writeOverlayStatus];
        return;
    }

    NAReleaseProtection();
    self.iconLabel.text = [mode isEqualToString:@"stopped"] ? @"■" : @"!";
    self.iconLabel.textColor = [UIColor colorWithRed:1.0 green:0.38 blue:0.47 alpha:1.0];
    self.fill.backgroundColor = self.iconLabel.textColor;
    self.titleLabel.text = message.length ? message : ([mode isEqualToString:@"stopped"] ? @"Stopped" : @"Action failed");
    [self updateSystemHUDMode:mode message:self.titleLabel.text progress:1.0];
    [self setProgress:1.0 animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self hide];
    });
    [self writeOverlayStatus];
}

@end


@interface NASplitTargetWindow : UIWindow
@property(nonatomic,assign) CGRect interactiveRect;
@end

@implementation NASplitTargetWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!CGRectContainsPoint(self.interactiveRect, point)) return nil;
    return [super hitTest:point withEvent:event];
}
@end

@interface NASplitWorkspaceController : NSObject
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIView *primaryHost;
@property(nonatomic,strong) UIView *secondaryHost;
@property(nonatomic,copy) NSString *primaryBundleID;
@property(nonatomic,copy) NSString *secondaryBundleID;
@property(nonatomic,copy) NSString *lastError;
@property(nonatomic,strong) id primaryUpdater;
@property(nonatomic,strong) id secondaryUpdater;
@property(nonatomic,strong) NSTimer *foregroundTimer;
@property(nonatomic,assign) BOOL opening;
@property(nonatomic,copy) NSDictionary *lastOpenResult;
@property(nonatomic,copy) NSString *lastSceneSource;
@property(nonatomic,assign) NSInteger lastSceneAttempts;
@property(nonatomic,assign) NSInteger lastLaunchResult;
+ (instancetype)shared;
- (NSDictionary *)beginOpenPrimary:(NSString *)primary secondary:(NSString *)secondary;
- (NSDictionary *)openPrimary:(NSString *)primary secondary:(NSString *)secondary;
- (NSDictionary *)status;
- (NSDictionary *)close;
@end

@implementation NASplitWorkspaceController

+ (instancetype)shared {
    static NASplitWorkspaceController *value;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ value = [NASplitWorkspaceController new]; });
    return value;
}

- (UIWindowScene *)springBoardWindowScene {
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *key = nil;
    if ([app respondsToSelector:@selector(keyWindow)]) {
        key = ((UIWindow *(*)(id, SEL))objc_msgSend)(app, @selector(keyWindow));
    }
    if (key.windowScene) return key.windowScene;

    UIWindowScene *fallback = nil;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)scene;
        if (!fallback) fallback = ws;
        if (scene.activationState == UISceneActivationStateForegroundActive) return ws;
    }
    return fallback;
}

- (BOOL)launchBundleID:(NSString *)bundleID suspended:(BOOL)suspended {
    if (!bundleID.length) return NO;
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    typedef int (*LaunchFn)(CFStringRef, BOOL);
    LaunchFn launch = (LaunchFn)dlsym(handle ?: RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");
    if (!launch) {
        self.lastLaunchResult = -999;
        return NO;
    }
    int result = launch((__bridge CFStringRef)bundleID, suspended);
    self.lastLaunchResult = result;
    return result != 0;
}

- (BOOL)launchSuspended:(NSString *)bundleID {
    return [self launchBundleID:bundleID suspended:YES];
}

- (id)applicationForBundleID:(NSString *)bundleID {
    Class cls = NSClassFromString(@"SBApplicationController");
    if (!cls) return nil;
    id controller = nil;
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if ([cls respondsToSelector:shared]) {
        controller = ((id (*)(id, SEL))objc_msgSend)((id)cls, shared);
    }
    if (!controller) return nil;

    for (NSString *name in @[@"applicationWithBundleIdentifier:", @"applicationWithDisplayIdentifier:"]) {
        SEL sel = NSSelectorFromString(name);
        if ([controller respondsToSelector:sel]) {
            id app = ((id (*)(id, SEL, id))objc_msgSend)(controller, sel, bundleID);
            if (app) return app;
        }
    }
    return nil;
}

- (id)sceneForApplication:(id)application {
    if (!application) return nil;
    for (NSString *name in @[@"mainScene", @"defaultScene", @"defaultUIScene"]) {
        SEL sel = NSSelectorFromString(name);
        if ([application respondsToSelector:sel]) {
            id scene = ((id (*)(id, SEL))objc_msgSend)(application, sel);
            if (scene) return scene;
        }
    }
    SEL scenesSel = NSSelectorFromString(@"scenes");
    if ([application respondsToSelector:scenesSel]) {
        id scenes = ((id (*)(id, SEL))objc_msgSend)(application, scenesSel);
        if ([scenes respondsToSelector:@selector(count)] &&
            [scenes respondsToSelector:@selector(objectAtIndex:)] &&
            [scenes count] > 0) {
            return [scenes objectAtIndex:0];
        }
    }
    return nil;
}

- (id)mainDisplaySceneManager {
    Class cls = NSClassFromString(@"SBSceneManagerCoordinator");
    if (!cls) return nil;
    SEL mainSel = NSSelectorFromString(@"mainDisplaySceneManager");
    if (![cls respondsToSelector:mainSel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)((id)cls, mainSel);
}

- (NSString *)bundleIDForScene:(id)scene manager:(id)manager {
    if (!scene) return nil;

    if (manager) {
        SEL handleSel = NSSelectorFromString(@"existingSceneHandleForScene:");
        if ([manager respondsToSelector:handleSel]) {
            id handle = ((id (*)(id, SEL, id))objc_msgSend)(manager, handleSel, scene);
            if (handle) {
                SEL appSel = NSSelectorFromString(@"application");
                id app = [handle respondsToSelector:appSel]
                    ? ((id (*)(id, SEL))objc_msgSend)(handle, appSel)
                    : nil;
                for (NSString *selName in @[@"bundleIdentifier", @"displayIdentifier"]) {
                    SEL sel = NSSelectorFromString(selName);
                    if ([app respondsToSelector:sel]) {
                        id value = ((id (*)(id, SEL))objc_msgSend)(app, sel);
                        if ([value isKindOfClass:NSString.class] && [value length]) return value;
                    }
                }
            }
        }
    }

    SEL procSel = NSSelectorFromString(@"_clientProcess");
    if ([scene respondsToSelector:procSel]) {
        id proc = ((id (*)(id, SEL))objc_msgSend)(scene, procSel);
        SEL bidSel = NSSelectorFromString(@"bundleIdentifier");
        if ([proc respondsToSelector:bidSel]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(proc, bidSel);
            if ([value isKindOfClass:NSString.class] && [value length]) return value;
        }
    }

    SEL identSel = NSSelectorFromString(@"identifier");
    if ([scene respondsToSelector:identSel]) {
        id ident = ((id (*)(id, SEL))objc_msgSend)(scene, identSel);
        if ([ident isKindOfClass:NSString.class]) {
            NSString *prefix = @"sceneID:";
            if ([ident hasPrefix:prefix]) {
                NSString *tail = [ident substringFromIndex:prefix.length];
                NSRange dash = [tail rangeOfString:@"-"];
                if (dash.location != NSNotFound && dash.location > 0) {
                    return [tail substringToIndex:dash.location];
                }
            }
        }
    }
    return nil;
}

- (id)sceneForBundleIDFromSceneManager:(NSString *)bundleID {
    id manager = [self mainDisplaySceneManager];
    if (!manager || !bundleID.length) return nil;

    SEL allScenesSel = NSSelectorFromString(@"allScenes");
    if (![manager respondsToSelector:allScenesSel]) return nil;
    id scenes = ((id (*)(id, SEL))objc_msgSend)(manager, allScenesSel);
    NSArray *array = nil;
    if ([scenes respondsToSelector:@selector(allObjects)]) {
        array = [scenes allObjects];
    } else if ([scenes isKindOfClass:NSArray.class]) {
        array = scenes;
    }
    if (![array isKindOfClass:NSArray.class]) return nil;

    for (id scene in array) {
        NSString *candidate = [self bundleIDForScene:scene manager:manager];
        if ([candidate isEqualToString:bundleID]) return scene;
    }
    return nil;
}

- (id)resolveSceneForBundleID:(NSString *)bundleID source:(NSString **)source {
    id app = [self applicationForBundleID:bundleID];
    id scene = [self sceneForApplication:app];
    if (scene) {
        if (source) *source = @"SBApplicationController";
        return scene;
    }

    scene = [self sceneForBundleIDFromSceneManager:bundleID];
    if (scene) {
        if (source) *source = @"SBSceneManagerCoordinator";
        return scene;
    }
    return nil;
}

- (id)waitForSceneBundleID:(NSString *)bundleID {
    self.lastSceneSource = @"";
    self.lastSceneAttempts = 0;

    NSString *source = nil;
    id scene = [self resolveSceneForBundleID:bundleID source:&source];
    if (scene) {
        self.lastSceneSource = source ?: @"preexisting";
        return scene;
    }

    BOOL suspendedLaunch = [self launchSuspended:bundleID];

    // iOS 16 can take materially longer than the old ~0.8s budget to publish
    // the FBScene, especially for Preferences/Settings. Poll both the
    // SBApplicationController and SBSceneManagerCoordinator sources.
    for (NSUInteger attempt = 0; attempt < 30; attempt++) {
        self.lastSceneAttempts = (NSInteger)attempt + 1;
        source = nil;
        scene = [self resolveSceneForBundleID:bundleID source:&source];
        if (scene) {
            self.lastSceneSource = source ?: @"after_suspended_launch";
            return scene;
        }
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.10, true);
    }

    // If suspended launch did not publish a hostable scene, briefly request
    // a normal foreground launch and immediately capture the resulting scene.
    // This is a last-resort compatibility path for system apps such as Settings.
    if (!suspendedLaunch || !scene) {
        [self launchBundleID:bundleID suspended:NO];
        for (NSUInteger attempt = 0; attempt < 20; attempt++) {
            self.lastSceneAttempts = 30 + (NSInteger)attempt + 1;
            source = nil;
            scene = [self resolveSceneForBundleID:bundleID source:&source];
            if (scene) {
                self.lastSceneSource = [NSString stringWithFormat:@"%@+foreground_fallback",
                    source ?: @"scene"];
                return scene;
            }
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.10, true);
        }
    }

    self.lastSceneSource = @"none";
    return nil;
}

- (UIView *)hostViewForScene:(id)scene frame:(CGRect)frame label:(NSString *)label {
    if (!scene) return nil;
    Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    if (!hostClass) {
        self.lastError = @"_UISceneLayerHostContainerView is unavailable";
        return nil;
    }

    id allocated = ((id (*)(id, SEL))objc_msgSend)((id)hostClass, @selector(alloc));
    id host = nil;

    SEL two = NSSelectorFromString(@"initWithScene:debugDescription:");
    if ([allocated respondsToSelector:two]) {
        host = ((id (*)(id, SEL, id, id))objc_msgSend)(
            allocated, two, scene, label ?: @"Next Agent split workspace"
        );
    }
    if (!host) {
        SEL one = NSSelectorFromString(@"initWithScene:");
        if ([allocated respondsToSelector:one]) {
            host = ((id (*)(id, SEL, id))objc_msgSend)(allocated, one, scene);
        }
    }
    if (!host || ![host isKindOfClass:UIView.class]) {
        self.lastError = @"scene host initializer failed";
        return nil;
    }

    UIView *view = (UIView *)host;
    view.frame = frame;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.clipsToBounds = YES;
    view.userInteractionEnabled = YES;
    view.backgroundColor = UIColor.blackColor;
    return view;
}

- (id)foregroundUpdaterForScene:(id)scene identifier:(NSString *)identifier {
    Class updaterClass = NSClassFromString(@"SBSceneSettingsUpdater");
    if (!scene || !updaterClass) return nil;

    id allocated = ((id (*)(id, SEL))objc_msgSend)((id)updaterClass, @selector(alloc));
    SEL initSel = NSSelectorFromString(@"initWithScene:persistentIdentifier:level:updatesGeometry:");
    if (![allocated respondsToSelector:initSel]) return nil;

    NSString *persistent = [NSString stringWithFormat:@"nextagent.%@.%@",
                            identifier ?: @"scene",
                            NSUUID.UUID.UUIDString];
    double level = 1.0;
    BOOL updatesGeometry = YES;
    NSMethodSignature *sig = [allocated methodSignatureForSelector:initSel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:allocated];
    [inv setSelector:initSel];
    id sceneArg = scene;
    id persistentArg = persistent;
    [inv setArgument:&sceneArg atIndex:2];
    [inv setArgument:&persistentArg atIndex:3];
    [inv setArgument:&level atIndex:4];
    [inv setArgument:&updatesGeometry atIndex:5];
    [inv invoke];

    __unsafe_unretained id result = nil;
    [inv getReturnValue:&result];
    return result;
}

- (void)markSceneForeground:(id)scene updater:(id)updater {
    if (!scene || !updater) return;

    SEL enhanced = NSSelectorFromString(@"setEnhancedWindowingModeEnabled:");
    if ([updater respondsToSelector:enhanced]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(updater, enhanced, YES);
    }

    SEL active = NSSelectorFromString(@"setActive:withTransitionContext:");
    if ([updater respondsToSelector:active]) {
        ((void (*)(id, SEL, BOOL, id))objc_msgSend)(updater, active, YES, nil);
    }

    SEL foreground = NSSelectorFromString(@"setForeground:");
    if ([updater respondsToSelector:foreground]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(updater, foreground, YES);
    }
}

- (void)refreshForegroundScenes {
    SEL foreground = NSSelectorFromString(@"setForeground:");
    if ([self.secondaryUpdater respondsToSelector:foreground]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self.secondaryUpdater, foreground, YES);
    }
}

- (NSDictionary *)capabilities {
    Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    Class appControllerClass = NSClassFromString(@"SBApplicationController");
    Class updaterClass = NSClassFromString(@"SBSceneSettingsUpdater");
    Class sceneCoordinatorClass = NSClassFromString(@"SBSceneManagerCoordinator");

    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    void *launchSymbol = dlsym(handle ?: RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");

    // v0.7.9 no longer requires SpringBoard to obtain/re-host the Next Agent
    // scene. Next Agent remains the actual foreground application; SpringBoard
    // hosts only the target scene in the bottom half.
    BOOL success = hostClass && appControllerClass && updaterClass && sceneCoordinatorClass && launchSymbol;
    return @{
        @"success": @(success),
        @"host_class_available": @(hostClass != Nil),
        @"application_controller_available": @(appControllerClass != Nil),
        @"scene_settings_updater_available": @(updaterClass != Nil),
        @"scene_manager_coordinator_available": @(sceneCoordinatorClass != Nil),
        @"launch_symbol_available": @(launchSymbol != NULL),
        @"nextagent_scene_required": @NO,
        @"mode": @"target_scene_overlay_50_50",
        @"bridge_version": @"0.7.15",
        @"transport_version": @"0.7.15-springboard-vision1"
    };
}

- (NSDictionary *)beginOpenPrimary:(NSString *)primary secondary:(NSString *)secondary {
    if (!secondary.length) {
        return @{@"success": @NO, @"error": @"missing target split-workspace bundle ID"};
    }

    self.opening = YES;
    self.lastError = nil;
    self.lastOpenResult = nil;
    NSString *primaryCopy = [primary copy] ?: @"uk.zeshanbarvi.nextagent";
    NSString *secondaryCopy = [secondary copy];

    // Return from CFMessagePort immediately. Scene launch/hosting can take
    // longer than the client's receive timeout on iOS 16.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *result = [self openPrimary:primaryCopy secondary:secondaryCopy];
        self.lastOpenResult = result;
        self.opening = NO;
        if (![result[@"success"] boolValue]) {
            self.lastError = [result[@"error"] isKindOfClass:NSString.class]
                ? result[@"error"] : @"split workspace creation failed";
        }
    });

    return @{
        @"success": @YES,
        @"accepted": @YES,
        @"opening": @YES,
        @"secondary_bundle_id": secondaryCopy,
        @"bridge_version": @"0.7.15"
    };
}

- (NSDictionary *)openPrimary:(NSString *)primary secondary:(NSString *)secondary {
    if (!secondary.length) {
        return @{@"success": @NO, @"error": @"missing target split-workspace bundle ID"};
    }

    [self close];
    self.lastError = nil;

    UIWindowScene *windowScene = [self springBoardWindowScene];
    if (!windowScene) {
        return @{@"success": @NO, @"error": @"SpringBoard UIWindowScene is unavailable"};
    }

    id secondaryScene = [self waitForSceneBundleID:secondary];
    if (!secondaryScene) {
        return @{
            @"success": @NO,
            @"error": @"target application scene was unavailable",
            @"secondary_scene": @NO,
            @"scene_source": self.lastSceneSource ?: @"",
            @"scene_attempts": @(self.lastSceneAttempts),
            @"launch_result": @(self.lastLaunchResult)
        };
    }

    self.secondaryUpdater = [self foregroundUpdaterForScene:secondaryScene identifier:@"secondary"];
    [self markSceneForeground:secondaryScene updater:self.secondaryUpdater];

    [self.foregroundTimer invalidate];
    self.foregroundTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                            target:self
                                                          selector:@selector(refreshForegroundScenes)
                                                          userInfo:nil
                                                           repeats:YES];

    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat divider = 2.0;
    CGFloat splitY = floor(bounds.size.height * 0.50);
    CGRect bottomFrame = CGRectMake(
        0,
        splitY + divider,
        bounds.size.width,
        MAX(1.0, bounds.size.height - splitY - divider)
    );

    NASplitTargetWindow *window = [[NASplitTargetWindow alloc] initWithWindowScene:windowScene];
    window.frame = bounds;
    window.windowLevel = 999990.0;
    window.backgroundColor = UIColor.clearColor;
    window.opaque = NO;
    window.userInteractionEnabled = YES;
    window.interactiveRect = bottomFrame;

    UIViewController *controller = [UIViewController new];
    controller.view.frame = bounds;
    controller.view.backgroundColor = UIColor.clearColor;
    controller.view.userInteractionEnabled = YES;
    window.rootViewController = controller;

    UIView *bottom = [self hostViewForScene:secondaryScene
                                      frame:bottomFrame
                                     label:@"Next Agent target scene"];
    if (!bottom) {
        window.hidden = YES;
        return @{
            @"success": @NO,
            @"error": self.lastError ?: @"could not create target scene host view"
        };
    }

    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, splitY, bounds.size.width, divider)];
    separator.backgroundColor = [UIColor colorWithWhite:0.22 alpha:0.92];
    separator.userInteractionEnabled = NO;

    // Optional small label so the user can see which half belongs to the target.
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12, splitY - 24, bounds.size.width - 24, 20)];
    label.text = [NSString stringWithFormat:@"Next Agent • %@", secondary];
    label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    label.backgroundColor = UIColor.clearColor;
    label.userInteractionEnabled = NO;

    [controller.view addSubview:bottom];
    [controller.view addSubview:separator];
    [controller.view addSubview:label];

    window.hidden = NO;
    window.alpha = 1.0;

    self.window = window;
    self.primaryHost = nil;
    self.secondaryHost = bottom;
    self.primaryBundleID = primary ?: @"uk.zeshanbarvi.nextagent";
    self.secondaryBundleID = secondary;

    return @{
        @"success": @YES,
        @"mode": @"target_scene_overlay_50_50",
        @"layout": @"nextagent_top_target_bottom",
        @"primary_bundle_id": self.primaryBundleID,
        @"secondary_bundle_id": secondary,
        @"primary_host_required": @NO,
        @"secondary_host_ready": @YES,
        @"secondary_rect": @{
            @"x": @0,
            @"y": @((splitY + divider) / bounds.size.height),
            @"width": @1,
            @"height": @((bounds.size.height - splitY - divider) / bounds.size.height)
        },
        @"window_level": @(window.windowLevel),
        @"interactive": @YES,
        @"scene_source": self.lastSceneSource ?: @"",
        @"scene_attempts": @(self.lastSceneAttempts),
        @"launch_result": @(self.lastLaunchResult),
        @"bridge_version": @"0.7.15"
    };
}

- (NSDictionary *)status {
    BOOL active = self.window != nil && !self.window.hidden && self.secondaryHost != nil;
    NSMutableDictionary *status = [@{
        @"success": @YES,
        @"active": @(active),
        @"opening": @(self.opening),
        @"primary_bundle_id": self.primaryBundleID ?: @"",
        @"secondary_bundle_id": self.secondaryBundleID ?: @"",
        @"primary_host_ready": @YES,
        @"primary_host_required": @NO,
        @"secondary_host_ready": @(self.secondaryHost != nil),
        @"last_error": self.lastError ?: @"",
        @"scene_source": self.lastSceneSource ?: @"",
        @"scene_attempts": @(self.lastSceneAttempts),
        @"launch_result": @(self.lastLaunchResult),
        @"mode": @"target_scene_overlay_50_50",
        @"bridge_version": @"0.7.15"
    } mutableCopy];
    if (self.lastOpenResult) status[@"last_open_result"] = self.lastOpenResult;
    return status;
}

- (NSDictionary *)close {
    if (self.window) {
        self.window.hidden = YES;
        self.window.rootViewController = nil;
    }
    [self.foregroundTimer invalidate];
    self.foregroundTimer = nil;
    self.primaryUpdater = nil;
    self.secondaryUpdater = nil;
    self.window = nil;
    self.primaryHost = nil;
    self.secondaryHost = nil;
    self.primaryBundleID = nil;
    self.secondaryBundleID = nil;
    self.opening = NO;
    self.lastOpenResult = nil;
    return @{@"success": @YES, @"active": @NO, @"bridge_version": @"0.7.15"};
}

@end

static CFMessagePortRef NABridgePort = NULL;
static CFRunLoopSourceRef NABridgeSource = NULL;
static CFStringRef const NABridgeServiceName =
    CFSTR("uk.zeshanbarvi.nextagent.bridge.v0715");

static CFDataRef NABridgeReply(NSDictionary *dictionary) {
    NSDictionary *value = dictionary ?: @{@"success": @NO, @"error": @"empty bridge reply"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
    if (!data) {
        data = [NSJSONSerialization dataWithJSONObject:@{
            @"success": @NO,
            @"error": @"could not encode SpringBoard bridge reply"
        } options:0 error:nil];
    }
    return data ? CFRetain((__bridge CFDataRef)data) : NULL;
}

static CFDataRef NABridgeCallback(
    CFMessagePortRef local,
    SInt32 msgid,
    CFDataRef data,
    void *info
) {
    (void)local;
    (void)msgid;
    (void)info;
    @autoreleasepool {
        NSData *requestData = (__bridge NSData *)data;
        id decoded = requestData.length
            ? [NSJSONSerialization JSONObjectWithData:requestData options:0 error:nil]
            : nil;
        if (![decoded isKindOfClass:NSDictionary.class]) {
            return NABridgeReply(@{@"success": @NO, @"error": @"malformed bridge request"});
        }

        NSDictionary *request = (NSDictionary *)decoded;
        NSString *action = [request[@"action"] isKindOfClass:NSString.class]
            ? request[@"action"] : @"";

        if ([action isEqualToString:@"capture"]) {
            return NABridgeReply([[NAProgressOverlay shared] directCapturePayload]);
        }
        if ([action isEqualToString:@"ocr"]) {
            BOOL fast = [request[@"fast"] boolValue];
            NSArray<NSString *> *languages = [request[@"languages"] isKindOfClass:NSArray.class]
                ? request[@"languages"] : @[];
            NSInteger maxItems = [request[@"max_items"] respondsToSelector:@selector(integerValue)]
                ? [request[@"max_items"] integerValue] : 160;
            return NABridgeReply([[NAProgressOverlay shared]
                directOCRPayloadFast:fast
                           languages:languages
                            maxItems:maxItems]);
        }
        if ([action isEqualToString:@"split_capabilities"]) {
            return NABridgeReply([[NASplitWorkspaceController shared] capabilities]);
        }
        if ([action isEqualToString:@"split_open"]) {
            NSString *primary = [request[@"primary_bundle_id"] isKindOfClass:NSString.class]
                ? request[@"primary_bundle_id"] : @"";
            NSString *secondary = [request[@"secondary_bundle_id"] isKindOfClass:NSString.class]
                ? request[@"secondary_bundle_id"] : @"";
            return NABridgeReply([[NASplitWorkspaceController shared]
                beginOpenPrimary:primary secondary:secondary]);
        }
        if ([action isEqualToString:@"split_status"]) {
            return NABridgeReply([[NASplitWorkspaceController shared] status]);
        }
        if ([action isEqualToString:@"split_close"]) {
            return NABridgeReply([[NASplitWorkspaceController shared] close]);
        }
        if ([action isEqualToString:@"hid_status"]) {
            return NABridgeReply(NAHIDStatusPayload());
        }
        if ([action isEqualToString:@"hud_status"]) {
            return NABridgeReply([[NAProgressOverlay shared] hudStatusPayload]);
        }
        if ([action isEqualToString:@"hid_tap"]) {
            return NABridgeReply(NAHIDTapPayload(
                [request[@"x"] doubleValue],
                [request[@"y"] doubleValue],
                [request[@"count"] integerValue]
            ));
        }
        if ([action isEqualToString:@"hid_long_press"]) {
            return NABridgeReply(NAHIDLongPressPayload(
                [request[@"x"] doubleValue],
                [request[@"y"] doubleValue],
                [request[@"duration"] doubleValue]
            ));
        }
        if ([action isEqualToString:@"hid_swipe"]) {
            return NABridgeReply(NAHIDSwipePayload(
                [request[@"x1"] doubleValue],
                [request[@"y1"] doubleValue],
                [request[@"x2"] doubleValue],
                [request[@"y2"] doubleValue],
                [request[@"duration"] doubleValue]
            ));
        }
        if ([action isEqualToString:@"hid_key"]) {
            NSString *key = [request[@"key"] isKindOfClass:NSString.class] ? request[@"key"] : @"";
            return NABridgeReply(NAHIDKeyPayload(key));
        }
        if ([action isEqualToString:@"hid_paste"]) {
            return NABridgeReply(NAHIDPastePayload());
        }
        if ([action isEqualToString:@"hid_type_text"]) {
            NSString *text = [request[@"text"] isKindOfClass:NSString.class] ? request[@"text"] : @"";
            return NABridgeReply(NAHIDTypeTextPayload(text));
        }
        if ([action isEqualToString:@"ping"]) {
            return NABridgeReply(@{
                @"success": @YES,
                @"version": @"0.7.15",
                @"transport": @"cfmessageport",
                @"capture": @"in_memory",
                @"ocr": @"springboard_vision",
                @"split_workspace": @"target_scene_overlay_50_50_async_scene_manager",
                @"hid": @"springboard_iohid_v0715",
                @"hud": @"native_sbhud_v0715"
            });
        }

        return NABridgeReply(@{@"success": @NO, @"error": @"unsupported bridge action"});
    }
}

static void NAStartDirectBridge(void) {
    if (NABridgePort) return;

    CFMessagePortContext context = {0, NULL, NULL, NULL, NULL};
    Boolean shouldFreeInfo = false;
    NABridgePort = CFMessagePortCreateLocal(
        kCFAllocatorDefault,
        NABridgeServiceName,
        NABridgeCallback,
        &context,
        &shouldFreeInfo
    );
    if (!NABridgePort) return;

    NABridgeSource = CFMessagePortCreateRunLoopSource(
        kCFAllocatorDefault,
        NABridgePort,
        0
    );
    if (!NABridgeSource) return;

    CFRunLoopAddSource(
        CFRunLoopGetMain(),
        NABridgeSource,
        kCFRunLoopCommonModes
    );
}

__attribute__((constructor))
static void NAOverlayInit(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            NAStartDirectBridge();
            NAHIDLoad();
            if (NAHUDStateToken < 0) {
                notify_register_check(NAHUDStateNotification, &NAHUDStateToken);
            }
            NAProgressOverlay *overlay = [NAProgressOverlay shared];
            [overlay ensureUI];
            [overlay startPermanentPolling];
            [overlay writeOverlayStatus];
            [overlay refresh];

            int progressToken = 0;
            notify_register_dispatch(
                NAProgressNotification,
                &progressToken,
                dispatch_get_main_queue(),
                ^(__unused int token) {
                    [[NAProgressOverlay shared] refresh];
                }
            );

            int captureToken = 0;
            notify_register_dispatch(
                NAScreenRequestNotification,
                &captureToken,
                dispatch_get_main_queue(),
                ^(__unused int token) {
                    [[NAProgressOverlay shared] captureRequested];
                }
            );
        });
    }
}
