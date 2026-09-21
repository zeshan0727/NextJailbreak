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

typedef void (*NACARenderServerRenderDisplay)(mach_port_t, CFStringRef, IOSurfaceRef, int32_t, int32_t);
typedef UIImage * NS_RETURNS_RETAINED (*NAUICreateScreenUIImage)(void);

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
}

static BOOL NAAcquireRBSProtection(pid_t pid) {
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/RunningBoardServices.framework/RunningBoardServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    if (!handle) {
        NAProtectionDetail = @"RunningBoardServices unavailable";
        return NO;
    }

    Class targetClass = NSClassFromString(@"RBSTarget");
    Class legacyClass = NSClassFromString(@"RBSLegacyAttribute");
    Class assertionClass = NSClassFromString(@"RBSAssertion");
    if (!targetClass || !legacyClass || !assertionClass) {
        NAProtectionDetail = @"RBS classes unavailable";
        return NO;
    }

    id target = nil;
    SEL targetWithPid = NSSelectorFromString(@"targetWithPid:");
    if ([targetClass respondsToSelector:targetWithPid]) {
        target = ((id (*)(id, SEL, int))objc_msgSend)((id)targetClass, targetWithPid, pid);
    }
    if (!target) {
        NAProtectionDetail = @"RBSTarget could not be created";
        return NO;
    }

    // Same legacy assertion flags used by established jailbreak backgrounders:
    // prevent suspend, prevent task throttle, foreground resource priority and UI throttle.
    const unsigned int flags = (1u << 0) | (1u << 1) | (1u << 3) | (1u << 5);
    SEL attrSel = NSSelectorFromString(@"attributeWithReason:flags:");
    if (![legacyClass respondsToSelector:attrSel]) {
        NAProtectionDetail = @"RBSLegacyAttribute selector unavailable";
        return NO;
    }
    typedef id (*AttrFn)(id, SEL, unsigned int, unsigned int);
    id legacy = ((AttrFn)objc_msgSend)((id)legacyClass, attrSel, 7u, flags);
    if (!legacy) {
        NAProtectionDetail = @"RBSLegacyAttribute creation failed";
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
        return NO;
    }

    NARBSAssertion = assertion;
    NAProtectedPID = pid;
    NAProtectionMethod = @"RBSAssertion";
    NAProtectionDetail = @"SpringBoard-held RBS assertion active";
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
    SEL six = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:acquire:");
    if ([object respondsToSelector:six]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id, id, BOOL);
        assertion = ((Fn)objc_msgSend)(
            object, six, pid, flags, 10005u,
            @"NextAgentSpringBoardFallback", nil, YES
        );
    }

    if (!assertion || !NAObjectValid(assertion)) {
        NAProtectionDetail = @"BKS fallback could not be acquired";
        return NO;
    }

    NABKSAssertion = assertion;
    NAProtectedPID = pid;
    NAProtectionMethod = @"BKSProcessAssertion";
    NAProtectionDetail = @"SpringBoard-held BKS fallback active";
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
+ (instancetype)shared;
- (void)refresh;
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
    NSDictionary *state = @{
        @"loaded": @YES,
        @"overlay_generation": @"0.7.9",
        @"pid": @(getpid()),
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"window_ready": @(self.window != nil),
        @"window_level": @(self.window ? self.window.windowLevel : 0.0),
        @"visible": @(self.visible),
        @"protected_pid": @(NAProtectedPID),
        @"assertion_valid": @((NARBSAssertion && NAObjectValid(NARBSAssertion)) ||
                              (NABKSAssertion && NAObjectValid(NABKSAssertion))),
        @"protection_method": NAProtectionMethod ?: @"none",
        @"protection_detail": NAProtectionDetail ?: @"",
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
    self.window.hidden = NO;
    self.window.alpha = 1.0;
    self.pill.hidden = NO;
    self.visible = YES;
    [self writeOverlayStatus];
}

- (void)hide {
    if (!self.window) return;
    self.window.hidden = YES;
    self.visible = NO;
    [self writeOverlayStatus];
}

- (void)startPermanentPolling {
    if (self.pollTimer) return;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.40
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
    if (wasVisible) {
        self.pill.hidden = YES;
        [self.window layoutIfNeeded];
    }

    notify_post("uk.zeshanbarvi.nextagent.capture.begin");

    NSString *source = nil;
    NSDictionary *quality = nil;
    UIImage *image = [self captureDisplayWithSource:&source quality:&quality];

    notify_post("uk.zeshanbarvi.nextagent.capture.end");

    if (wasVisible) self.pill.hidden = NO;

    if (!image) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unavailable",
            @"quality": quality ?: @{},
            @"error": @"SpringBoard compositor did not return a validated frame",
            @"transport_version": @"0.7.9-cfmessageport1"
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
            @"transport_version": @"0.7.9-cfmessageport1"
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
        @"transport_version": @"0.7.9-cfmessageport1",
        @"timestamp": @([[NSDate date] timeIntervalSince1970])
    };
}

