#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Local-only notification presentation for the user's own device.
// Notification text is never written to disk or transmitted anywhere.

@interface SBSystemApertureWindow : UIWindow
@end

static NSString * const NANPrefsDomain = @"com.nextsolution.unlockvibrate";
static NSString * const NANPrefsChanged = @"com.nextsolution.unlockvibrate/preferences.changed";
static NSString * const NANTestNotification = @"com.nextsolution.unlockvibrate/test-dynamic-island-suite";
static NSString * const NANDismissedKey = @"NotificationIslandDismissedFingerprints";

static __weak SBSystemApertureWindow *NANSystemWindow = nil;
static UIView *NANIslandView = nil;
static NSDictionary *NANCurrentModel = nil;
static __weak UIViewController *NANCurrentShortLook = nil;
static NSMutableOrderedSet<NSString *> *NANSeenFingerprints = nil;
static NSTimer *NANHideTimer = nil;
static NSTimer *NANPrivacyTimer = nil;
static BOOL NANExpanded = NO;
static BOOL NANTestMode = NO;

static id NANPreference(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)NANPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NANPrefsDomain);
    return CFBridgingRelease(value);
}

static BOOL NANBool(NSString *key, BOOL fallback) {
    id value = NANPreference(key);
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

static CGFloat NANFloat(NSString *key, CGFloat fallback, CGFloat minimum, CGFloat maximum) {
    id value = NANPreference(key);
    CGFloat result = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return MIN(MAX(result, minimum), maximum);
}

static id NANSafeValue(id object, NSString *key) {
    if (!object || !key.length) return nil;
    @try { return [object valueForKey:key]; }
    @catch (__unused NSException *exception) { return nil; }
}

static NSString *NANString(id object, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        id value = NANSafeValue(object, key);
        if ([value isKindOfClass:NSString.class]) {
            NSString *text = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (text.length) return text;
        }
    }
    return @"";
}

static BOOL NANIsUILocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    id manager = nil;
    SEL shared = NSSelectorFromString(@"sharedInstance");
    SEL sharedAlt = NSSelectorFromString(@"_sharedInstance");
    if (cls && [cls respondsToSelector:shared]) manager = ((id(*)(id,SEL))objc_msgSend)(cls, shared);
    else if (cls && [cls respondsToSelector:sharedAlt]) manager = ((id(*)(id,SEL))objc_msgSend)(cls, sharedAlt);
    SEL locked = NSSelectorFromString(@"isUILocked");
    if (manager && [manager respondsToSelector:locked]) return ((BOOL(*)(id,SEL))objc_msgSend)(manager, locked);
    return !UIApplication.sharedApplication.isProtectedDataAvailable;
}

static NSString *NANApplicationName(NSString *bundleID) {
    if (!bundleID.length) return @"Notification";
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL selector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = nil;
    if (proxyClass && [proxyClass respondsToSelector:selector]) {
        proxy = ((id(*)(id,SEL,id))objc_msgSend)(proxyClass, selector, bundleID);
    }
    NSString *name = NANString(proxy, @[@"localizedName", @"localizedShortName"]);
    return name.length ? name : bundleID;
}

static UIImage *NANApplicationIcon(NSString *bundleID) {
    if (!bundleID.length) return [UIImage systemImageNamed:@"bell.fill"];
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL selector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = nil;
    if (proxyClass && [proxyClass respondsToSelector:selector]) {
        proxy = ((id(*)(id,SEL,id))objc_msgSend)(proxyClass, selector, bundleID);
    }
    SEL iconSelector = NSSelectorFromString(@"iconDataForVariant:");
    if (proxy && [proxy respondsToSelector:iconSelector]) {
        for (NSInteger variant = 2; variant >= 0; variant--) {
            NSData *data = ((id(*)(id,SEL,NSInteger))objc_msgSend)(proxy, iconSelector, variant);
            if ([data isKindOfClass:NSData.class] && data.length) {
                UIImage *image = [UIImage imageWithData:data];
                if (image) return image;
            }
        }
    }
    return [UIImage systemImageNamed:@"bell.fill"];
}

