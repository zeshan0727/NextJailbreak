#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <unistd.h>

static NSString * const LTPrefsPath = @"/var/mobile/Library/Preferences/com.nextjailbreak.livetouch.plist";
static NSString * const LTDataDir = @"/var/mobile/Library/LiveTouchWallpaper";
static NSString * const LTLogPath = @"/var/mobile/Library/LiveTouchWallpaper/engine.log";

static void LTLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:LTDataDir withIntermediateDirectories:YES attributes:nil error:nil];
    if (![fm fileExistsAtPath:LTLogPath]) {
        [data writeToFile:LTLogPath atomically:YES];
    } else {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:LTLogPath];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

@interface LTWallpaperView : UIView
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) id endObserver;
@property (nonatomic, copy) NSString *triggerMode;
- (void)configureWithPreferences:(NSDictionary *)prefs;
- (void)playOnce;
- (void)resetToFirstFrame;
@end

@implementation LTWallpaperView

+ (Class)layerClass { return [AVPlayerLayer class]; }
- (AVPlayerLayer *)playerLayer { return (AVPlayerLayer *)self.layer; }

- (void)dealloc {
    if (self.endObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.endObserver];
}

- (void)configureWithPreferences:(NSDictionary *)prefs {
    NSString *videoPath = prefs[@"videoPath"];
    self.triggerMode = [prefs[@"trigger"] isKindOfClass:NSString.class] ? prefs[@"trigger"] : @"tap";
    if (!videoPath.length || ![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        LTLog(@"Wallpaper video missing: %@", videoPath ?: @"(nil)");
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:videoPath]];
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    self.player.muted = [prefs[@"mute"] boolValue];
    if ([self.player respondsToSelector:@selector(setAutomaticallyWaitsToMinimizeStalling:)]) {
        self.player.automaticallyWaitsToMinimizeStalling = NO;
    }

    AVPlayerLayer *layer = self.playerLayer;
    layer.player = self.player;
    NSString *gravity = [prefs[@"gravity"] isKindOfClass:NSString.class] ? prefs[@"gravity"] : @"fill";
    layer.videoGravity = [gravity isEqualToString:@"fit"] ? AVLayerVideoGravityResizeAspect : AVLayerVideoGravityResizeAspectFill;

    __weak typeof(self) weakSelf = self;
    self.endObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        [weakSelf resetToFirstFrame];
    }];

    [self resetToFirstFrame];
    LTLog(@"Configured player path=%@ mode=%@ gravity=%@ mute=%d", videoPath, self.triggerMode, gravity, self.player.muted);
}

- (void)resetToFirstFrame {
    AVPlayer *player = self.player;
    if (!player) return;
    [player pause];
    [player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(__unused BOOL finished) {
        [player pause];
    }];
}

- (void)playOnce {
    AVPlayer *player = self.player;
    if (!player) return;
    [player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        if (finished) [player play];
    }];
}

@end

static const void *LTWallpaperKey = &LTWallpaperKey;
static const void *LTGestureKey = &LTGestureKey;
static IMP LTOriginalViewDidAppear = NULL;
static Class LTHookedControllerClass = Nil;

static NSDictionary *LTPreferences(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:LTPrefsPath];
    return [prefs isKindOfClass:NSDictionary.class] ? prefs : nil;
}

static void LTLogSubviewClasses(UIView *view) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIView *subview in view.subviews) {
        [names addObject:NSStringFromClass(subview.class) ?: @"?"];
        if (names.count >= 20) break;
    }
    LTLog(@"CoverSheet root subviews: %@", [names componentsJoinedByString:@", "]);
}

static UIViewController *LTControllerForView(UIView *view) {
    UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:UIViewController.class]) return (UIViewController *)responder;
        responder = responder.nextResponder;
    }
    return nil;
}

static void LTTriggerGesture(UIGestureRecognizer *gesture) {
    UIViewController *controller = LTControllerForView(gesture.view);
    LTWallpaperView *wallpaper = controller ? objc_getAssociatedObject(controller, LTWallpaperKey) : nil;
    if (!wallpaper) return;
    if ([gesture isKindOfClass:UILongPressGestureRecognizer.class]) {
        if (gesture.state == UIGestureRecognizerStateBegan) [wallpaper playOnce];
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        [wallpaper playOnce];
    }
}

@interface LTGestureProxy : NSObject
+ (instancetype)shared;
- (void)trigger:(UIGestureRecognizer *)gesture;
@end
@implementation LTGestureProxy
+ (instancetype)shared {
    static LTGestureProxy *proxy;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ proxy = [LTGestureProxy new]; });
    return proxy;
}
- (void)trigger:(UIGestureRecognizer *)gesture { LTTriggerGesture(gesture); }
@end

