#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>

static const char *NAHUDStateNotification = "uk.zeshanbarvi.nextagent.hud.state";
static const char *NACaptureBeginNotification = "uk.zeshanbarvi.nextagent.capture.begin";
static const char *NACaptureEndNotification = "uk.zeshanbarvi.nextagent.capture.end";

@interface NAHUDWindow : UIWindow
@end
@implementation NAHUDWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
- (BOOL)canBecomeKeyWindow { return NO; }
@end

static NSString * const NAStatusHUDGeneration = @"system_status_hud_v0716";

@interface NAStatusHUD : NSObject
@property(nonatomic,strong) NAHUDWindow *window;
@property(nonatomic,strong) UIView *pill;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UILabel *icon;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) UIView *track;
@property(nonatomic,strong) UIView *fill;
@property(nonatomic,strong) NSLayoutConstraint *fillWidth;
@property(nonatomic,strong) NSTimer *pollTimer;
@property(nonatomic,assign) int stateToken;
@property(nonatomic,assign) BOOL captureSuppressed;
@property(nonatomic,assign) uint64_t lastTerminalState;
@property(nonatomic,strong) NSDate *lastTerminalDate;
+ (instancetype)shared;
- (void)start;
- (void)refresh;
@end

@implementation NAStatusHUD

+ (instancetype)shared {
    static NAStatusHUD *value;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ value = [NAStatusHUD new]; });
    return value;
}

- (UIWindowScene *)activeScene {
    if (@available(iOS 13.0, *)) {
        UIWindowScene *fallback = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (!fallback) fallback = ws;
            if (scene.activationState == UISceneActivationStateForegroundActive) return ws;
        }
        return fallback;
    }
    return nil;
}