static NSString *NANDateText(NSDate *date) {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.dateFormat = @"h:mm a";
    });
    return [formatter stringFromDate:date ?: NSDate.date] ?: @"Now";
}

static NSString *NANFingerprint(NSDictionary *model) {
    return [model[@"fingerprint"] isKindOfClass:NSString.class] ? model[@"fingerprint"] : @"";
}

static NSDictionary *NANDismissedFingerprints(void) {
    id value = NANPreference(NANDismissedKey);
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

static BOOL NANWasDismissed(NSString *fingerprint) {
    if (!fingerprint.length) return NO;
    return [NANDismissedFingerprints()[fingerprint] boolValue];
}

static void NANMarkDismissed(NSString *fingerprint) {
    if (!fingerprint.length) return;
    NSMutableDictionary *saved = [NANDismissedFingerprints() mutableCopy];
    saved[fingerprint] = @YES;
    if (saved.count > 250) {
        NSArray *keys = saved.allKeys;
        NSUInteger remove = saved.count - 200;
        for (NSUInteger index = 0; index < remove && index < keys.count; index++) [saved removeObjectForKey:keys[index]];
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)NANDismissedKey, (__bridge CFPropertyListRef)saved, (__bridge CFStringRef)NANPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)NANPrefsDomain);
}

static CGRect NANFrame(BOOL expanded) {
    CGFloat screenWidth = UIScreen.mainScreen.bounds.size.width;
    CGFloat width = expanded
        ? NANFloat(@"NotificationIslandExpandedWidth", MIN(screenWidth - 18.0, 405.0), 270.0, MAX(270.0, screenWidth - 8.0))
        : NANFloat(@"NotificationIslandCompactWidth", MIN(screenWidth - 32.0, 330.0), 190.0, MAX(190.0, screenWidth - 8.0));
    CGFloat height = expanded
        ? NANFloat(@"NotificationIslandExpandedHeight", 150.0, 105.0, 240.0)
        : NANFloat(@"NotificationIslandCompactHeight", 68.0, 48.0, 110.0);
    CGFloat y = expanded
        ? NANFloat(@"NotificationIslandExpandedY", 48.0, -10.0, 220.0)
        : NANFloat(@"NotificationIslandCompactY", 48.0, -10.0, 140.0);
    CGFloat offset = NANFloat(@"NotificationIslandHorizontalOffset", 0.0, -140.0, 140.0);
    CGFloat x = ((screenWidth - width) / 2.0) + offset;
    x = MIN(MAX(x, 4.0), MAX(4.0, screenWidth - width - 4.0));
    return CGRectMake(x, y, width, height);
}

static void NANRemoveIsland(void);
static void NANPresentModel(NSDictionary *model, UIViewController *shortLook);

@interface NANNotificationCard : UIControl
@property(nonatomic,strong) UIImageView *iconView;
@property(nonatomic,strong) UILabel *appLabel;
@property(nonatomic,strong) UILabel *timeLabel;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *bodyLabel;
@property(nonatomic,strong) UIButton *openButton;
@property(nonatomic,strong) UIButton *dismissButton;
@property(nonatomic,copy) NSString *bundleID;
@property(nonatomic,copy) NSString *fingerprint;
- (void)applyModel:(NSDictionary *)model;
- (void)applyPrivacy;
- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated;
@end

