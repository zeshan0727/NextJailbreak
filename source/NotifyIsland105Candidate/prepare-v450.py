#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parent
path = root / 'NotificationIsland.xm'
s = path.read_text()

# Add helper for preset enums + an explicit auto-dismiss preference.
old = '''static CGFloat NANFloat(NSString *key, CGFloat fallback, CGFloat minimum, CGFloat maximum) {\n    id value = NANPreference(key);\n    CGFloat result = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;\n    return MIN(MAX(result, minimum), maximum);\n}\n'''
new = old + '''\nstatic NSInteger NANInteger(NSString *key, NSInteger fallback, NSInteger minimum, NSInteger maximum) {\n    id value = NANPreference(key);\n    NSInteger result = [value isKindOfClass:NSNumber.class] ? [value integerValue] : fallback;\n    return MIN(MAX(result, minimum), maximum);\n}\n\nstatic NSTimeInterval NANDismissInterval(void) {\n    id modern = NANPreference(@"NotificationIslandDismissTime");\n    if ([modern isKindOfClass:NSNumber.class]) return MIN(MAX([modern doubleValue], 2.0), 30.0);\n    return NANFloat(@"NotificationIslandDuration", 6.0, 2.0, 30.0);\n}\n'''
if 'static NSInteger NANInteger' not in s:
    if old not in s:
        raise SystemExit('NANFloat helper anchor missing')
    s = s.replace(old, new, 1)

# Resolve the installed app icon first; never use a bell as the fallback.
start = s.index('static UIImage *NANApplicationIcon(NSString *bundleID) {')
end = s.index('\nstatic NSString *NANDateText', start)
icon_func = r'''static UIImage *NANApplicationIcon(NSString *bundleID) {
    if (!bundleID.length) return [UIImage systemImageNamed:@"app.fill"];

    SEL uiIconSelector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if ([UIImage respondsToSelector:uiIconSelector]) {
        CGFloat scale = UIScreen.mainScreen.scale ?: 3.0;
        for (NSInteger format = 2; format >= 0; format--) {
            UIImage *image = ((id(*)(id,SEL,id,NSInteger,CGFloat))objc_msgSend)(UIImage.class, uiIconSelector, bundleID, format, scale);
            if ([image isKindOfClass:UIImage.class] && image.size.width > 1.0) return image;
        }
    }

    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    SEL proxySelector = NSSelectorFromString(@"applicationProxyForIdentifier:");
    id proxy = nil;
    if (proxyClass && [proxyClass respondsToSelector:proxySelector]) {
        proxy = ((id(*)(id,SEL,id))objc_msgSend)(proxyClass, proxySelector, bundleID);
    }
    SEL imageSelector = NSSelectorFromString(@"iconImageForVariant:");
    if (proxy && [proxy respondsToSelector:imageSelector]) {
        for (NSInteger variant = 2; variant >= 0; variant--) {
            UIImage *image = ((id(*)(id,SEL,NSInteger))objc_msgSend)(proxy, imageSelector, variant);
            if ([image isKindOfClass:UIImage.class] && image.size.width > 1.0) return image;
        }
    }
    SEL dataSelector = NSSelectorFromString(@"iconDataForVariant:");
    if (proxy && [proxy respondsToSelector:dataSelector]) {
        for (NSInteger variant = 2; variant >= 0; variant--) {
            NSData *data = ((id(*)(id,SEL,NSInteger))objc_msgSend)(proxy, dataSelector, variant);
            if ([data isKindOfClass:NSData.class] && data.length) {
                UIImage *image = [UIImage imageWithData:data];
                if (image) return image;
            }
        }
    }

    UIImage *fallback = [UIImage systemImageNamed:@"app.fill"];
    return [fallback imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
'''
s = s[:start] + icon_func + s[end:]

# Appearance layers live behind the content.
if '@property(nonatomic,strong) UIVisualEffectView *backgroundEffectView;' not in s:
    s = s.replace('@property(nonatomic,strong) UIImageView *iconView;', '@property(nonatomic,strong) UIVisualEffectView *backgroundEffectView;\n@property(nonatomic,strong) UIView *backgroundTintView;\n@property(nonatomic,strong) UIImageView *iconView;', 1)
if '- (void)applyAppearance;' not in s:
    s = s.replace('- (void)applyPrivacy;\n- (void)setExpanded:', '- (void)applyPrivacy;\n- (void)applyAppearance;\n- (void)setExpanded:', 1)

