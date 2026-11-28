#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <math.h>

static CFStringRef const MGPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const MGVolumeIconColorKey = CFSTR("CCModuleVolumeIconColor");
static CFStringRef const MGVolumeIconColorEnabledKey = CFSTR("CCModuleVolumeIconColorEnabled");
static const void *MGPickerDelegateKey = &MGPickerDelegateKey;
static const NSInteger MGBrandHeaderTag = 0x4D473119;

static UIColor *MGBrandColor(NSUInteger rgb, CGFloat alpha) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:alpha];
}

@interface MGBrandHeaderView : UIView
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UIView *iconPlate;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *brandLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *versionLabel;
@property (nonatomic, strong) UIView *accentLine;
@end

@implementation MGBrandHeaderView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.backgroundColor = UIColor.clearColor;
    self.tag = MGBrandHeaderTag;

    _card = [UIView new];
    _card.layer.cornerRadius = 22.0;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _card.layer.borderColor = MGBrandColor(0x6CF58C, 0.34).CGColor;
    _card.layer.shadowColor = UIColor.blackColor.CGColor;
    _card.layer.shadowOpacity = 0.28;
    _card.layer.shadowRadius = 18.0;
    _card.layer.shadowOffset = CGSizeMake(0.0, 10.0);
    _card.clipsToBounds = NO;
    [self addSubview:_card];

    _gradient = [CAGradientLayer layer];
    _gradient.colors = @[
        (__bridge id)MGBrandColor(0x07100B, 1.0).CGColor,
        (__bridge id)MGBrandColor(0x11172A, 1.0).CGColor,
        (__bridge id)MGBrandColor(0x080A0E, 1.0).CGColor,
    ];
    _gradient.locations = @[@0.0, @0.55, @1.0];
    _gradient.startPoint = CGPointMake(0.0, 0.0);
    _gradient.endPoint = CGPointMake(1.0, 1.0);
    _gradient.cornerRadius = 22.0;
    [_card.layer insertSublayer:_gradient atIndex:0];

    _iconPlate = [UIView new];
    _iconPlate.backgroundColor = MGBrandColor(0xFFFFFF, 0.08);
    _iconPlate.layer.cornerRadius = 17.0;
    _iconPlate.layer.cornerCurve = kCACornerCurveContinuous;
    _iconPlate.layer.borderWidth = 1.0;
    _iconPlate.layer.borderColor = MGBrandColor(0x6CF58C, 0.52).CGColor;
    _iconPlate.layer.shadowColor = MGBrandColor(0x6CF58C, 1.0).CGColor;
    _iconPlate.layer.shadowOpacity = 0.38;
    _iconPlate.layer.shadowRadius = 13.0;
    _iconPlate.layer.shadowOffset = CGSizeZero;
    [_card addSubview:_iconPlate];

    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:28.0 weight:UIImageSymbolWeightSemibold];
    UIImage *icon = [UIImage systemImageNamed:@"square.grid.2x2.fill" withConfiguration:configuration];
    _iconView = [[UIImageView alloc] initWithImage:icon];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = MGBrandColor(0x71F994, 1.0);
    [_iconPlate addSubview:_iconView];

    _brandLabel = [UILabel new];
    _brandLabel.text = @"NEXT JAILBREAK";
    _brandLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightBold];
    _brandLabel.textColor = MGBrandColor(0x71F994, 1.0);
    _brandLabel.accessibilityLabel = @"Next Jailbreak";
    [_card addSubview:_brandLabel];

    _titleLabel = [UILabel new];
    _titleLabel.text = @"Module Glass";
    _titleLabel.font = [UIFont systemFontOfSize:27.0 weight:UIFontWeightBold];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.82;
    [_card addSubview:_titleLabel];

    _subtitleLabel = [UILabel new];
    _subtitleLabel.text = @"Premium Control Center styling";
    _subtitleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    _subtitleLabel.textColor = MGBrandColor(0xD5DBE7, 0.82);
    [_card addSubview:_subtitleLabel];

    _versionLabel = [UILabel new];
    _versionLabel.text = @"1.1.21  •  iOS 16+";
    _versionLabel.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightSemibold];
    _versionLabel.textAlignment = NSTextAlignmentCenter;
    _versionLabel.textColor = MGBrandColor(0xDDFDE5, 0.94);
    _versionLabel.backgroundColor = MGBrandColor(0x6CF58C, 0.13);
    _versionLabel.layer.cornerRadius = 10.0;
    _versionLabel.layer.masksToBounds = YES;
    [_card addSubview:_versionLabel];

    _accentLine = [UIView new];
    _accentLine.backgroundColor = MGBrandColor(0x6CF58C, 0.88);
    _accentLine.layer.cornerRadius = 1.5;
    [_card addSubview:_accentLine];

    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"Module Glass by Next Jailbreak. Premium Control Center styling. Version 1.1.21.";
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat cardX = 16.0;
    CGFloat cardWidth = MAX(0.0, width - cardX * 2.0);
    self.card.frame = CGRectMake(cardX, 10.0, cardWidth, 144.0);
    self.gradient.frame = self.card.bounds;

    self.iconPlate.frame = CGRectMake(18.0, 24.0, 62.0, 62.0);
    self.iconView.frame = CGRectInset(self.iconPlate.bounds, 15.0, 15.0);

    CGFloat textX = 96.0;
    CGFloat textWidth = MAX(0.0, cardWidth - textX - 18.0);
    self.brandLabel.frame = CGRectMake(textX, 20.0, textWidth, 16.0);
    self.titleLabel.frame = CGRectMake(textX, 39.0, textWidth, 34.0);
    self.subtitleLabel.frame = CGRectMake(textX, 75.0, textWidth, 19.0);

    self.accentLine.frame = CGRectMake(18.0, 109.0, 40.0, 3.0);
    self.versionLabel.frame = CGRectMake(68.0, 100.0, 142.0, 23.0);
}
@end