@implementation NANNotificationCard
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.blackColor;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.clipsToBounds = YES;

    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFill;
    _iconView.layer.cornerRadius = 9;
    _iconView.clipsToBounds = YES;

    _appLabel = [UILabel new];
    _appLabel.textColor = UIColor.whiteColor;
    _appLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _appLabel.numberOfLines = 1;

    _timeLabel = [UILabel new];
    _timeLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.58];
    _timeLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    _timeLabel.textAlignment = NSTextAlignmentRight;

    _titleLabel = [UILabel new];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _titleLabel.numberOfLines = 1;

    _bodyLabel = [UILabel new];
    _bodyLabel.textColor = [UIColor.whiteColor colorWithAlphaComponent:0.82];
    _bodyLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _bodyLabel.numberOfLines = 2;

    _openButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_openButton setTitle:@"Open" forState:UIControlStateNormal];
    [_openButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _openButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _openButton.backgroundColor = UIColor.systemBlueColor;
    _openButton.layer.cornerRadius = 11;
    [_openButton addTarget:self action:@selector(openTapped) forControlEvents:UIControlEventTouchUpInside];

    _dismissButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_dismissButton setTitle:@"Dismiss" forState:UIControlStateNormal];
    [_dismissButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _dismissButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    _dismissButton.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    _dismissButton.layer.cornerRadius = 11;
    [_dismissButton addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];

    for (UIView *view in @[_iconView,_appLabel,_timeLabel,_titleLabel,_bodyLabel,_openButton,_dismissButton]) [self addSubview:view];

    [self addTarget:self action:@selector(cardTapped) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    longPress.minimumPressDuration = 0.35;
    [self addGestureRecognizer:longPress];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);
    CGFloat pad = 11;
    CGFloat icon = NANExpanded ? 38 : 34;
    self.iconView.frame = CGRectMake(pad, (self.bounds.size.height - icon) / 2.0, icon, icon);

    CGFloat textX = CGRectGetMaxX(self.iconView.frame) + 9;
    CGFloat right = 10;
    CGFloat timeWidth = 58;
    self.timeLabel.frame = CGRectMake(self.bounds.size.width - right - timeWidth, 8, timeWidth, 16);
    self.appLabel.frame = CGRectMake(textX, 7, MAX(40, self.bounds.size.width - textX - timeWidth - 18), 18);
    self.appLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];

    if (NANExpanded) {
        CGFloat buttonHeight = 38;
        CGFloat buttonY = self.bounds.size.height - buttonHeight - 10;
        CGFloat available = self.bounds.size.width - textX - right;
        self.titleLabel.frame = CGRectMake(textX, 29, available, 19);
        self.bodyLabel.frame = CGRectMake(textX, 49, available, MAX(28, buttonY - 53));
        CGFloat buttonWidth = (self.bounds.size.width - 30) / 2.0;
        self.openButton.frame = CGRectMake(10, buttonY, buttonWidth, buttonHeight);
        self.dismissButton.frame = CGRectMake(CGRectGetMaxX(self.openButton.frame) + 10, buttonY, buttonWidth, buttonHeight);
        self.titleLabel.hidden = NO;
        self.openButton.hidden = NO;
        self.dismissButton.hidden = NO;
        self.bodyLabel.numberOfLines = 3;
    } else {
        self.titleLabel.hidden = YES;
        self.openButton.hidden = YES;
        self.dismissButton.hidden = YES;
        self.bodyLabel.frame = CGRectMake(textX, 27, MAX(40, self.bounds.size.width - textX - right), self.bounds.size.height - 31);
        self.bodyLabel.numberOfLines = 1;
    }
    self.titleLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];
    self.bodyLabel.font = [UIFont systemFontOfSize:12 * scale weight:UIFontWeightRegular];
}

- (void)applyModel:(NSDictionary *)model {
    self.bundleID = [model[@"bundleID"] isKindOfClass:NSString.class] ? model[@"bundleID"] : @"";
    self.fingerprint = NANFingerprint(model);
    self.iconView.image = NANApplicationIcon(self.bundleID);
    self.appLabel.text = [model[@"appName"] isKindOfClass:NSString.class] ? model[@"appName"] : @"Notification";
    self.timeLabel.text = [model[@"time"] isKindOfClass:NSString.class] ? model[@"time"] : @"Now";
    [self applyPrivacy];
}

- (void)applyPrivacy {
    NSDictionary *model = NANCurrentModel;
    BOOL locked = NANIsUILocked();
    NSString *title = [model[@"title"] isKindOfClass:NSString.class] ? model[@"title"] : @"";
    NSString *body = [model[@"body"] isKindOfClass:NSString.class] ? model[@"body"] : @"";
    if (locked) {
        self.titleLabel.text = @"Notification";
        self.bodyLabel.text = @"Content hidden while locked";
    } else {
        self.titleLabel.text = title.length ? title : self.appLabel.text;
        self.bodyLabel.text = body.length ? body : (title.length ? title : @"New notification");
    }
}