old = '''    self.backgroundColor = UIColor.blackColor;\n    self.layer.cornerCurve = kCACornerCurveContinuous;\n    self.clipsToBounds = YES;\n\n    _iconView = [UIImageView new];\n'''
new = '''    self.backgroundColor = UIColor.clearColor;\n    self.layer.cornerCurve = kCACornerCurveContinuous;\n    self.clipsToBounds = YES;\n\n    _backgroundEffectView = [[UIVisualEffectView alloc] initWithEffect:nil];\n    _backgroundEffectView.userInteractionEnabled = NO;\n    [self addSubview:_backgroundEffectView];\n\n    _backgroundTintView = [UIView new];\n    _backgroundTintView.userInteractionEnabled = NO;\n    [self addSubview:_backgroundTintView];\n\n    _iconView = [UIImageView new];\n'''
if old in s:
    s = s.replace(old, new, 1)

# Keep one visual layer per action button. UIButtonConfiguration was drawing a
# second inner capsule and could initially offset the title until first touch.
old = '''    longPress.minimumPressDuration = 0.35;\n    [self addGestureRecognizer:longPress];\n    return self;\n}\n'''
new = '''    longPress.minimumPressDuration = 0.35;\n    [self addGestureRecognizer:longPress];\n\n    if (@available(iOS 15.0, *)) {\n        self.openButton.configuration = nil;\n        self.dismissButton.configuration = nil;\n    }\n    [self.openButton setTitle:@"Open" forState:UIControlStateNormal];\n    [self.dismissButton setTitle:@"Dismiss" forState:UIControlStateNormal];\n    self.openButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;\n    self.openButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;\n    self.dismissButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;\n    self.dismissButton.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;\n    self.openButton.titleLabel.textAlignment = NSTextAlignmentCenter;\n    self.dismissButton.titleLabel.textAlignment = NSTextAlignmentCenter;\n    self.openButton.titleEdgeInsets = UIEdgeInsetsZero;\n    self.dismissButton.titleEdgeInsets = UIEdgeInsetsZero;\n    self.openButton.contentEdgeInsets = UIEdgeInsetsZero;\n    self.dismissButton.contentEdgeInsets = UIEdgeInsetsZero;\n    self.openButton.backgroundColor = UIColor.systemBlueColor;\n    self.dismissButton.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];\n    self.openButton.layer.cornerRadius = 11.0;\n    self.dismissButton.layer.cornerRadius = 11.0;\n    self.openButton.clipsToBounds = YES;\n    self.dismissButton.clipsToBounds = YES;\n    [self applyAppearance];\n    return self;\n}\n'''
if old in s:
    s = s.replace(old, new, 1)

old = '''- (void)layoutSubviews {\n    [super layoutSubviews];\n    CGFloat scale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);\n'''
new = '''- (void)layoutSubviews {\n    [super layoutSubviews];\n    self.backgroundEffectView.frame = self.bounds;\n    self.backgroundTintView.frame = self.bounds;\n    CGFloat scale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);\n'''
if old in s:
    s = s.replace(old, new, 1)

old_buttons = '''        self.openButton.frame = CGRectMake(10, buttonY, buttonWidth, buttonHeight);\n        self.dismissButton.frame = CGRectMake(CGRectGetMaxX(self.openButton.frame) + 10, buttonY, buttonWidth, buttonHeight);\n        self.titleLabel.hidden = NO;\n'''
new_buttons = '''        self.openButton.frame = CGRectMake(10, buttonY, buttonWidth, buttonHeight);\n        self.dismissButton.frame = CGRectMake(CGRectGetMaxX(self.openButton.frame) + 10, buttonY, buttonWidth, buttonHeight);\n        self.openButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;\n        self.dismissButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;\n        self.openButton.titleLabel.textAlignment = NSTextAlignmentCenter;\n        self.dismissButton.titleLabel.textAlignment = NSTextAlignmentCenter;\n        [self.openButton setNeedsLayout];\n        [self.dismissButton setNeedsLayout];\n        self.titleLabel.hidden = NO;\n'''
if old_buttons in s:
    s = s.replace(old_buttons, new_buttons, 1)