- (NSDictionary *)directOCRPayloadFast:(BOOL)fast
                              languages:(NSArray<NSString *> *)languages
                               maxItems:(NSInteger)maxItems {
    NSString *source = nil;
    NSDictionary *quality = nil;
    UIImage *image = [self captureDisplayWithSource:&source quality:&quality];
    if (!image || !image.CGImage) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unavailable",
            @"quality": quality ?: @{},
            @"error": @"SpringBoard compositor did not return a validated frame",
            @"transport_version": @"0.7.9-springboard-vision1"
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
    if (!performed || error) {
        return @{
            @"success": @NO,
            @"source": source ?: @"unknown",
            @"quality": quality ?: @{},
            @"error": error.localizedDescription ?: @"Vision OCR request failed",
            @"transport_version": @"0.7.9-springboard-vision1"
        };
    }

    NSInteger bounded = MAX(1, MIN(200, maxItems));
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

    return @{
        @"success": @(items.count > 0),
        @"source": source ?: @"unknown",
        @"quality": quality ?: @{},
        @"items": items,
        @"count": @(items.count),
        @"coordinate_space": @"normalized top-left; x/y range 0...1",
        @"recognition_level": fast ? @"fast" : @"accurate",
        @"transport_version": @"0.7.9-springboard-vision1",
        @"error": items.count ? @"" : @"Vision completed but returned zero text observations"
    };
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
    [self setProgress:1.0 animated:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self hide];
    });
    [self writeOverlayStatus];
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
+ (instancetype)shared;
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

- (BOOL)launchSuspended:(NSString *)bundleID {
    if (!bundleID.length) return NO;
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    typedef int (*LaunchFn)(CFStringRef, BOOL);
    LaunchFn launch = (LaunchFn)dlsym(handle ?: RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");
    if (!launch) return NO;
    (void)launch((__bridge CFStringRef)bundleID, YES);
    return YES;
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

- (id)waitForSceneBundleID:(NSString *)bundleID {
    [self launchSuspended:bundleID];
    for (NSUInteger attempt = 0; attempt < 18; attempt++) {
        id app = [self applicationForBundleID:bundleID];
        id scene = [self sceneForApplication:app];
        if (scene) return scene;
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.045, true);
    }
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
    [self markSceneForeground:nil updater:nil];
    SEL foreground = NSSelectorFromString(@"setForeground:");
    if ([self.primaryUpdater respondsToSelector:foreground]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self.primaryUpdater, foreground, YES);
    }
    if ([self.secondaryUpdater respondsToSelector:foreground]) {
        ((void (*)(id, SEL, BOOL))objc_msgSend)(self.secondaryUpdater, foreground, YES);
    }
}

- (NSDictionary *)capabilities {
    Class hostClass = NSClassFromString(@"_UISceneLayerHostContainerView");
    Class appControllerClass = NSClassFromString(@"SBApplicationController");
    Class updaterClass = NSClassFromString(@"SBSceneSettingsUpdater");

    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    void *launchSymbol = dlsym(handle ?: RTLD_DEFAULT, "SBSLaunchApplicationWithIdentifier");

    id app = [self applicationForBundleID:@"uk.zeshanbarvi.nextagent"];
    id scene = [self sceneForApplication:app];
    UIView *probe = nil;
    if (scene && hostClass) {
        probe = [self hostViewForScene:scene
                                frame:CGRectMake(0, 0, 24, 24)
                                label:@"Next Agent split capability probe"];
        [probe removeFromSuperview];
    }

    BOOL hostReady = probe != nil;
    BOOL success = hostClass && appControllerClass && updaterClass && launchSymbol && scene && hostReady;
    return @{
        @"success": @(success),
        @"host_class_available": @(hostClass != Nil),
        @"application_controller_available": @(appControllerClass != Nil),
        @"scene_settings_updater_available": @(updaterClass != Nil),
        @"launch_symbol_available": @(launchSymbol != NULL),
        @"nextagent_scene_available": @(scene != nil),
        @"host_probe_ready": @(hostReady),
        @"mode": @"springboard_scene_host_50_50",
        @"bridge_version": @"0.7.9",
        @"transport_version": @"0.7.9-springboard-vision1"
    };
}

