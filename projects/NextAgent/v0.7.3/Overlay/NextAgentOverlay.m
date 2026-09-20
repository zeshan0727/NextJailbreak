#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const NAProgressPath = @"/var/mobile/Library/NextAgent/progress.json";
static const char *NAProgressNotification = "uk.zeshanbarvi.nextagent.progress.changed";
static NSString * const NABundleID = @"uk.zeshanbarvi.nextagent";

@interface NAPassThroughWindow : UIWindow
@end
@implementation NAPassThroughWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
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
+ (instancetype)shared;
- (void)refresh;
@end

@implementation NAProgressOverlay

+ (instancetype)shared {
    static NAProgressOverlay *value;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ value = [NAProgressOverlay new]; });
    return value;
}

- (void)ensureUI {
    if (self.window) return;

    CGRect screen = UIScreen.mainScreen.bounds;
    CGFloat width = MIN(246.0, screen.size.width - 44.0);
    CGFloat y = 51.0;

    NAPassThroughWindow *window = [[NAPassThroughWindow alloc] initWithFrame:CGRectMake((screen.size.width-width)/2.0, y, width, 38.0)];
    window.windowLevel = UIWindowLevelAlert + 1100.0;
    window.backgroundColor = UIColor.clearColor;
    window.hidden = YES;
    window.userInteractionEnabled = NO;

    UIViewController *controller = [UIViewController new];
    controller.view.backgroundColor = UIColor.clearColor;
    window.rootViewController = controller;

    UIView *pill = [UIView new];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.92];
    pill.layer.cornerRadius = 18.0;
    pill.layer.masksToBounds = YES;
    pill.layer.borderWidth = 0.5;
    pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    [controller.view addSubview:pill];

    [NSLayoutConstraint activateConstraints:@[
        [pill.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [pill.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
        [pill.topAnchor constraintEqualToAnchor:controller.view.topAnchor],
        [pill.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor]
    ]];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    spinner.transform = CGAffineTransformMakeScale(0.72, 0.72);
    spinner.color = [UIColor colorWithRed:0.23 green:0.91 blue:1.0 alpha:1.0];
    [pill addSubview:spinner];

    UILabel *icon = [UILabel new];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    icon.textAlignment = NSTextAlignmentCenter;
    icon.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.64 alpha:1.0];
    icon.hidden = YES;
    [pill addSubview:icon];

    UILabel *title = [UILabel new];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:12.5 weight:UIFontWeightSemibold];
    title.textColor = UIColor.whiteColor;
    title.lineBreakMode = NSLineBreakByTruncatingTail;
    [pill addSubview:title];

    UIView *track = [UIView new];
    track.translatesAutoresizingMaskIntoConstraints = NO;
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    [pill addSubview:track];

    UIView *fill = [UIView new];
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    fill.backgroundColor = [UIColor colorWithRed:0.20 green:0.85 blue:1.0 alpha:1.0];
    [track addSubview:fill];

    NSLayoutConstraint *fillWidth = [fill.widthAnchor constraintEqualToConstant:0];

    [NSLayoutConstraint activateConstraints:@[
        [spinner.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
        [spinner.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1],
        [spinner.widthAnchor constraintEqualToConstant:18],
        [spinner.heightAnchor constraintEqualToConstant:18],

        [icon.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
        [icon.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-1],
        [icon.widthAnchor constraintEqualToConstant:18],
        [icon.heightAnchor constraintEqualToConstant:18],

        [title.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:36],
        [title.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-12],
        [title.centerYAnchor constraintEqualToAnchor:pill.centerYAnchor constant:-2],

        [track.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:12],
        [track.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-12],
        [track.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-4],
        [track.heightAnchor constraintEqualToConstant:2],

        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        fillWidth
    ]];

    track.layer.cornerRadius = 1;
    fill.layer.cornerRadius = 1;

    self.window = window;
    self.pill = pill;
    self.spinner = spinner;
    self.iconLabel = icon;
    self.titleLabel = title;
    self.track = track;
    self.fill = fill;
    self.fillWidth = fillWidth;
}

- (NSDictionary *)readState {
    NSData *data = [NSData dataWithContentsOfFile:NAProgressPath options:0 error:nil];
    if (!data.length) return nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

- (void)setProgress:(CGFloat)value animated:(BOOL)animated {
    [self ensureUI];
    CGFloat clamped = MAX(0.02, MIN(1.0, value));
    CGFloat maxWidth = MAX(0, self.window.bounds.size.width - 24.0);
    self.fillWidth.constant = maxWidth * clamped;
    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{
            [self.track layoutIfNeeded];
        }];
    } else {
        [self.track layoutIfNeeded];
    }
}