if '- (void)applyAppearance {' not in s:
    anchor = '- (void)applyModel:(NSDictionary *)model {\n'
    appearance = r'''- (void)applyAppearance {
    NSInteger mode = NANInteger(@"NotificationIslandAppearanceMode", 0, 0, 3);
    CGFloat strength = NANFloat(@"NotificationIslandBlurStrength", 0.55, 0.20, 1.00);
    CGFloat opacity = NANFloat(@"NotificationIslandBackgroundOpacity", 0.98, 0.55, 1.00);

    self.backgroundEffectView.hidden = (mode == 0);
    self.backgroundTintView.hidden = NO;

    if (mode == 0) {
        self.backgroundEffectView.effect = nil;
        self.backgroundTintView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:opacity];
    } else {
        BOOL light = (mode == 2);
        UIBlurEffectStyle style;
        if (mode == 3) {
            style = UIBlurEffectStyleSystemUltraThinMaterialDark;
        } else if (strength < 0.40) {
            style = light ? UIBlurEffectStyleSystemUltraThinMaterialLight : UIBlurEffectStyleSystemUltraThinMaterialDark;
        } else if (strength < 0.75) {
            style = light ? UIBlurEffectStyleSystemThinMaterialLight : UIBlurEffectStyleSystemThinMaterialDark;
        } else {
            style = light ? UIBlurEffectStyleSystemChromeMaterialLight : UIBlurEffectStyleSystemChromeMaterialDark;
        }
        self.backgroundEffectView.effect = [UIBlurEffect effectWithStyle:style];
        if (mode == 3) {
            self.backgroundTintView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.18 * opacity];
        } else if (light) {
            self.backgroundTintView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10 * opacity];
        } else {
            self.backgroundTintView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:(0.16 + (0.16 * strength)) * opacity];
        }
    }
}

'''
    if anchor not in s:
        raise SystemExit('applyModel anchor missing')
    s = s.replace(anchor, appearance + anchor, 1)

s = s.replace('''    self.timeLabel.text = [model[@"time"] isKindOfClass:NSString.class] ? model[@"time"] : @"Now";\n    [self applyPrivacy];\n''', '''    self.timeLabel.text = [model[@"time"] isKindOfClass:NSString.class] ? model[@"time"] : @"Now";\n    [self applyAppearance];\n    [self applyPrivacy];\n''', 1)

s = s.replace('''        self.layer.cornerRadius = MAX(18.0, MIN(frame.size.height / 2.0, expanded ? 30.0 : 28.0));\n        [self setNeedsLayout];\n''', '''        self.layer.cornerRadius = MAX(18.0, MIN(frame.size.height / 2.0, expanded ? 30.0 : 28.0));\n        [self applyAppearance];\n        [self setNeedsLayout];\n''', 1)

s = s.replace('NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:NO block:^(__unused NSTimer *timer) { NANRemoveIsland(); }];', 'NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:NANDismissInterval() repeats:NO block:^(__unused NSTimer *timer) { NANRemoveIsland(); }];', 1)
s = s.replace('NSTimeInterval duration = NANFloat(@"NotificationIslandDuration", 6.0, 2.0, 20.0);', 'NSTimeInterval duration = NANDismissInterval();', 1)

old = '''        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) {\n            [(NANNotificationCard *)NANIslandView setExpanded:NANExpanded animated:NO];\n            [(NANNotificationCard *)NANIslandView applyPrivacy];\n        }\n'''
new = '''        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) {\n            NANNotificationCard *card = (NANNotificationCard *)NANIslandView;\n            [card setExpanded:NANExpanded animated:NO];\n            [card applyAppearance];\n            [card applyPrivacy];\n            [NANHideTimer invalidate];\n            NANHideTimer = [NSTimer scheduledTimerWithTimeInterval:NANDismissInterval() repeats:NO block:^(__unused NSTimer *timer) { NANRemoveIsland(); }];\n        }\n'''
if old in s:
    s = s.replace(old, new, 1)

s = s.replace('Move the size and position sliders while this preview is visible. Tap to expand.', 'Change the style, size, position or dismiss-time controls while this preview is visible. Tap to expand.', 1)
s = s.replace('Notification Island 4.4.9 loaded; local-only content, locked content protected', 'Notification Island 4.5.1 loaded; stable centered action-button titles', 1)

path.write_text(s)
print('Prepared NextAura Notification Island 4.5.1.')
