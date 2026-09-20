#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <notify.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>

static NSString * const NAProgressPath = @"/var/mobile/Library/NextAgent/progress.json";
static NSString * const NAOverlayStatusPath = @"/var/mobile/Library/NextAgent/overlay.status.json";
static NSString * const NAScreenRequestPath = @"/var/mobile/Library/NextAgent/screen.request.json";
static NSString * const NAScreenResponsePath = @"/var/mobile/Library/NextAgent/screen.response.json";
static NSString * const NACaptureDirectory = @"/var/mobile/Library/NextAgent/Captures";
static NSString * const NABundleID = @"uk.zeshanbarvi.nextagent";

static const char *NAProgressNotification = "uk.zeshanbarvi.nextagent.progress.changed";
static const char *NAScreenRequestNotification = "uk.zeshanbarvi.nextagent.screen.capture.request";
static const char *NAScreenDoneNotification = "uk.zeshanbarvi.nextagent.screen.capture.done";

typedef CGImageRef (*NACARenderServerCaptureDisplay)(uint32_t, CFStringRef, CFDictionaryRef);
typedef UIImage * NS_RETURNS_RETAINED (*NAUICreateScreenUIImage)(void);

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
    NAPassThroughWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = [self preferredWindowScene];
        if (scene) {
            window = [[NAPassThroughWindow alloc] initWithWindowScene:scene];
            window.frame = screen.bounds;
        }
    }
    if (!window) {
        window = [[NAPassThroughWindow alloc] initWithFrame:screen.bounds];
    }

    window.windowLevel = UIWindowLevelAlert + 5000.0;
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
        @"pid": @(getpid()),
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"window_ready": @(self.window != nil),
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

- (UIImage *)captureDisplayWithSource:(NSString **)sourceOut {
    void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_NOW | RTLD_LOCAL);
    NACARenderServerCaptureDisplay renderCapture = (NACARenderServerCaptureDisplay)dlsym(
        qc ?: RTLD_DEFAULT,
        "CARenderServerCaptureDisplay"
    );

    if (renderCapture) {
        for (NSString *displayName in @[@"LCD", @"Main"]) {
            CGImageRef cg = renderCapture(0, (__bridge CFStringRef)displayName, nil);
            if (!cg) continue;
            UIImage *image = [self bitmapImageFromCGImage:cg];
            CGImageRelease(cg);
            if (image) {
                if (sourceOut) *sourceOut = [@"render_server:" stringByAppendingString:displayName];
                return image;
            }
        }
    }

    NAUICreateScreenUIImage uiCapture = (NAUICreateScreenUIImage)dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
    if (uiCapture) {
        UIImage *image = uiCapture();
        if (image) {
            if (sourceOut) *sourceOut = @"springboard_uicreate";
            return image;
        }
    }

    if (sourceOut) *sourceOut = @"unavailable";
    return nil;
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

        NSString *source = nil;
        UIImage *image = [self captureDisplayWithSource:&source];

        if (wasVisible) {
            self.pill.hidden = NO;
        }

        NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{
            @"request_id": requestID,
            @"success": @(image != nil),
            @"source": source ?: @"unavailable",
            @"timestamp": @([[NSDate date] timeIntervalSince1970])
        }];

        if (image) {
            NAEnsureDirectory(NACaptureDirectory);
            NSString *safeID = [[requestID componentsSeparatedByCharactersInSet:
                [[NSCharacterSet alphanumericCharacterSet] invertedSet]] componentsJoinedByString:@"-"];
            NSString *path = [NACaptureDirectory stringByAppendingPathComponent:
                [NSString stringWithFormat:@"screen-%@.jpg", safeID]];
            NSData *jpeg = UIImageJPEGRepresentation(image, 0.82);
            BOOL written = jpeg.length && [jpeg writeToFile:path options:NSDataWritingAtomic error:nil];
            if (written) {
                response[@"path"] = path;
                response[@"bytes"] = @(jpeg.length);
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

__attribute__((constructor))
static void NAOverlayInit(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
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