- (void)setExpanded:(BOOL)expanded animated:(BOOL)animated {
    NANExpanded = expanded;
    CGRect frame = NANFrame(expanded);
    void (^changes)(void) = ^{
        self.frame = frame;
        self.layer.cornerRadius = MAX(18.0, MIN(frame.size.height / 2.0, expanded ? 30.0 : 28.0));
        [self setNeedsLayout];
        [self layoutIfNeeded];
    };
    if (animated) {
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.12 options:UIViewAnimationOptionCurveEaseInOut animations:changes completion:nil];
    } else changes();
}

- (void)cardTapped {
    if (!NANExpanded) {
        [self setExpanded:YES animated:YES];
        [NANHideTimer invalidate];
        NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:NO block:^(__unused NSTimer *timer) { NANRemoveIsland(); }];
    }
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) [self setExpanded:!NANExpanded animated:YES];
}

- (void)openTapped {
    if (NANTestMode) { NANTestMode = NO; NANRemoveIsland(); return; }
    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);
    if (self.bundleID.length) {
        Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
        SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");
        id workspace = (workspaceClass && [workspaceClass respondsToSelector:defaultSelector]) ? ((id(*)(id,SEL))objc_msgSend)(workspaceClass, defaultSelector) : nil;
        SEL openSelector = NSSelectorFromString(@"openApplicationWithBundleID:");
        if (workspace && [workspace respondsToSelector:openSelector]) ((BOOL(*)(id,SEL,id))objc_msgSend)(workspace, openSelector, self.bundleID);
    }
    NANRemoveIsland();
}

- (void)dismissTapped {
    if (NANTestMode) { NANTestMode = NO; NANRemoveIsland(); return; }
    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);
    UIViewController *shortLook = NANCurrentShortLook;
    if (shortLook) {
        dispatch_async(dispatch_get_main_queue(), ^{
            shortLook.view.hidden = YES;
            shortLook.view.alpha = 0.0;
        });
    }
    NANRemoveIsland();
}
@end

static void NANRemoveIslandOnMain(void) {
    [NANHideTimer invalidate]; NANHideTimer = nil;
    [NANPrivacyTimer invalidate]; NANPrivacyTimer = nil;
    [NANIslandView removeFromSuperview];
    NANIslandView = nil;
    NANCurrentModel = nil;
    NANCurrentShortLook = nil;
    NANExpanded = NO;
}

static void NANRemoveIsland(void) {
    if (NSThread.isMainThread) NANRemoveIslandOnMain();
    else dispatch_async(dispatch_get_main_queue(), ^{ NANRemoveIslandOnMain(); });
}

static void NANStartTimers(void) {
    [NANHideTimer invalidate];
    NSTimeInterval duration = NANFloat(@"NotificationIslandDuration", 6.0, 2.0, 20.0);
    NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(__unused NSTimer *timer) { NANRemoveIsland(); }];
    [NANPrivacyTimer invalidate];
    NANPrivacyTimer = [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:YES block:^(__unused NSTimer *timer) {
        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) [(NANNotificationCard *)NANIslandView applyPrivacy];
    }];
}

static void NANPresentModel(NSDictionary *model, UIViewController *shortLook) {
    if (!NANBool(@"NotificationIslandEnabled", YES) || !model || !NANSystemWindow) return;
    NSString *fingerprint = NANFingerprint(model);
    if (!NANTestMode && (NANWasDismissed(fingerprint) || [NANSeenFingerprints containsObject:fingerprint])) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NANTestMode && fingerprint.length) {
            [NANSeenFingerprints addObject:fingerprint];
            while (NANSeenFingerprints.count > 200) [NANSeenFingerprints removeObjectAtIndex:0];
        }
        NANRemoveIslandOnMain();
        NANCurrentModel = model;
        NANCurrentShortLook = shortLook;

        NANNotificationCard *card = [[NANNotificationCard alloc] initWithFrame:CGRectZero];
        [NANSystemWindow addSubview:card];
        NANIslandView = card;
        [card applyModel:model];
        [card setExpanded:NO animated:NO];
        NANSystemWindow.userInteractionEnabled = YES;
        [NANSystemWindow bringSubviewToFront:card];
        NANStartTimers();

        if (NANBool(@"NotificationIslandReplaceStockBanner", YES) && shortLook) {
            shortLook.view.alpha = 0.0;
            shortLook.view.userInteractionEnabled = NO;
        }
    });
}