- (void)show {
    [self ensureUI];
    self.window.hidden = NO;
    self.window.alpha = 1.0;
    self.visible = YES;
}

- (void)hide {
    if (!self.window) return;
    self.window.hidden = YES;
    self.visible = NO;
    [self.pollTimer invalidate];
    self.pollTimer = nil;
}

- (void)beginPollingIfNeeded {
    if (self.pollTimer) return;
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(__unused NSTimer *timer) {
        [[NAProgressOverlay shared] refresh];
    }];
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

- (void)refresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *state = [self readState];
        NSString *mode = [state[@"state"] isKindOfClass:NSString.class] ? state[@"state"] : @"idle";
        NSString *message = [state[@"message"] isKindOfClass:NSString.class] ? state[@"message"] : @"";
        CGFloat progress = [state[@"progress"] respondsToSelector:@selector(doubleValue)] ? [state[@"progress"] doubleValue] : 0;
        BOOL returnToApp = [state[@"return_to_app"] boolValue];

        if ([mode isEqualToString:@"idle"] || !state) {
            [self hide];
            return;
        }

        [self show];
        self.titleLabel.text = message.length ? message : @"Next Agent working";

        if ([mode isEqualToString:@"working"]) {
            self.spinner.hidden = NO;
            self.iconLabel.hidden = YES;
            [self.spinner startAnimating];
            self.fill.backgroundColor = [UIColor colorWithRed:0.20 green:0.85 blue:1.0 alpha:1.0];
            [self setProgress:MAX(0.05, progress) animated:YES];
            [self beginPollingIfNeeded];
            return;
        }

        [self.spinner stopAnimating];
        self.spinner.hidden = YES;
        self.iconLabel.hidden = NO;

        if ([mode isEqualToString:@"complete"]) {
            self.iconLabel.text = @"✓";
            self.iconLabel.textColor = [UIColor colorWithRed:0.25 green:0.95 blue:0.64 alpha:1.0];
            self.fill.backgroundColor = self.iconLabel.textColor;
            self.titleLabel.text = message.length ? message : @"Complete";
            [self setProgress:1.0 animated:YES];

            if (returnToApp) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self returnToNextAgent];
                });
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self hide];
            });
            return;
        }

        self.iconLabel.text = [mode isEqualToString:@"stopped"] ? @"■" : @"!";
        self.iconLabel.textColor = [UIColor colorWithRed:1.0 green:0.39 blue:0.47 alpha:1.0];
        self.fill.backgroundColor = self.iconLabel.textColor;
        self.titleLabel.text = message.length ? message : ([mode isEqualToString:@"stopped"] ? @"Stopped" : @"Action failed");
        [self setProgress:1.0 animated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self hide];
        });
    });
}

@end

__attribute__((constructor))
static void NAOverlayInit(void) {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if (![bundle isEqualToString:@"com.apple.springboard"]) return;

        dispatch_async(dispatch_get_main_queue(), ^{
            [[NAProgressOverlay shared] refresh];

            int token = 0;
            notify_register_dispatch(
                NAProgressNotification,
                &token,
                dispatch_get_main_queue(),
                ^(__unused int notifyToken) {
                    [[NAProgressOverlay shared] refresh];
                }
            );
        });
    }
}