- (NSDictionary *)openPrimary:(NSString *)primary secondary:(NSString *)secondary {
    if (!primary.length || !secondary.length) {
        return @{@"success": @NO, @"error": @"missing split workspace bundle ID"};
    }

    [self close];
    self.lastError = nil;

    UIWindowScene *windowScene = [self springBoardWindowScene];
    if (!windowScene) {
        return @{@"success": @NO, @"error": @"SpringBoard UIWindowScene is unavailable"};
    }

    id primaryScene = [self waitForSceneBundleID:primary];
    id secondaryScene = [self waitForSceneBundleID:secondary];
    if (!primaryScene || !secondaryScene) {
        return @{
            @"success": @NO,
            @"error": @"one or both application scenes were unavailable",
            @"primary_scene": @(primaryScene != nil),
            @"secondary_scene": @(secondaryScene != nil)
        };
    }

    self.primaryUpdater = [self foregroundUpdaterForScene:primaryScene identifier:@"primary"];
    self.secondaryUpdater = [self foregroundUpdaterForScene:secondaryScene identifier:@"secondary"];
    [self markSceneForeground:primaryScene updater:self.primaryUpdater];
    [self markSceneForeground:secondaryScene updater:self.secondaryUpdater];

    [self.foregroundTimer invalidate];
    self.foregroundTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                            target:self
                                                          selector:@selector(refreshForegroundScenes)
                                                          userInfo:nil
                                                           repeats:YES];

    CGRect bounds = UIScreen.mainScreen.bounds;
    CGFloat divider = 2.0;
    CGFloat topHeight = floor((bounds.size.height - divider) * 0.50);
    CGRect topFrame = CGRectMake(0, 0, bounds.size.width, topHeight);
    CGRect bottomFrame = CGRectMake(
        0,
        topHeight + divider,
        bounds.size.width,
        bounds.size.height - topHeight - divider
    );

    UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
    window.frame = bounds;
    window.windowLevel = 999990.0;
    window.backgroundColor = UIColor.blackColor;
    window.opaque = YES;
    window.userInteractionEnabled = YES;

    UIViewController *controller = [UIViewController new];
    controller.view.frame = bounds;
    controller.view.backgroundColor = UIColor.blackColor;
    controller.view.userInteractionEnabled = YES;
    window.rootViewController = controller;

    UIView *top = [self hostViewForScene:primaryScene frame:topFrame label:@"Next Agent primary scene"];
    UIView *bottom = [self hostViewForScene:secondaryScene frame:bottomFrame label:@"Next Agent secondary scene"];
    if (!top || !bottom) {
        window.hidden = YES;
        return @{
            @"success": @NO,
            @"error": self.lastError ?: @"could not create one or both scene host views"
        };
    }

    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(0, topHeight, bounds.size.width, divider)];
    separator.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    separator.userInteractionEnabled = NO;

    [controller.view addSubview:top];
    [controller.view addSubview:bottom];
    [controller.view addSubview:separator];

    window.hidden = NO;
    window.alpha = 1.0;

    self.window = window;
    self.primaryHost = top;
    self.secondaryHost = bottom;
    self.primaryBundleID = primary;
    self.secondaryBundleID = secondary;

    return @{
        @"success": @YES,
        @"mode": @"springboard_scene_host_50_50",
        @"layout": @"top_bottom",
        @"primary_bundle_id": primary,
        @"secondary_bundle_id": secondary,
        @"primary_rect": @{
            @"x": @0,
            @"y": @0,
            @"width": @(bounds.size.width),
            @"height": @(topHeight)
        },
        @"secondary_rect": @{
            @"x": @0,
            @"y": @((topHeight + divider) / bounds.size.height),
            @"width": @1,
            @"height": @((bounds.size.height - topHeight - divider) / bounds.size.height)
        },
        @"window_level": @(window.windowLevel),
        @"interactive": @YES,
        @"experimental": @YES
    };
}

- (NSDictionary *)status {
    return @{
        @"success": @YES,
        @"active": @(self.window != nil && !self.window.hidden),
        @"primary_bundle_id": self.primaryBundleID ?: @"",
        @"secondary_bundle_id": self.secondaryBundleID ?: @"",
        @"primary_host_ready": @(self.primaryHost != nil),
        @"secondary_host_ready": @(self.secondaryHost != nil),
        @"last_error": self.lastError ?: @"",
        @"mode": @"springboard_scene_host_50_50"
    };
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
    return @{@"success": @YES, @"active": @NO};
}

@end

static CFMessagePortRef NABridgePort = NULL;
static CFRunLoopSourceRef NABridgeSource = NULL;
static CFStringRef const NABridgeServiceName =
    CFSTR("uk.zeshanbarvi.nextagent.bridge.v079");

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
                openPrimary:primary secondary:secondary]);
        }
        if ([action isEqualToString:@"split_status"]) {
            return NABridgeReply([[NASplitWorkspaceController shared] status]);
        }
        if ([action isEqualToString:@"split_close"]) {
            return NABridgeReply([[NASplitWorkspaceController shared] close]);
        }
        if ([action isEqualToString:@"ping"]) {
            return NABridgeReply(@{
                @"success": @YES,
                @"version": @"0.7.9",
                @"transport": @"cfmessageport",
                @"capture": @"in_memory",
                @"ocr": @"springboard_vision",
                @"split_workspace": @"springboard_scene_host_50_50"
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
