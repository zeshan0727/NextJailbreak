#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/runtime.h>
#import <unistd.h>

static const char *NAHUDStateNotification = "uk.zeshanbarvi.nextagent.hud.state";
static const char *NACaptureBeginNotification = "uk.zeshanbarvi.nextagent.capture.begin";
static const char *NACaptureEndNotification = "uk.zeshanbarvi.nextagent.capture.end";
static NSString * const NAHUDStatusPath = @"/var/mobile/Library/NextAgent/statushud.springboard.json";
static NSString * const NAGeneration = @"springboard_statusbar_hud_v0719";

static void NAWriteStatus(NSDictionary *extra) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSData *oldData = [NSData dataWithContentsOfFile:NAHUDStatusPath];
    if (oldData.length) {
        id old = [NSJSONSerialization JSONObjectWithData:oldData options:0 error:nil];
        if ([old isKindOfClass:NSDictionary.class]) [d addEntriesFromDictionary:old];
    }
    [d addEntriesFromDictionary:@{
        @"loaded": @YES,
        @"generation": NAGeneration,
        @"bundle": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"pid": @(getpid()),
        @"updated_at": @([[NSDate date] timeIntervalSince1970])
    }];
    if (extra) [d addEntriesFromDictionary:extra];

    NSString *dir = [NAHUDStatusPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:@{NSFilePosixPermissions:@0755}
                                                    error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];
    if (data.length) [data writeToFile:NAHUDStatusPath atomically:YES];
}

static UIView *NAFindStatusViewRecursive(UIView *view) {
    if (!view) return nil;
    NSString *name = NSStringFromClass(view.class) ?: @"";
    if ([name containsString:@"SBMainDisplaySceneLayoutStatusBarView"] ||
        [name containsString:@"StatusBarWindow"] ||
        [name hasPrefix:@"_UIStatusBar"] ||
        [name isEqualToString:@"UIStatusBar"]) {
        return view;
    }
    for (UIView *sub in view.subviews) {
        UIView *hit = NAFindStatusViewRecursive(sub);
        if (hit) return hit;
    }
    return nil;
}

@interface NASpringBoardHUD : NSObject
@property(nonatomic,strong) UIView *pill;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) UILabel *icon;
@property(nonatomic,strong) UIActivityIndicatorView *spinner;
@property(nonatomic,strong) UIView *track;
@property(nonatomic,strong) UIView *fill;
@property(nonatomic,strong) NSTimer *pollTimer;
@property(nonatomic,strong) NSTimer *terminalTimer;
@property(nonatomic,weak) UIWindow *hostWindow;
@property(nonatomic,weak) UIView *hostView;
@property(nonatomic,assign) int stateToken;
@property(nonatomic,assign) BOOL captureSuppressed;
@property(nonatomic,assign) BOOL visible;
@property(nonatomic,assign) uint64_t lastPacked;
+ (instancetype)shared;
- (void)start;
- (void)refresh;
@end

@implementation NASpringBoardHUD

+ (instancetype)shared {
    static NASpringBoardHUD *x;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ x = [NASpringBoardHUD new]; });
    return x;
}

- (NSArray<UIWindow *> *)allWindows {
    NSMutableArray<UIWindow *> *out = [NSMutableArray array];
    UIApplication *app = UIApplication.sharedApplication;
    if ([app respondsToSelector:@selector(windows)]) {
        for (UIWindow *w in app.windows ?: @[]) if (w && ![out containsObject:w]) [out addObject:w];
    }
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows ?: @[]) {
                if (w && ![out containsObject:w]) [out addObject:w];
            }
        }
    }
    return out;
}

- (UIWindow *)findHostWindow:(UIView **)statusViewOut {
    NSArray<UIWindow *> *windows = [self allWindows];
    UIWindow *fallback = nil;
    CGFloat bestLevel = -CGFLOAT_MAX;

    for (UIWindow *w in windows) {
        if (w.hidden || w.alpha < 0.01) continue;
        NSString *wn = NSStringFromClass(w.class) ?: @"";
        UIView *status = NAFindStatusViewRecursive(w);
        if (status) {
            if (statusViewOut) *statusViewOut = status;
            return w;
        }
        if ([wn containsString:@"StatusBar"] || [wn containsString:@"SpringBoard"]) {
            if (statusViewOut) *statusViewOut = nil;
            return w;
        }
        if (w.windowLevel > bestLevel) {
            bestLevel = w.windowLevel;
            fallback = w;
        }
    }

    if (statusViewOut) *statusViewOut = nil;
    return fallback;
}

- (void)removePill {
    [self.pill removeFromSuperview];
    self.pill = nil;
    self.label = nil;
    self.icon = nil;
    self.spinner = nil;
    self.track = nil;
    self.fill = nil;
    self.hostWindow = nil;
    self.hostView = nil;
}