static void LTInstallWallpaperOnController(UIViewController *controller) {
    if (!controller || !controller.view) return;
    NSDictionary *prefs = LTPreferences();
    if (![prefs[@"enabled"] boolValue]) {
        LTLog(@"Preferences not enabled; skipping wallpaper");
        return;
    }

    NSString *videoPath = prefs[@"videoPath"];
    if (!videoPath.length || ![[NSFileManager defaultManager] fileExistsAtPath:videoPath]) {
        LTLog(@"Configured video missing at %@", videoPath ?: @"(nil)");
        return;
    }

    LTWallpaperView *existing = objc_getAssociatedObject(controller, LTWallpaperKey);
    if (existing) {
        existing.frame = controller.view.bounds;
        [existing resetToFirstFrame];
        return;
    }

    UIView *root = controller.view;
    LTWallpaperView *wallpaper = [[LTWallpaperView alloc] initWithFrame:root.bounds];
    wallpaper.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    wallpaper.userInteractionEnabled = NO;
    wallpaper.backgroundColor = UIColor.blackColor;
    [wallpaper configureWithPreferences:prefs];

    [root insertSubview:wallpaper atIndex:0];
    objc_setAssociatedObject(controller, LTWallpaperKey, wallpaper, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSString *trigger = [prefs[@"trigger"] isKindOfClass:NSString.class] ? prefs[@"trigger"] : @"tap";
    UIGestureRecognizer *gesture;
    if ([trigger isEqualToString:@"press"]) {
        UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:[LTGestureProxy shared] action:@selector(trigger:)];
        press.minimumPressDuration = 0.18;
        press.cancelsTouchesInView = NO;
        gesture = press;
    } else {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[LTGestureProxy shared] action:@selector(trigger:)];
        tap.cancelsTouchesInView = NO;
        gesture = tap;
    }
    [root addGestureRecognizer:gesture];
    objc_setAssociatedObject(controller, LTGestureKey, gesture, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    LTLog(@"Wallpaper attached to %@ frame=%@ trigger=%@", NSStringFromClass(controller.class), NSStringFromCGRect(root.bounds), trigger);
    LTLogSubviewClasses(root);
}

static void LTViewDidAppearReplacement(id self, SEL _cmd, BOOL animated) {
    if (LTOriginalViewDidAppear) {
        ((void(*)(id, SEL, BOOL))LTOriginalViewDidAppear)(self, _cmd, animated);
    }
    LTInstallWallpaperOnController((UIViewController *)self);
}

static BOOL LTHookControllerNamed(NSString *name) {
    Class cls = NSClassFromString(name);
    if (!cls) return NO;
    SEL selector = @selector(viewDidAppear:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return NO;

    LTOriginalViewDidAppear = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    // If the method is inherited, add an override on the lock-screen class only.
    // If it already exists on that class, replace just that implementation.
    if (!class_addMethod(cls, selector, (IMP)LTViewDidAppearReplacement, types)) {
        Method ownMethod = class_getInstanceMethod(cls, selector);
        LTOriginalViewDidAppear = method_setImplementation(ownMethod, (IMP)LTViewDidAppearReplacement);
    }
    LTHookedControllerClass = cls;
    LTLog(@"Hooked %@ viewDidAppear:", name);
    return YES;
}

static void LTFindAndAttachInController(UIViewController *controller) {
    if (!controller) return;
    if (LTHookedControllerClass && [controller isKindOfClass:LTHookedControllerClass]) {
        LTInstallWallpaperOnController(controller);
    }
    for (UIViewController *child in controller.childViewControllers) LTFindAndAttachInController(child);
    if (controller.presentedViewController) LTFindAndAttachInController(controller.presentedViewController);
}

static void LTAttachToExistingController(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIWindow *window in app.windows) LTFindAndAttachInController(window.rootViewController);
}

static void LTTryInstallHooks(NSUInteger attempt) {
    if (LTHookedControllerClass) {
        LTAttachToExistingController();
        return;
    }
    if (LTHookControllerNamed(@"CSCoverSheetViewController") || LTHookControllerNamed(@"SBDashBoardViewController")) {
        LTAttachToExistingController();
        return;
    }
    if (attempt < 20) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LTTryInstallHooks(attempt + 1);
        });
    } else {
        LTLog(@"FAILED: lock-screen controller class not found after retries");
    }
}

__attribute__((constructor)) static void LiveTouchEngineInit(void) {
    @autoreleasepool {
        LTLog(@"LiveTouchEngine 0.1.6 loaded into %@ pid=%d", NSProcessInfo.processInfo.processName, getpid());
        dispatch_async(dispatch_get_main_queue(), ^{ LTTryInstallHooks(0); });
    }
}