- (void)ensureUI {
    UIWindowScene *scene = [self activeScene];
    if (!scene) return;

    if (self.window && self.window.windowScene == scene) return;
    self.window.hidden = YES;
    self.window = nil;

    NAHUDWindow *window = [[NAHUDWindow alloc] initWithWindowScene:scene];
    window.frame = scene.coordinateSpace.bounds;
    window.windowLevel = UIWindowLevelAlert + 1200.0;
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
    pill.layer.cornerRadius = 17.0;
    pill.layer.borderWidth = 0.8;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    pill.clipsToBounds = YES;
    [controller.view addSubview:pill];

    [NSLayoutConstraint activateConstraints:@[
        [pill.centerXAnchor constraintEqualToAnchor:controller.view.centerXAnchor],
        [pill.topAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.topAnchor constant:3.0],
        [pill.widthAnchor constraintGreaterThanOrEqualToConstant:178.0],
        [pill.widthAnchor constraintLessThanOrEqualToConstant:252.0],
        [pill.heightAnchor constraintEqualToConstant:34.0]
    ]];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.transform = CGAffineTransformMakeScale(0.68, 0.68);
    spinner.color = [UIColor colorWithRed:0.14 green:0.84 blue:1 alpha:1];
    [pill addSubview:spinner];

    UILabel *icon = [UILabel new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.hidden = YES;
    [pill addSubview:icon];

    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [pill addSubview:label];

    UIView *track = [UIView new];
    track.translatesAutoresizingMaskIntoConstraints = NO;
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    [pill addSubview:track];

    UIView *fill = [UIView new];
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    fill.backgroundColor = [UIColor colorWithRed:0.14 green:0.84 blue:1 alpha:1];
    [track addSubview:fill];

    NSLayoutConstraint *fillWidth = [fill.widthAnchor constraintEqualToConstant:2];

    [NSLayoutConstraint activateConstraints:@[
        [spinner.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:9],
        [spinner.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1],
        [spinner.widthAnchor constraintEqualToConstant:18],
        [spinner.heightAnchor constraintEqualToConstant:18],

        [icon.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:9],
        [icon.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],

        [label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:31],
        [label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-9],
        [label.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1],

        [track.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
        [track.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10],
        [track.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-3],
        [track.heightAnchor constraintEqualToConstant:2],

        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        fillWidth
    ]];

    self.window = window;
    self.pill = pill;
    self.label = label;
    self.icon = icon;
    self.spinner = spinner;
    self.track = track;
    self.fill = fill;
    self.fillWidth = fillWidth;
    [controller.view layoutIfNeeded];
}

- (NSString *)labelForDetail:(uint64_t)detail {
    switch (detail) {
        case 1: return @"Next Agent HUD • Opening app";
        case 2: return @"Next Agent HUD • Reading screen";
        case 3: return @"Next Agent • Typing…";
        case 4: return @"Next Agent HUD • Interacting";
        case 5: return @"Next Agent • Planning";
        case 6: return @"Next Agent • Resuming";
        case 7: return @"Next Agent HUD • Checking";
        case 8: return @"Next Agent HUD • Thinking…";
        case 9: return @"Next Agent HUD • Returning";
        default: return [NSString stringWithFormat:@"Next Agent HUD • Working"]; // system_status_hud_v0716
    }
}

- (void)setProgress:(CGFloat)progress {
    [self.pill layoutIfNeeded];
    CGFloat width = MAX(2.0, self.pill.bounds.size.width - 20.0);
    self.fillWidth.constant = width * MAX(0.02, MIN(1.0, progress));
    [self.pill layoutIfNeeded];
}

- (void)show {
    [self ensureUI];
    if (!self.window || self.captureSuppressed) return;
    self.window.hidden = NO;
    self.pill.hidden = NO;
}

- (void)hide {
    self.window.hidden = YES;
}

- (void)refresh {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }

    if (UIApplication.sharedApplication.applicationState != UIApplicationStateActive ||
        self.captureSuppressed) {
        [self hide];
        return;
    }

    [self ensureUI];
    if (self.stateToken < 0) return;

    uint64_t packed = 0;
    if (notify_get_state(self.stateToken, &packed) != NOTIFY_STATUS_OK) return;

    uint64_t mode = (packed >> 56) & 0xff;
    uint64_t detail = (packed >> 48) & 0xff;
    CGFloat progress = (CGFloat)(packed & 0xffff) / 1000.0;

    if (mode == 0) {
        [self hide];
        return;
    }

    if (mode == 1) {
        self.lastTerminalState = 0;
        self.lastTerminalDate = nil;
        self.spinner.hidden = NO;
        self.icon.hidden = YES;
        [self.spinner startAnimating];
        self.label.text = [self labelForDetail:detail];
        self.fill.backgroundColor = [UIColor colorWithRed:0.14 green:0.84 blue:1 alpha:1];
        [self setProgress:MAX(0.05, progress)];
        [self show];
        return;
    }

    if (self.lastTerminalState != packed) {
        self.lastTerminalState = packed;
        self.lastTerminalDate = [NSDate date];
    } else if (self.lastTerminalDate &&
               [[NSDate date] timeIntervalSinceDate:self.lastTerminalDate] > 2.8) {
        [self hide];
        return;
    }

    [self.spinner stopAnimating];
    self.spinner.hidden = YES;
    self.icon.hidden = NO;
    [self setProgress:1.0];

    if (mode == 2) {
        self.icon.text = @"✓";
        self.icon.textColor = [UIColor colorWithRed:0.24 green:0.95 blue:0.62 alpha:1];
        self.fill.backgroundColor = self.icon.textColor;
        self.label.text = @"Next Agent HUD • Complete";
    } else {
        self.icon.text = mode == 4 ? @"■" : @"!";
        self.icon.textColor = [UIColor colorWithRed:1 green:0.36 blue:0.45 alpha:1];
        self.fill.backgroundColor = self.icon.textColor;
        self.label.text = mode == 4 ? @"Next Agent HUD • Stopped" : @"Next Agent HUD • Failed";
    }
    [self show];
}

- (void)start {
    if (self.stateToken == 0) self.stateToken = -1;
    if (self.stateToken < 0) {
        notify_register_check(NAHUDStateNotification, &_stateToken);
    }

    int stateNotify = 0;
    notify_register_dispatch(
        NAHUDStateNotification,
        &stateNotify,
        dispatch_get_main_queue(),
        ^(__unused int token) { [[NAStatusHUD shared] refresh]; }
    );

    int captureBegin = 0;
    notify_register_dispatch(
        NACaptureBeginNotification,
        &captureBegin,
        dispatch_get_main_queue(),
        ^(__unused int token) {
            NAStatusHUD *hud = [NAStatusHUD shared];
            hud.captureSuppressed = YES;
            [hud hide];
        }
    );

    int captureEnd = 0;
    notify_register_dispatch(
        NACaptureEndNotification,
        &captureEnd,
        dispatch_get_main_queue(),
        ^(__unused int token) {
            NAStatusHUD *hud = [NAStatusHUD shared];
            hud.captureSuppressed = NO;
            [hud refresh];
        }
    );

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.35
                                                      target:self
                                                    selector:@selector(refresh)
                                                    userInfo:nil
                                                     repeats:YES];
    [self refresh];
}

@end

__attribute__((constructor))
static void NAStatusHUDInit(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if ([bundle isEqualToString:@"com.apple.springboard"]) {
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (UIApplication.sharedApplication) {
                NAStatusHUD *hud = [NAStatusHUD shared];
                hud.stateToken = -1;
                [hud start];
            }
        });
    }
}