- (void)ensureHost {
    UIView *status = nil;
    UIWindow *window = [self findHostWindow:&status];
    if (!window) {
        NAWriteStatus(@{
            @"host_found": @NO,
            @"view_ready": @NO,
            @"visible": @NO,
            @"failure": @"No SpringBoard/status-bar window found"
        });
        return;
    }

    if (self.pill && self.hostWindow == window && self.pill.superview) {
        return;
    }

    [self removePill];
    self.hostWindow = window;
    self.hostView = status;

    UIView *pill = [UIView new];
    pill.userInteractionEnabled = NO;
    pill.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.96];
    pill.layer.cornerRadius = 16.0;
    pill.layer.borderWidth = 0.7;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    pill.layer.shadowColor = [UIColor colorWithRed:0.10 green:0.78 blue:1 alpha:1].CGColor;
    pill.layer.shadowOpacity = 0.28;
    pill.layer.shadowRadius = 9.0;
    pill.layer.shadowOffset = CGSizeZero;
    pill.hidden = YES;
    pill.layer.zPosition = CGFLOAT_MAX;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.transform = CGAffineTransformMakeScale(0.68, 0.68);
    spinner.color = [UIColor colorWithRed:0.17 green:0.84 blue:1 alpha:1];
    [pill addSubview:spinner];

    UILabel *icon = [UILabel new];
    icon.font = [UIFont systemFontOfSize:13.5 weight:UIFontWeightBold];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.hidden = YES;
    [pill addSubview:icon];

    UILabel *label = [UILabel new];
    label.font = [UIFont systemFontOfSize:11.5 weight:UIFontWeightSemibold];
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    [pill addSubview:label];

    UIView *track = [UIView new];
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    [pill addSubview:track];

    UIView *fill = [UIView new];
    fill.backgroundColor = [UIColor colorWithRed:0.17 green:0.84 blue:1 alpha:1];
    [track addSubview:fill];

    // Add directly to the SpringBoard status-bar window, not to the foreground app.
    window.clipsToBounds = NO;
    [window addSubview:pill];

    self.pill = pill;
    self.spinner = spinner;
    self.icon = icon;
    self.label = label;
    self.track = track;
    self.fill = fill;

    [self layoutPill];

    NAWriteStatus(@{
        @"host_found": @YES,
        @"view_ready": @YES,
        @"visible": @NO,
        @"host_window_class": NSStringFromClass(window.class) ?: @"",
        @"host_view_class": status ? (NSStringFromClass(status.class) ?: @"") : @"",
        @"host_window_level": @(window.windowLevel),
        @"host_window_hidden": @(window.hidden),
        @"failure": @""
    });
}

- (void)layoutPill {
    if (!self.pill || !self.hostWindow) return;

    CGRect wb = self.hostWindow.bounds;
    CGFloat width = MIN(224.0, MAX(176.0, wb.size.width - 64.0));
    CGFloat height = 32.0;

    // On Dynamic Island devices keep the pill just below the island/status bar.
    CGFloat y = 58.0;
    UIEdgeInsets insets = self.hostWindow.safeAreaInsets;
    if (insets.top < 44.0) y = MAX(28.0, insets.top + 3.0);

    CGFloat x = floor((wb.size.width - width) * 0.5);
    self.pill.frame = CGRectMake(x, y, width, height);

    self.spinner.frame = CGRectMake(8, 5, 20, 20);
    self.icon.frame = CGRectMake(9, 6, 18, 18);
    self.label.frame = CGRectMake(31, 3, width - 40, 23);
    self.track.frame = CGRectMake(10, height - 4, width - 20, 2);
    CGFloat p = 0.06;
    if (self.lastPacked) p = MAX(0.02, MIN(1.0, (CGFloat)(self.lastPacked & 0xffff) / 1000.0));
    self.fill.frame = CGRectMake(0, 0, self.track.bounds.size.width * p, 2);
}

- (NSString *)textForDetail:(uint64_t)detail {
    switch (detail) {
        case 1: return @"Next Agent • Opening app";
        case 2: return @"Next Agent • Reading screen";
        case 3: return @"Next Agent • Typing";
        case 4: return @"Next Agent • Interacting";
        case 5: return @"Next Agent • Planning";
        case 6: return @"Next Agent • Resuming";
        case 7: return @"Next Agent • Checking";
        case 8: return @"Next Agent • Thinking";
        case 9: return @"Next Agent • Returning";
        default: return @"Next Agent • Working";
    }
}