static NSDictionary *NANModelForRequest(id request) {
    if (!request) return nil;
    NSString *bundleID = NANString(request, @[@"sectionIdentifier", @"_sectionIdentifier"]);
    id content = NANSafeValue(request, @"content");
    NSString *title = NANString(content, @[@"title", @"header", @"primaryText"]);
    NSString *body = NANString(content, @[@"message", @"body", @"secondaryText", @"summary"]);
    NSString *identifier = NANString(request, @[@"notificationIdentifier", @"requestIdentifier", @"identifier"]);
    NSDate *timestamp = NANSafeValue(request, @"timestamp");
    if (![timestamp isKindOfClass:NSDate.class]) timestamp = NANSafeValue(request, @"date");
    if (![timestamp isKindOfClass:NSDate.class]) timestamp = NSDate.date;
    if (!identifier.length) identifier = [NSString stringWithFormat:@"%.0f", timestamp.timeIntervalSince1970 * 1000.0];
    NSString *fingerprint = [NSString stringWithFormat:@"%@|%@", bundleID ?: @"", identifier];
    return @{
        @"bundleID": bundleID ?: @"",
        @"appName": NANApplicationName(bundleID),
        @"title": title ?: @"",
        @"body": body ?: @"",
        @"time": NANDateText(timestamp),
        @"fingerprint": fingerprint
    };
}

static void NANPreferencesChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!NANBool(@"NotificationIslandEnabled", YES)) { NANRemoveIsland(); return; }
        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) {
            [(NANNotificationCard *)NANIslandView setExpanded:NANExpanded animated:NO];
            [(NANNotificationCard *)NANIslandView applyPrivacy];
        }
    });
}

static void NANTest(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NANTestMode = YES;
        NSString *identifier = [NSString stringWithFormat:@"test-%.0f", NSDate.date.timeIntervalSince1970 * 1000.0];
        NSDictionary *sample = @{
            @"bundleID": @"com.apple.MobileSMS",
            @"appName": @"Messages",
            @"title": @"Test Notification",
            @"body": @"Move the size and position sliders while this preview is visible. Tap to expand.",
            @"time": NANDateText(NSDate.date),
            @"fingerprint": identifier
        };
        NANPresentModel(sample, nil);
        [NANHideTimer invalidate];
        NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 repeats:NO block:^(__unused NSTimer *timer) { NANTestMode = NO; NANRemoveIsland(); }];
    });
}

%hook SBSystemApertureWindow
- (void)didMoveToScreen:(UIScreen *)screen {
    %orig;
    NANSystemWindow = self;
}
- (void)layoutSubviews {
    %orig;
    NANSystemWindow = self;
    if (NANIslandView.superview == self) [self bringSubviewToFront:NANIslandView];
}
%end

%hook NCNotificationShortLookViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    id request = NANSafeValue(self, @"notificationRequest");
    NSDictionary *model = NANModelForRequest(request);
    if (model) NANPresentModel(model, self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (NANBool(@"NotificationIslandReplaceStockBanner", YES) && NANCurrentShortLook == self) {
        self.view.alpha = 0.0;
        self.view.userInteractionEnabled = NO;
    }
}
%end

__attribute__((constructor)) static void NANInit(void) {
    @autoreleasepool {
        NANSeenFingerprints = [NSMutableOrderedSet orderedSet];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NANPreferencesChanged, (__bridge CFStringRef)NANPrefsChanged, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NANTest, (__bridge CFStringRef)NANTestNotification, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[NextAura] Notification Island 4.4.9 loaded; local-only content, locked content protected");
    }
}