static NSString *MGHexFromColor(UIColor *color) {
    CGFloat r = 1.0, g = 1.0, b = 1.0, a = 1.0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 1.0;
        if ([color getWhite:&w alpha:&a]) r = g = b = w;
    }
    NSInteger ri = (NSInteger)llround(MAX(0.0, MIN(1.0, r)) * 255.0);
    NSInteger gi = (NSInteger)llround(MAX(0.0, MIN(1.0, g)) * 255.0);
    NSInteger bi = (NSInteger)llround(MAX(0.0, MIN(1.0, b)) * 255.0);
    return [NSString stringWithFormat:@"#%02lX%02lX%02lX", (long)ri, (long)gi, (long)bi];
}

static UIColor *MGColorFromHex(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return UIColor.whiteColor;
    NSString *hex = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6 && hex.length != 8) return UIColor.whiteColor;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&value]) return UIColor.whiteColor;
    CGFloat r, g, b, a = 1.0;
    if (hex.length == 8) {
        r = ((value >> 24) & 0xFF) / 255.0;
        g = ((value >> 16) & 0xFF) / 255.0;
        b = ((value >> 8) & 0xFF) / 255.0;
        a = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static NSString *MGStoredVolumeColor(void) {
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(MGVolumeIconColorKey, MGPrefsDomain);
    if (!value) return @"#FFFFFF";
    id bridged = CFBridgingRelease(value);
    return [bridged isKindOfClass:NSString.class] ? bridged : @"#FFFFFF";
}

static void MGSaveVolumeColor(UIColor *color) {
    NSString *hex = MGHexFromColor(color ?: UIColor.whiteColor);
    CFPreferencesSetAppValue(MGVolumeIconColorKey, (__bridge CFStringRef)hex, MGPrefsDomain);
    CFPreferencesSetAppValue(MGVolumeIconColorEnabledKey, kCFBooleanTrue, MGPrefsDomain);
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.nextsolution.unlockvibrate/preferences.changed"),
                                         NULL, NULL, true);
}

@interface MGVolumeColorPickerDelegate : NSObject <UIColorPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
@end

@implementation MGVolumeColorPickerDelegate
- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    MGSaveVolumeColor(viewController.selectedColor);
}
- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    MGSaveVolumeColor(viewController.selectedColor);
}
@end

static void MGChooseVolumeIconColor(id self, SEL _cmd, id specifier) {
    if (![self isKindOfClass:UIViewController.class]) return;
    UIViewController *presenter = (UIViewController *)self;
    UIColorPickerViewController *picker = [UIColorPickerViewController new];
    picker.title = @"Volume Icon Color";
    picker.supportsAlpha = NO;
    picker.selectedColor = MGColorFromHex(MGStoredVolumeColor());
    MGVolumeColorPickerDelegate *delegate = [MGVolumeColorPickerDelegate new];
    delegate.presenter = presenter;
    picker.delegate = delegate;
    objc_setAssociatedObject(picker, MGPickerDelegateKey, delegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:picker animated:YES completion:nil];
}