- (void)showMode:(uint64_t)mode detail:(uint64_t)detail progress:(CGFloat)progress {
    [self ensureHost];
    if (!self.pill || self.captureSuppressed) return;

    [self.terminalTimer invalidate];
    self.terminalTimer = nil;

    self.spinner.hidden = YES;
    self.icon.hidden = YES;

    if (mode == 1) {
        self.spinner.hidden = NO;
        [self.spinner startAnimating];
        self.label.text = [self textForDetail:detail];
        self.fill.backgroundColor = [UIColor colorWithRed:0.17 green:0.84 blue:1 alpha:1];
    } else if (mode == 2) {
        [self.spinner stopAnimating];
        self.icon.hidden = NO;
        self.icon.text = @"✓";
        self.icon.textColor = [UIColor colorWithRed:0.24 green:0.95 blue:0.62 alpha:1];
        self.label.text = @"Next Agent • Complete";
        self.fill.backgroundColor = self.icon.textColor;
        progress = 1.0;
    } else if (mode == 4) {
        [self.spinner stopAnimating];
        self.icon.hidden = NO;
        self.icon.text = @"■";
        self.icon.textColor = [UIColor colorWithRed:1 green:0.40 blue:0.47 alpha:1];
        self.label.text = @"Next Agent • Stopped";
        self.fill.backgroundColor = self.icon.textColor;
        progress = 1.0;
    } else {
        [self.spinner stopAnimating];
        self.icon.hidden = NO;
        self.icon.text = @"!";
        self.icon.textColor = [UIColor colorWithRed:1 green:0.40 blue:0.47 alpha:1];
        self.label.text = @"Next Agent • Failed";
        self.fill.backgroundColor = self.icon.textColor;
        progress = 1.0;
    }

    self.fill.frame = CGRectMake(0, 0, self.track.bounds.size.width * MAX(0.02, MIN(1.0, progress)), 2);
    self.pill.hidden = NO;
    [self.hostWindow bringSubviewToFront:self.pill];
    self.visible = YES;

    NAWriteStatus(@{
        @"host_found": @YES,
        @"view_ready": @YES,
        @"visible": @YES,
        @"mode": @(mode),
        @"detail": @(detail),
        @"progress": @(progress),
        @"host_window_class": NSStringFromClass(self.hostWindow.class) ?: @"",
        @"host_view_class": self.hostView ? (NSStringFromClass(self.hostView.class) ?: @"") : @"",
        @"host_window_level": @(self.hostWindow.windowLevel),
        @"pill_frame": NSStringFromCGRect(self.pill.frame)
    });

    if (mode != 1) {
        self.terminalTimer = [NSTimer scheduledTimerWithTimeInterval:2.4
                                                             repeats:NO
                                                               block:^(__unused NSTimer *timer) {
            NASpringBoardHUD *hud = [NASpringBoardHUD shared];
            hud.pill.hidden = YES;
            hud.visible = NO;
            NAWriteStatus(@{@"visible": @NO});
        }];
    }
}

- (void)refresh {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
        return;
    }

    [self ensureHost];
    [self layoutPill];

    if (self.stateToken < 0) return;
    uint64_t packed = 0;
    if (notify_get_state(self.stateToken, &packed) != NOTIFY_STATUS_OK) return;
    self.lastPacked = packed;

    uint64_t mode = (packed >> 56) & 0xff;
    uint64_t detail = (packed >> 48) & 0xff;
    CGFloat progress = (CGFloat)(packed & 0xffff) / 1000.0;

    if (mode == 0 || self.captureSuppressed) {
        self.pill.hidden = YES;
        self.visible = NO;
        NAWriteStatus(@{
            @"mode": @(mode),
            @"detail": @(detail),
            @"progress": @(progress),
            @"visible": @NO
        });
        return;
    }

    [self showMode:mode detail:detail progress:progress];
}

- (void)start {
    if (self.stateToken == 0) self.stateToken = -1;
    if (self.stateToken < 0) notify_register_check(NAHUDStateNotification, &_stateToken);

    int stateNotify = 0;
    notify_register_dispatch(NAHUDStateNotification, &stateNotify, dispatch_get_main_queue(),
        ^(__unused int token) { [[NASpringBoardHUD shared] refresh]; });

    int captureBegin = 0;
    notify_register_dispatch(NACaptureBeginNotification, &captureBegin, dispatch_get_main_queue(),
        ^(__unused int token) {
            NASpringBoardHUD *hud = [NASpringBoardHUD shared];
            hud.captureSuppressed = YES;
            hud.pill.hidden = YES;
            hud.visible = NO;
            NAWriteStatus(@{@"capture_suppressed": @YES, @"visible": @NO});
        });

    int captureEnd = 0;
    notify_register_dispatch(NACaptureEndNotification, &captureEnd, dispatch_get_main_queue(),
        ^(__unused int token) {
            NASpringBoardHUD *hud = [NASpringBoardHUD shared];
            hud.captureSuppressed = NO;
            NAWriteStatus(@{@"capture_suppressed": @NO});
            [hud refresh];
        });

    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.50
                                                      target:self
                                                    selector:@selector(refresh)
                                                    userInfo:nil
                                                     repeats:YES];

    [self ensureHost];
    [self refresh];
}

@end

__attribute__((constructor))
static void NAStatusHUD0719Init(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;

        NAWriteStatus(@{
            @"constructor": @"entered",
            @"host_found": @NO,
            @"view_ready": @NO,
            @"visible": @NO
        });

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NASpringBoardHUD shared] start];
            NAWriteStatus(@{@"constructor": @"started"});
        });
    }
}
