#import <Foundation/Foundation.h>
#import <math.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
static CFStringRef const NIDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const NIChanged = CFSTR("com.nextsolution.unlockvibrate/preferences.changed");
#import <UIKit/UIKit.h>

static NSNumber *NIValue(NSString *key, NSNumber *fallback) {
    CFPreferencesAppSynchronize(NIDomain);
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NIDomain));
    return [v isKindOfClass:NSNumber.class] ? v : fallback;
}
static void NIWrite(NSString *key, NSNumber *value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NIDomain);
    CFPreferencesAppSynchronize(NIDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NIChanged, NULL, NULL, true);
}
static UILabel *NILabel(NSString *text, CGFloat size, UIFontWeight weight) {
    UILabel *l = [UILabel new]; l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = UIColor.labelColor; l.numberOfLines = 0;
    return l;
}
static UIStackView *NIRow(NSArray<UIView *> *views) {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 8;
    return row;
}
static UIColor *NIStyleColor(NSInteger mode) {
    switch (mode) {
        case 1: return [UIColor colorWithRed:.12 green:.18 blue:.28 alpha:1];
        case 2: return [UIColor colorWithRed:.84 green:.88 blue:.94 alpha:1];
        case 3: return [UIColor colorWithRed:.33 green:.43 blue:.62 alpha:.88];
        default: return UIColor.blackColor;
    }
}
@interface NIStudioPreview : UIView
@property(nonatomic) CGFloat position;
@property(nonatomic) NSInteger mode;
@property(nonatomic,strong) UIView *phone;
@property(nonatomic,strong) UIView *cutout;
@property(nonatomic,strong) UIView *tile;
@property(nonatomic,strong) UILabel *sample;
@end
@implementation NIStudioPreview
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.layer.cornerRadius = 18;
    _phone = [UIView new]; _phone.backgroundColor = [UIColor colorWithRed:.12 green:.22 blue:.40 alpha:1];
    _phone.layer.cornerRadius = 24; _phone.layer.borderWidth = 4; _phone.layer.borderColor = UIColor.blackColor.CGColor; _phone.clipsToBounds=YES;
    _cutout = [UIView new]; _cutout.backgroundColor = UIColor.blackColor; _cutout.layer.cornerRadius = 6;
    _tile = [UIView new]; _tile.layer.cornerRadius = 10; _tile.clipsToBounds = YES;
    _sample = NILabel(@"Messages\nNew notification", 10, UIFontWeightSemibold);
    _sample.textColor = UIColor.whiteColor;
    [_tile addSubview:_sample]; [_phone addSubview:_cutout]; [_phone addSubview:_tile]; [self addSubview:_phone];
    self.isAccessibilityElement = YES; self.accessibilityLabel=@"Notification placement preview";
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = MAX(1.0,self.bounds.size.height-16), w=MIN(h*.49,self.bounds.size.width-16);
    self.phone.frame=CGRectMake((self.bounds.size.width-w)/2,8,w,h);
    self.cutout.frame=CGRectMake((w-45)/2,9,45,12);
    CGFloat th=34, minY=24, maxY=MAX(minY,h-th-14);
    self.tile.frame=CGRectMake(9,minY+(maxY-minY)*self.position,w-18,th);
    self.tile.backgroundColor=NIStyleColor(self.mode);
    self.sample.textColor=self.mode==2?UIColor.blackColor:UIColor.whiteColor;
    self.sample.frame=CGRectInset(self.tile.bounds,7,2);
}
@end
@interface NIStudioHeader : UIView
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) NIStudioPreview *preview;
@property(nonatomic,strong) UISlider *positionSlider;
@property(nonatomic,strong) UISlider *durationSlider;
@property(nonatomic,strong) UILabel *positionValue;
@property(nonatomic,strong) UILabel *durationValue;
@property(nonatomic,strong) NSArray<UIButton *> *styleButtons;
@property(nonatomic,strong) NSArray<UIButton *> *positionButtons;
@property(nonatomic,strong) UISwitch *animationSwitch;
- (void)refresh;
@end
@implementation NIStudioHeader
- (UIButton *)button:(NSString *)title action:(SEL)action tag:(NSInteger)tag {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal]; b.tag=tag;
    b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    b.layer.cornerRadius=10; b.layer.borderWidth=1.0; b.clipsToBounds=YES;
    [b.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.backgroundColor=UIColor.clearColor;
    _stack=[UIStackView new]; _stack.axis=UILayoutConstraintAxisVertical; _stack.spacing=12; _stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:_stack];
    [NSLayoutConstraint activateConstraints:@[
        [_stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [_stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
        [_stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:20],
        [_stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-20]
    ]];
    [_stack addArrangedSubview:NILabel(@"Island Studio",24,UIFontWeightBold)];
    UILabel *sub=NILabel(@"Choose a style and slide the notification to any position.",13,UIFontWeightRegular);
    sub.textColor=UIColor.secondaryLabelColor; [_stack addArrangedSubview:sub];
    _preview=[NIStudioPreview new]; [_preview.heightAnchor constraintEqualToConstant:226].active=YES; [_stack addArrangedSubview:_preview];
    _positionValue=NILabel(@"Top",13,UIFontWeightMedium); _positionValue.textColor=UIColor.secondaryLabelColor; _positionValue.textAlignment=NSTextAlignmentRight;
    [_positionValue setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_stack addArrangedSubview:NIRow(@[NILabel(@"Vertical position",16,UIFontWeightSemibold),_positionValue])];
    _positionSlider=[UISlider new]; _positionSlider.minimumValue=0; _positionSlider.maximumValue=1;
    _positionSlider.accessibilityLabel=@"Vertical notification position";
    [_positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    [_positionSlider addTarget:self action:@selector(commitPosition:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [_stack addArrangedSubview:_positionSlider];
    NSMutableArray *positions=[NSMutableArray new]; NSArray *titles=@[@"Top",@"Middle",@"Bottom"];
    for (NSInteger i=0;i<3;i++) [positions addObject:[self button:titles[i] action:@selector(positionTapped:) tag:i]];
    _positionButtons=[positions copy]; UIStackView *pr=NIRow(positions); pr.distribution=UIStackViewDistributionFillEqually; [_stack addArrangedSubview:pr];
    [_stack addArrangedSubview:NILabel(@"Appearance",16,UIFontWeightSemibold)];
    NSMutableArray *styles=[NSMutableArray new]; NSArray *names=@[@"Black",@"Dark",@"Light",@"Glass"];
    for (NSInteger i=0;i<4;i++) {
        UIButton *b=[self button:names[i] action:@selector(styleTapped:) tag:i]; b.backgroundColor=NIStyleColor(i);
        [b setTitleColor:i==2?UIColor.blackColor:UIColor.whiteColor forState:UIControlStateNormal];
        [styles addObject:b];
    }
    _styleButtons=[styles copy]; UIStackView *sr=NIRow(styles); sr.distribution=UIStackViewDistributionFillEqually; [_stack addArrangedSubview:sr];
    _durationValue=NILabel(@"8 sec",13,UIFontWeightMedium); _durationValue.textColor=UIColor.secondaryLabelColor; _durationValue.textAlignment=NSTextAlignmentRight;
    [_durationValue setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_stack addArrangedSubview:NIRow(@[NILabel(@"Display duration",16,UIFontWeightSemibold),_durationValue])];
    _durationSlider=[UISlider new]; _durationSlider.minimumValue=2; _durationSlider.maximumValue=30;
    _durationSlider.accessibilityLabel=@"Notification display duration";
    [_durationSlider addTarget:self action:@selector(durationChanged:) forControlEvents:UIControlEventValueChanged];
    [_durationSlider addTarget:self action:@selector(commitDuration:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [_stack addArrangedSubview:_durationSlider];
    _animationSwitch=[UISwitch new]; [_animationSwitch addTarget:self action:@selector(animationChanged:) forControlEvents:UIControlEventValueChanged];
    [_stack addArrangedSubview:NIRow(@[NILabel(@"Island animation",16,UIFontWeightSemibold),[UIView new],_animationSwitch])];
    UIButton *test=[self button:@"Send test notification" action:@selector(testTapped) tag:0];
    test.backgroundColor=UIColor.systemBlueColor; [test setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; test.layer.borderWidth=0;
    [_stack addArrangedSubview:test];
    [self refresh];
    return self;
}
- (void)updatePosition {
    CGFloat v=self.positionSlider.value; self.preview.position=v;
    self.positionValue.text=v<.01?@"Top":v>.99?@"Bottom":fabs(v-.5)<.01?@"Middle":[NSString stringWithFormat:@"%.0f%%",v*100];
    [self.preview setNeedsLayout];
    for (UIButton *b in self.positionButtons) {
        BOOL selected=fabs(v-b.tag*.5)<.01;
        b.layer.borderColor=(selected?UIColor.systemBlueColor:UIColor.separatorColor).CGColor;
        b.backgroundColor=selected?[UIColor.systemBlueColor colorWithAlphaComponent:.12]:UIColor.tertiarySystemGroupedBackgroundColor;
        b.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    }
}
- (void)updateStyle {
    for (UIButton *b in self.styleButtons) {
        BOOL selected=b.tag==self.preview.mode;
        b.layer.borderWidth=selected?3:1;
        b.layer.borderColor=(selected?UIColor.systemBlueColor:UIColor.separatorColor).CGColor;
        b.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    }
    [self.preview setNeedsLayout];
}
- (void)refresh {
    self.positionSlider.value=MIN(1,MAX(0,NIValue(@"NotificationIslandVerticalPosition",@0).floatValue));
    self.preview.mode=MIN(3,MAX(0,NIValue(@"NotificationIslandAppearanceMode",@0).integerValue));
    self.durationSlider.value=MIN(30,MAX(2,NIValue(@"NotificationIslandDismissTime",NIValue(@"NotificationIslandDuration",@6)).floatValue));
    self.animationSwitch.on=NIValue(@"NotificationIslandAnimationEnabled",@YES).boolValue;
    [self updatePosition]; [self updateStyle];
    self.durationValue.text=[NSString stringWithFormat:@"%.0f sec",self.durationSlider.value];
}
- (void)positionChanged:(UISlider *)sender { [self updatePosition]; if (!sender.tracking) [self commitPosition:sender]; }
- (void)commitPosition:(UISlider *)sender { NIWrite(@"NotificationIslandVerticalPosition",@(sender.value)); }
- (void)positionTapped:(UIButton *)sender { [self.positionSlider setValue:sender.tag*.5 animated:YES]; [self updatePosition]; [self commitPosition:self.positionSlider]; }
- (void)styleTapped:(UIButton *)sender { self.preview.mode=sender.tag; [self updateStyle]; NIWrite(@"NotificationIslandAppearanceMode",@(sender.tag)); }
- (void)durationChanged:(UISlider *)sender { self.durationValue.text=[NSString stringWithFormat:@"%.0f sec",sender.value]; if (!sender.tracking) [self commitDuration:sender]; }
- (void)commitDuration:(UISlider *)sender { NIWrite(@"NotificationIslandDismissTime",@((NSInteger)lroundf(sender.value))); }
- (void)animationChanged:(UISwitch *)sender { NIWrite(@"NotificationIslandAnimationEnabled",@(sender.on)); }
- (void)testTapped { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/test-dynamic-island-suite"), NULL, NULL, true); }
@end

static UITableView *NIFindTable(UIView *view) {
    if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    for (UIView *child in view.subviews) { UITableView *table=NIFindTable(child); if (table) return table; }
    return nil;
}

@interface NISettingsController : PSListController
@property(nonatomic,strong) NIStudioHeader *studioHeader;
@property(nonatomic) CGFloat studioWidth;
@end
@implementation NISettingsController
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if ([self class] == NISettingsController.class) [self.studioHeader refresh];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if ([self class] != NISettingsController.class) return;
    UITableView *table=NIFindTable(self.view);
    if (!table || CGRectGetWidth(table.bounds)<100) return;
    CGFloat width=CGRectGetWidth(table.bounds);
    if (!self.studioHeader) self.studioHeader=[[NIStudioHeader alloc] initWithFrame:CGRectMake(0,0,width,1)];
    if (table.tableHeaderView==self.studioHeader && fabs(self.studioWidth-width)<.5) return;
    self.studioWidth=width;
    self.studioHeader.frame=CGRectMake(0,0,width,1);
    CGSize fitting=[self.studioHeader systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel];
    self.studioHeader.frame=CGRectMake(0,0,width,ceil(fitting.height));
    table.tableHeaderView=self.studioHeader;
}
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(NIDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NIDomain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NIDomain);
    CFPreferencesAppSynchronize(NIDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NIChanged, NULL, NULL, true);
}
- (void)testDynamicIslandSuite:(PSSpecifier *)specifier {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/test-dynamic-island-suite"), NULL, NULL, true);
}
@end

@interface NISettingsPageController : NISettingsController
@end
@implementation NISettingsPageController
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *page = [[self specifier] propertyForKey:@"NIPage"];
        NSSet *allowed = [NSSet setWithArray:@[@"Appearance",@"Behavior",@"Privacy",@"Landscape",@"Advanced"]];
        if (![allowed containsObject:page]) return @[];
        _specifiers = [self loadSpecifiersFromPlistName:page target:self];
    }
    return _specifiers;
}
@end