static void MGInstallVolumeColorAction(void) {
    Class cls = NSClassFromString(@"AuraCategoryListController");
    if (!cls) return;
    SEL selector = NSSelectorFromString(@"chooseVolumeIconColor:");
    if (!class_getInstanceMethod(cls, selector)) {
        class_addMethod(cls, selector, (IMP)MGChooseVolumeIconColor, "v@:@");
    }
}

static UITableView *MGFindTableView(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *subview in view.subviews) {
        UITableView *found = MGFindTableView(subview);
        if (found) return found;
    }
    return nil;
}

static UITableView *MGTableViewForController(id controller) {
    if ([controller isKindOfClass:UITableViewController.class]) {
        return ((UITableViewController *)controller).tableView;
    }
    SEL tableSelector = NSSelectorFromString(@"table");
    if ([controller respondsToSelector:tableSelector]) {
        id table = ((id (*)(id, SEL))objc_msgSend)(controller, tableSelector);
        if ([table isKindOfClass:UITableView.class]) return table;
    }
    if ([controller isKindOfClass:UIViewController.class]) {
        return MGFindTableView(((UIViewController *)controller).view);
    }
    return nil;
}

static BOOL MGIsModuleGlassRootController(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) return NO;
    UIViewController *viewController = (UIViewController *)controller;
    NSString *title = viewController.navigationItem.title ?: viewController.title;
    return [title isEqualToString:@"Module Glass"];
}

static void MGApplyBrandHeader(id controller) {
    if (!MGIsModuleGlassRootController(controller)) return;
    UITableView *table = MGTableViewForController(controller);
    if (!table) return;

    CGFloat width = CGRectGetWidth(table.bounds);
    if (width < 240.0) width = CGRectGetWidth(UIScreen.mainScreen.bounds);
    MGBrandHeaderView *header = nil;
    if ([table.tableHeaderView isKindOfClass:MGBrandHeaderView.class]) {
        header = (MGBrandHeaderView *)table.tableHeaderView;
    } else {
        header = [[MGBrandHeaderView alloc] initWithFrame:CGRectMake(0.0, 0.0, width, 164.0)];
        table.tableHeaderView = header;
    }
    if (fabs(CGRectGetWidth(header.frame) - width) > 0.5 || fabs(CGRectGetHeight(header.frame) - 164.0) > 0.5) {
        header.frame = CGRectMake(0.0, 0.0, width, 164.0);
        table.tableHeaderView = header;
    }
}

static IMP MGOriginalViewWillAppear = NULL;
static BOOL MGBrandHookInstalled = NO;

static void MGModuleGlassViewWillAppear(id self, SEL _cmd, BOOL animated) {
    if (MGOriginalViewWillAppear) {
        ((void (*)(id, SEL, BOOL))MGOriginalViewWillAppear)(self, _cmd, animated);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ MGApplyBrandHeader(self); });
}

static void MGInstallBrandHeader(void) {
    if (MGBrandHookInstalled) return;
    Class cls = NSClassFromString(@"AuraCategoryListController");
    if (!cls) return;
    SEL selector = @selector(viewWillAppear:);
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return;

    MGOriginalViewWillAppear = method_getImplementation(method);
    const char *types = method_getTypeEncoding(method);
    if (!class_addMethod(cls, selector, (IMP)MGModuleGlassViewWillAppear, types)) {
        class_replaceMethod(cls, selector, (IMP)MGModuleGlassViewWillAppear, types);
    }
    MGBrandHookInstalled = YES;
}

static void MGInstallPreferenceEnhancements(void) {
    MGInstallVolumeColorAction();
    MGInstallBrandHeader();
}

@interface MGPrefsBundleObserver : NSObject
+ (instancetype)shared;
- (void)bundleDidLoad:(NSNotification *)notification;
@end

@implementation MGPrefsBundleObserver
+ (instancetype)shared {
    static MGPrefsBundleObserver *observer;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ observer = [MGPrefsBundleObserver new]; });
    return observer;
}
- (void)bundleDidLoad:(NSNotification *)notification {
    MGInstallPreferenceEnhancements();
}
@end

__attribute__((constructor)) static void MGPrefsExtensionInit(void) {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserver:[MGPrefsBundleObserver shared]
                                                 selector:@selector(bundleDidLoad:)
                                                     name:NSBundleDidLoadNotification
                                                   object:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ MGInstallPreferenceEnhancements(); });
    }
}
