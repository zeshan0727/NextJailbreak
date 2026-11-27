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
@property(nonatomic) NSInteger shape;
@property(nonatomic,strong) UIView *phone;
@property(nonatomic,strong) UIView *cutout;
@property(nonatomic,strong) UIView *tile;
@property(nonatomic,strong) UILabel *sample;
@property(nonatomic,strong) CAShapeLayer *dockMask;
@property(nonatomic,strong) UIView *dockCap;
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
    _dockCap=[UIView new]; _dockCap.backgroundColor=UIColor.blackColor; _dockCap.hidden=YES; [_tile addSubview:_dockCap];
    _dockMask=[CAShapeLayer layer];
    [_tile addSubview:_sample]; [_phone addSubview:_cutout]; [_phone addSubview:_tile]; [self addSubview:_phone];
    self.isAccessibilityElement = YES; self.accessibilityLabel=@"Notification placement preview";
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = MAX(1.0,self.bounds.size.height-16), w=MIN(h*.49,self.bounds.size.width-16);
    self.phone.frame=CGRectMake((self.bounds.size.width-w)/2,8,w,h);
    self.cutout.frame=CGRectMake((w-45)/2,9,45,12);
    BOOL docked=self.position<=.015 && (self.shape<2 || self.shape==4);
    CGFloat th=34, minY=24, maxY=MAX(minY,h-th-14);
    CGFloat margin=self.shape==2?17:(self.shape==3?12:9);
    self.tile.frame=docked?CGRectMake(9,7,w-18,52):CGRectMake(margin,minY+(maxY-minY)*self.position,w-2*margin,th);
    self.tile.backgroundColor=NIStyleColor(self.mode);
    self.sample.textColor=self.mode==2?UIColor.blackColor:UIColor.whiteColor;
    self.dockCap.hidden=!docked;
    self.tile.layer.borderWidth=(!docked && self.shape==3)?1:0;
    self.tile.layer.borderColor=[UIColor colorWithWhite:1 alpha:.4].CGColor;
    if (docked) {
        CGFloat tw=self.tile.bounds.size.width, c=tw/2, l=c-25, r=c+25;
        UIBezierPath *p=[UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(l+7,0)]; [p addLineToPoint:CGPointMake(r-7,0)];
        [p addQuadCurveToPoint:CGPointMake(r,7) controlPoint:CGPointMake(r,0)];
        [p addLineToPoint:CGPointMake(r,12)]; [p addQuadCurveToPoint:CGPointMake(r+4,16) controlPoint:CGPointMake(r,16)];
        [p addLineToPoint:CGPointMake(tw-9,16)]; [p addQuadCurveToPoint:CGPointMake(tw,25) controlPoint:CGPointMake(tw,16)];
        [p addLineToPoint:CGPointMake(tw,42)]; [p addQuadCurveToPoint:CGPointMake(tw-10,52) controlPoint:CGPointMake(tw,52)];
        [p addLineToPoint:CGPointMake(10,52)]; [p addQuadCurveToPoint:CGPointMake(0,42) controlPoint:CGPointMake(0,52)];
        [p addLineToPoint:CGPointMake(0,25)]; [p addQuadCurveToPoint:CGPointMake(9,16) controlPoint:CGPointMake(0,16)];
        [p addLineToPoint:CGPointMake(l-4,16)]; [p addQuadCurveToPoint:CGPointMake(l,12) controlPoint:CGPointMake(l,16)];
        [p addLineToPoint:CGPointMake(l,7)]; [p addQuadCurveToPoint:CGPointMake(l+7,0) controlPoint:CGPointMake(l,0)]; [p closePath];
        if (self.shape==1) {
            p=[UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(l+7,0)]; [p addLineToPoint:CGPointMake(r-7,0)];
            [p addQuadCurveToPoint:CGPointMake(r,7) controlPoint:CGPointMake(r,0)];
            [p addLineToPoint:CGPointMake(r,10)];
            [p addCurveToPoint:CGPointMake(tw-12,16) controlPoint1:CGPointMake(r,16) controlPoint2:CGPointMake(tw-12,16)];
            [p addQuadCurveToPoint:CGPointMake(tw,28) controlPoint:CGPointMake(tw,16)];
            [p addLineToPoint:CGPointMake(tw,39)]; [p addQuadCurveToPoint:CGPointMake(tw-13,52) controlPoint:CGPointMake(tw,52)];
            [p addLineToPoint:CGPointMake(13,52)]; [p addQuadCurveToPoint:CGPointMake(0,39) controlPoint:CGPointMake(0,52)];
            [p addLineToPoint:CGPointMake(0,28)]; [p addQuadCurveToPoint:CGPointMake(12,16) controlPoint:CGPointMake(0,16)];
            [p addCurveToPoint:CGPointMake(l,10) controlPoint1:CGPointMake(12,16) controlPoint2:CGPointMake(l,16)];
            [p addLineToPoint:CGPointMake(l,7)]; [p addQuadCurveToPoint:CGPointMake(l+7,0) controlPoint:CGPointMake(l,0)]; [p closePath];
        }
        if (self.shape==4) {
            CGFloat half=MIN(tw*.5-.5,34.0), left=c-half, right=c+half, top=7, shoulder=18, edge=24, bottom=13;
            p=[UIBezierPath bezierPath];
            [p moveToPoint:CGPointMake(left+top,0)]; [p addLineToPoint:CGPointMake(right-top,0)];
            [p addQuadCurveToPoint:CGPointMake(right,top) controlPoint:CGPointMake(right,0)];
            [p addCurveToPoint:CGPointMake(tw,edge) controlPoint1:CGPointMake(right,shoulder) controlPoint2:CGPointMake(tw,shoulder)];
            [p addLineToPoint:CGPointMake(tw,52-bottom)];
            [p addQuadCurveToPoint:CGPointMake(tw-bottom,52) controlPoint:CGPointMake(tw,52)];
            [p addLineToPoint:CGPointMake(bottom,52)];
            [p addQuadCurveToPoint:CGPointMake(0,52-bottom) controlPoint:CGPointMake(0,52)];
            [p addLineToPoint:CGPointMake(0,edge)];
            [p addCurveToPoint:CGPointMake(left,top) controlPoint1:CGPointMake(0,shoulder) controlPoint2:CGPointMake(left,shoulder)];
            [p addQuadCurveToPoint:CGPointMake(left+top,0) controlPoint:CGPointMake(left,0)]; [p closePath];
        }
        self.tile.layer.cornerRadius=0; self.dockMask.frame=self.tile.bounds; self.dockMask.path=p.CGPath; self.tile.layer.mask=self.dockMask;
        if (self.shape==4) { self.dockCap.frame=CGRectMake(c-25,1,50,14); self.dockCap.layer.cornerRadius=7; }
        else { self.dockCap.frame=CGRectMake(0,0,tw,19); self.dockCap.layer.cornerRadius=0; }
        self.sample.frame=CGRectMake(7,21,tw-14,29);
    } else {
        self.tile.layer.mask=nil; self.tile.layer.cornerRadius=self.shape==2?17:12;
        self.tile.layer.cornerCurve=kCACornerCurveContinuous;
        self.sample.frame=CGRectInset(self.tile.bounds,7,2);
    }
}
@end
@interface NICompactSlider : UIView
@property(nonatomic,copy) NSString *key;
@property(nonatomic,strong) NSNumber *fallback;
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,strong) UILabel *valueLabel;
@property(nonatomic) BOOL percentage;
- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key fallback:(NSNumber *)fallback min:(float)min max:(float)max percentage:(BOOL)percentage;
- (void)refresh;
@end
@implementation NICompactSlider
- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key fallback:(NSNumber *)fallback min:(float)min max:(float)max percentage:(BOOL)percentage {
    if (!(self=[super initWithFrame:CGRectZero])) return nil;
    _key=[key copy]; _fallback=fallback; _percentage=percentage;
    UILabel *label=NILabel(title,14,UIFontWeightMedium);
    label.adjustsFontSizeToFitWidth=YES; label.minimumScaleFactor=.8;
    [label.widthAnchor constraintEqualToConstant:110].active=YES;
    _slider=[UISlider new]; _slider.minimumValue=min; _slider.maximumValue=max; _slider.accessibilityLabel=title;
    [_slider addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [_slider addTarget:self action:@selector(commit:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [_slider setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _valueLabel=NILabel(@"",12,UIFontWeightMedium); _valueLabel.textColor=UIColor.secondaryLabelColor;
    _valueLabel.textAlignment=NSTextAlignmentRight;
    [_valueLabel.widthAnchor constraintEqualToConstant:46].active=YES;
    UIStackView *row=NIRow(@[label,_slider,_valueLabel]); row.translatesAutoresizingMaskIntoConstraints=NO; row.spacing=6;
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],[row.topAnchor constraintEqualToAnchor:self.topAnchor],[row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],[self.heightAnchor constraintGreaterThanOrEqualToConstant:40]]];
    [self refresh]; return self;
}
- (void)updateValue { self.valueLabel.text=[NSString stringWithFormat:@"%.0f%@",self.percentage?self.slider.value*100:self.slider.value,self.percentage?@"%":@""]; }
- (void)refresh { self.slider.value=NIValue(self.key,self.fallback).floatValue; [self updateValue]; }
- (void)changed:(UISlider *)sender { [self updateValue]; if (!sender.tracking) [self commit:sender]; }
- (void)commit:(UISlider *)sender { NIWrite(self.key,self.percentage?@(roundf(sender.value*100)/100):@((NSInteger)lroundf(sender.value))); }
@end

@interface NICompactSwitch : UISwitch
@property(nonatomic,copy) NSString *preferenceKey;
@end
@implementation NICompactSwitch
@end

@interface NIStudioHeader : UIView
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) NIStudioPreview *preview;
@property(nonatomic,strong) UISlider *positionSlider;
@property(nonatomic,strong) UISlider *durationSlider;
@property(nonatomic,strong) UILabel *positionValue;
@property(nonatomic,strong) UILabel *durationValue;
@property(nonatomic,strong) NSArray<UIButton *> *styleButtons;
@property(nonatomic,strong) NSArray<UIButton *> *shapeButtons;
@property(nonatomic,strong) NSArray<UIButton *> *positionButtons;
@property(nonatomic,strong) UISwitch *animationSwitch;
@property(nonatomic,strong) UISwitch *masterSwitch;
@property(nonatomic,strong) NSMutableArray<NICompactSlider *> *detailSliders;
@property(nonatomic,strong) NSMutableArray<NICompactSwitch *> *detailSwitches;
- (void)refresh;
@end
@implementation NIStudioHeader
- (UIStackView *)detailGroup:(NSString *)title {
    UILabel *heading=NILabel(title,15,UIFontWeightSemibold);
    [_stack addArrangedSubview:heading];
    UIStackView *group=[UIStackView new]; group.axis=UILayoutConstraintAxisVertical; group.spacing=2;
    group.layoutMargins=UIEdgeInsetsMake(6,12,6,12); group.layoutMarginsRelativeArrangement=YES;
    group.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor; group.layer.cornerRadius=14;
    [_stack addArrangedSubview:group]; return group;
}
- (void)addDetail:(UIStackView *)group title:(NSString *)title key:(NSString *)key fallback:(NSNumber *)fallback min:(float)min max:(float)max percentage:(BOOL)percentage {
    NICompactSlider *slider=[[NICompactSlider alloc] initWithTitle:title key:key fallback:fallback min:min max:max percentage:percentage];
    [self.detailSliders addObject:slider]; [group addArrangedSubview:slider];
}
- (void)addToggle:(UIStackView *)group title:(NSString *)title key:(NSString *)key {
    NICompactSwitch *toggle=[NICompactSwitch new]; toggle.preferenceKey=key;
    toggle.accessibilityLabel=title; toggle.on=NIValue(key,@YES).boolValue;
    [toggle addTarget:self action:@selector(detailToggle:) forControlEvents:UIControlEventValueChanged];
    UIStackView *r=NIRow(@[NILabel(title,14,UIFontWeightMedium),[UIView new],toggle]);
    [r.heightAnchor constraintGreaterThanOrEqualToConstant:44].active=YES;
    [self.detailSwitches addObject:toggle]; [group addArrangedSubview:r];
}
- (void)detailToggle:(NICompactSwitch *)sender { NIWrite(sender.preferenceKey,@(sender.on)); }
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
    _masterSwitch=[UISwitch new];
    _masterSwitch.accessibilityLabel=@"Enable Notify Island";
    [_masterSwitch addTarget:self action:@selector(masterChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *master=NIRow(@[NILabel(@"Enable Notify Island",17,UIFontWeightSemibold),[UIView new],_masterSwitch]);
    master.layoutMargins=UIEdgeInsetsMake(10,12,10,12); master.layoutMarginsRelativeArrangement=YES;
    master.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor; master.layer.cornerRadius=14;
    [_stack addArrangedSubview:master];
    UILabel *sub=NILabel(@"Dock to the Dynamic Island or drag to a detached position.",13,UIFontWeightRegular);
    sub.textColor=UIColor.secondaryLabelColor; [_stack addArrangedSubview:sub];
    _preview=[NIStudioPreview new]; [_preview.heightAnchor constraintEqualToConstant:226].active=YES; [_stack addArrangedSubview:_preview];
    _positionValue=NILabel(@"Island",13,UIFontWeightMedium); _positionValue.textColor=UIColor.secondaryLabelColor; _positionValue.textAlignment=NSTextAlignmentRight;
    [_positionValue setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_stack addArrangedSubview:NIRow(@[NILabel(@"Vertical position",16,UIFontWeightSemibold),_positionValue])];
    _positionSlider=[UISlider new]; _positionSlider.minimumValue=0; _positionSlider.maximumValue=1;
    _positionSlider.accessibilityLabel=@"Vertical notification position";
    [_positionSlider addTarget:self action:@selector(positionChanged:) forControlEvents:UIControlEventValueChanged];
    [_positionSlider addTarget:self action:@selector(commitPosition:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
    [_stack addArrangedSubview:_positionSlider];
    NSMutableArray *positions=[NSMutableArray new]; NSArray *titles=@[@"Island",@"Middle",@"Bottom"];
    for (NSInteger i=0;i<3;i++) [positions addObject:[self button:titles[i] action:@selector(positionTapped:) tag:i]];
    _positionButtons=[positions copy]; UIStackView *pr=NIRow(positions); pr.distribution=UIStackViewDistributionFillEqually; [_stack addArrangedSubview:pr];
    [_stack addArrangedSubview:NILabel(@"Island style",16,UIFontWeightSemibold)];
    NSArray *shapeNames=@[@"Classic",@"Fluid",@"Capsule",@"Floating",@"Full Cover"];
    NSMutableArray *shapes=[NSMutableArray new];
    for (NSInteger i=0;i<5;i++) {
        UIButton *b=[self button:shapeNames[i] action:@selector(shapeTapped:) tag:i];
        b.titleLabel.adjustsFontSizeToFitWidth=YES;
        b.titleLabel.minimumScaleFactor=.7;
        [shapes addObject:b];
    }
    _shapeButtons=[shapes copy];
    UIStackView *shapeRow=NIRow([shapes subarrayWithRange:NSMakeRange(0,3)]);
    shapeRow.distribution=UIStackViewDistributionFillEqually; [_stack addArrangedSubview:shapeRow];
    UIStackView *shapeRow2=NIRow([shapes subarrayWithRange:NSMakeRange(3,2)]);
    shapeRow2.distribution=UIStackViewDistributionFillEqually; [_stack addArrangedSubview:shapeRow2];
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
    UIButton *test=[self button:@"Shuffle test notification" action:@selector(testTapped) tag:0];
    test.backgroundColor=UIColor.systemBlueColor; [test setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; test.layer.borderWidth=0;
    [_stack addArrangedSubview:test];
    _detailSliders=[NSMutableArray new]; _detailSwitches=[NSMutableArray new];
    UIStackView *look=[self detailGroup:@"Appearance details"];
    [self addDetail:look title:@"Blur" key:@"NotificationIslandBlurStrength" fallback:@.55 min:.20 max:1 percentage:YES];
    [self addDetail:look title:@"Opacity" key:@"NotificationIslandBackgroundOpacity" fallback:@.98 min:.55 max:1 percentage:YES];
    [self addDetail:look title:@"Text size" key:@"NotificationIslandTextScale" fallback:@1 min:.8 max:1.35 percentage:YES];
    [self addDetail:look title:@"Corner rounding" key:@"NotificationIslandCornerRadius" fallback:@32 min:16 max:40 percentage:NO];
    UIStackView *behavior=[self detailGroup:@"Behavior"];
    [self addToggle:behavior title:@"Replace stock banner" key:@"NotificationIslandReplaceStockBanner"];
    [self addToggle:behavior title:@"Landscape support" key:@"NotificationIslandLandscapeEnabled"];
    [self addToggle:behavior title:@"App notification actions" key:@"NotificationIslandNativeActions"];
    UIStackView *size=[self detailGroup:@"Card size & alignment"];
    [self addDetail:size title:@"Compact width" key:@"NotificationIslandCompactWidth" fallback:@330 min:190 max:425 percentage:NO];
    [self addDetail:size title:@"Compact height" key:@"NotificationIslandCompactHeight" fallback:@68 min:58 max:110 percentage:NO];
    [self addDetail:size title:@"Expanded width" key:@"NotificationIslandExpandedWidth" fallback:@405 min:190 max:425 percentage:NO];
    [self addDetail:size title:@"Expanded height" key:@"NotificationIslandExpandedHeight" fallback:@150 min:125 max:240 percentage:NO];
    [self addDetail:size title:@"Side offset" key:@"NotificationIslandHorizontalOffset" fallback:@0 min:-140 max:140 percentage:NO];
    UILabel *note=NILabel(@"Full Cover wraps the entire aperture in one continuous shape. Select it to snap to Island position. Double-tap to dismiss; Reply opens the composer.",12,UIFontWeightRegular);
    note.textColor=UIColor.secondaryLabelColor; [_stack addArrangedSubview:note];
    [self refresh];
    return self;
}
- (void)updatePosition {
    CGFloat v=self.positionSlider.value; self.preview.position=v;
    self.positionValue.text=v<.01?@"Island":v>.99?@"Bottom":fabs(v-.5)<.01?@"Middle":[NSString stringWithFormat:@"%.0f%%",v*100];
    [self.preview setNeedsLayout];
    for (UIButton *b in self.positionButtons) {
        BOOL selected=fabs(v-b.tag*.5)<.01;
        b.layer.borderColor=(selected?UIColor.systemBlueColor:UIColor.separatorColor).CGColor;
        b.backgroundColor=selected?[UIColor.systemBlueColor colorWithAlphaComponent:.12]:UIColor.tertiarySystemGroupedBackgroundColor;
        b.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    }
}
- (void)updateStyle {
    for (UIButton *b in self.shapeButtons) {
        BOOL selected=b.tag==self.preview.shape;
        b.backgroundColor=selected?[UIColor.systemBlueColor colorWithAlphaComponent:.14]:UIColor.tertiarySystemGroupedBackgroundColor;
        b.layer.borderWidth=selected?2:1;
        b.layer.borderColor=(selected?UIColor.systemBlueColor:UIColor.separatorColor).CGColor;
        b.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
    }
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
    self.preview.shape=MIN(4,MAX(0,NIValue(@"NotificationIslandShapeStyle",@1).integerValue));
    self.durationSlider.value=MIN(30,MAX(2,NIValue(@"NotificationIslandDismissTime",NIValue(@"NotificationIslandDuration",@6)).floatValue));
    self.animationSwitch.on=NIValue(@"NotificationIslandAnimationEnabled",@YES).boolValue;
    self.masterSwitch.on=NIValue(@"NotificationIslandEnabled",@YES).boolValue;
    for (NICompactSlider *slider in self.detailSliders) [slider refresh];
    for (NICompactSwitch *toggle in self.detailSwitches) toggle.on=NIValue(toggle.preferenceKey,@YES).boolValue;
    [self updatePosition]; [self updateStyle];
    self.durationValue.text=[NSString stringWithFormat:@"%.0f sec",self.durationSlider.value];
}
- (void)positionChanged:(UISlider *)sender { [self updatePosition]; if (!sender.tracking) [self commitPosition:sender]; }
- (void)commitPosition:(UISlider *)sender { NIWrite(@"NotificationIslandVerticalPosition",@(sender.value)); }
- (void)positionTapped:(UIButton *)sender { [self.positionSlider setValue:sender.tag*.5 animated:YES]; [self updatePosition]; [self commitPosition:self.positionSlider]; }
- (void)shapeTapped:(UIButton *)sender {
    self.preview.shape=sender.tag;
    if (sender.tag==4) {
        [self.positionSlider setValue:0 animated:YES];
        [self updatePosition];
        [self commitPosition:self.positionSlider];
    }
    [self updateStyle]; NIWrite(@"NotificationIslandShapeStyle",@(sender.tag));
}
- (void)styleTapped:(UIButton *)sender { self.preview.mode=sender.tag; [self updateStyle]; NIWrite(@"NotificationIslandAppearanceMode",@(sender.tag)); }
- (void)durationChanged:(UISlider *)sender { self.durationValue.text=[NSString stringWithFormat:@"%.0f sec",sender.value]; if (!sender.tracking) [self commitDuration:sender]; }
- (void)commitDuration:(UISlider *)sender { NIWrite(@"NotificationIslandDismissTime",@((NSInteger)lroundf(sender.value))); }
- (void)masterChanged:(UISwitch *)sender { NIWrite(@"NotificationIslandEnabled",@(sender.on)); }
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
