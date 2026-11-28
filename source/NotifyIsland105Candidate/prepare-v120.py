#!/usr/bin/env python3
"""1.0.20: nonblocking app launch and session-only motion notification bubbles."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.20 missing anchor: "+a[:140])
    s=s.replace(a,b,1)
rep('#import <UIKit/UIKit.h>','#import <UIKit/UIKit.h>\n#import <CoreMotion/CoreMotion.h>')
# Insert before the card and after existing forwards/utilities, preserving
# the existing native action dispatch, composer and suppression functions.
anchor='@interface NANReplyWindow : UIWindow'
rep(anchor,r'''static BOOL NANFloatingReopen=NO;
static BOOL NANOpeningApplication=NO;
static void NANFloatingRefresh(void);
static void NANFloatingAttend(NSString *fingerprint);
static void NANFloatingClear(void);
static void NANFloatingRemember(NSDictionary *model,UIViewController *controller);

@interface NANFloatingRecord : NSObject
@property(nonatomic,strong) NSDictionary *model;
@property(nonatomic,weak) UIViewController *controller;
@end
@implementation NANFloatingRecord
@end

@interface NANFloatingButton : UIControl
@property(nonatomic,copy) NSString *bundleID;
@property(nonatomic,strong) UIImageView *imageView;
@property(nonatomic,strong) UILabel *countLabel;
@property(nonatomic) CGPoint velocity;
@end
@implementation NANFloatingButton
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.backgroundColor=[UIColor colorWithWhite:.08 alpha:.94];
    self.layer.cornerRadius=25;
    self.layer.borderWidth=1.0;
    self.layer.borderColor=[UIColor colorWithWhite:1 alpha:.28].CGColor;
    self.layer.shadowColor=UIColor.blackColor.CGColor;
    self.layer.shadowOpacity=.3;
    self.layer.shadowRadius=5;
    self.layer.shadowOffset=CGSizeMake(0,2);
    self.imageView=[[UIImageView alloc] initWithFrame:CGRectMake(5,5,40,40)];
    self.imageView.contentMode=UIViewContentModeScaleAspectFit;
    self.imageView.layer.cornerRadius=11;
    self.imageView.clipsToBounds=YES;
    self.imageView.userInteractionEnabled=NO;
    [self addSubview:self.imageView];
    self.countLabel=[[UILabel alloc] initWithFrame:CGRectMake(32,-4,22,22)];
    self.countLabel.font=[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightBold];
    self.countLabel.textAlignment=NSTextAlignmentCenter;
    self.countLabel.textColor=UIColor.whiteColor;
    self.countLabel.backgroundColor=UIColor.systemRedColor;
    self.countLabel.layer.cornerRadius=11;
    self.countLabel.clipsToBounds=YES;
    self.countLabel.userInteractionEnabled=NO;
    [self addSubview:self.countLabel];
    self.isAccessibilityElement=YES;
    self.accessibilityTraits=UIAccessibilityTraitButton;
    return self;
}
@end

@interface NANFloatingWindow : UIWindow
@end
@implementation NANFloatingWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)_canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled || NANIsUILocked()) return nil;
    UIView *root=self.rootViewController.view;
    for (UIView *view in root.subviews.reverseObjectEnumerator) {
        if (![view isKindOfClass:NANFloatingButton.class] || view.hidden || !view.userInteractionEnabled) continue;
        CGPoint local=[view convertPoint:point fromView:self];
        UIView *hit=[view hitTest:local withEvent:event];
        if (hit) return hit;
    }
    return nil; // Never intercept unrelated taps, swipes or app gestures.
}
@end

@interface NANFloatingManager : NSObject
@property(nonatomic,strong) NSMutableArray<NANFloatingRecord *> *records;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NANFloatingButton *> *buttons;
@property(nonatomic,strong) NANFloatingWindow *window;
@property(nonatomic,strong) CMMotionManager *motion;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic) CFTimeInterval lastTick;
@property(nonatomic) CFTimeInterval lastPrivacyCheck;
- (void)refresh;
- (void)clear;
- (void)attend:(NSString *)fingerprint;
- (void)remember:(NSDictionary *)model controller:(UIViewController *)controller;
- (void)bubbleTapped:(NANFloatingButton *)button;
@end
static NANFloatingManager *NANFloats=nil;
static BOOL NANFloatingEnabled(void) {
    return NANBool(@"NotificationIslandEnabled",YES) && NANBool(@"NotificationIslandFloatingIcons",YES);
}
@implementation NANFloatingManager
- (instancetype)init {
    if (!(self=[super init])) return nil;
    self.records=[NSMutableArray new];
    self.buttons=[NSMutableDictionary new];
    return self;
}
- (void)stopMotion {
    [self.displayLink invalidate]; self.displayLink=nil;
    [self.motion stopDeviceMotionUpdates]; self.motion=nil;
    self.lastTick=0; self.lastPrivacyCheck=0;
}
- (void)hideWindow {
    self.window.hidden=YES;
    [self stopMotion];
}
- (void)clear {
    [self hideWindow];
    [self.records removeAllObjects];
    for (UIView *button in self.buttons.allValues) [button removeFromSuperview];
    [self.buttons removeAllObjects];
    self.window.rootViewController=nil;
    self.window=nil;
}
- (void)remember:(NSDictionary *)model controller:(UIViewController *)controller {
    if (!NANFloatingEnabled() || [model[@"test"] boolValue]) return;
    NSString *fingerprint=NANFingerprint(model);
    NSString *bundle=model[@"bundleID"];
    if (!fingerprint.length || ![bundle isKindOfClass:NSString.class] || !bundle.length) return;
    for (NANFloatingRecord *record in self.records) {
        if ([NANFingerprint(record.model) isEqualToString:fingerprint]) {
            if (controller) record.controller=controller;
            return;
        }
    }
    NANFloatingRecord *record=[NANFloatingRecord new];
    record.model=model; record.controller=controller;
    [self.records addObject:record];
    // Bound in-memory retention; overflow stays in original Notification Center.
    while (self.records.count>64) [self.records removeObjectAtIndex:0];
}
- (void)attend:(NSString *)fingerprint {
    if (!fingerprint.length) return;
    NSIndexSet *matches=[self.records indexesOfObjectsPassingTest:^BOOL(NANFloatingRecord *record,NSUInteger idx,BOOL *stop) {
        return [NANFingerprint(record.model) isEqualToString:fingerprint];
    }];
    [self.records removeObjectsAtIndexes:matches];
    [self refresh];
}
- (void)refresh {
    if (!NANFloatingEnabled()) { [self clear]; return; }
    // Present bubbles after the notification card retracts; never obscure
    // the card, reply composer, keyboard, lock screen or a pending launch.
    if (!self.records.count || NANIslandView || NANOpeningApplication || NANIsUILocked()) {
        [self hideWindow]; return;
    }
    UIWindowScene *scene=NANSystemWindow.windowScene;
    if (!scene || scene.screen!=UIScreen.mainScreen || scene.activationState!=UISceneActivationStateForegroundActive) {
        [self hideWindow]; return;
    }
    if (!self.window || self.window.windowScene!=scene) {
        [self hideWindow];
        for (UIView *button in self.buttons.allValues) [button removeFromSuperview];
        [self.buttons removeAllObjects];
        self.window.rootViewController=nil;
        self.window=[[NANFloatingWindow alloc] initWithWindowScene:scene];
        self.window.backgroundColor=UIColor.clearColor;
        self.window.windowLevel=MAX(UIWindowLevelStatusBar+1,NANSystemWindow.windowLevel);
        UIViewController *host=[UIViewController new];
        host.view.backgroundColor=UIColor.clearColor;
        self.window.rootViewController=host;
    }
    CGRect screenBounds=scene.coordinateSpace.bounds;
    if (!CGRectEqualToRect(self.window.frame,screenBounds)) self.window.frame=screenBounds;
    NSMutableDictionary<NSString *,NSNumber *> *counts=[NSMutableDictionary new];
    NSMutableArray<NSString *> *order=[NSMutableArray new];
    NSMutableDictionary<NSString *,NSString *> *names=[NSMutableDictionary new];
    for (NANFloatingRecord *record in self.records) {
        NSString *bundle=record.model[@"bundleID"];
        if (!counts[bundle]) [order addObject:bundle];
        counts[bundle]=@([counts[bundle] unsignedIntegerValue]+1);
        names[bundle]=record.model[@"appName"] ?: bundle;
    }
    // Limit concurrent moving touch targets; older apps remain queued.
    if (order.count>8) [order removeObjectsInRange:NSMakeRange(8,order.count-8)];
    for (NSString *key in self.buttons.allKeys.copy) if (![order containsObject:key]) {
        [self.buttons[key] removeFromSuperview]; [self.buttons removeObjectForKey:key];
    }
    UIView *root=self.window.rootViewController.view;
    CGRect bounds=root.bounds;
    for (NSUInteger i=0;i<order.count;i++) {
        NSString *bundle=order[i];
        NANFloatingButton *button=self.buttons[bundle];
        if (!button) {
            button=[[NANFloatingButton alloc] initWithFrame:CGRectMake(0,0,50,50)];
            button.bundleID=bundle;
            button.imageView.image=NANApplicationIcon(bundle);
            button.center=CGPointMake(40+(i%2)*MAX(0,CGRectGetWidth(bounds)-80),
                                      145+(i/2)*64);
            [button addTarget:self action:@selector(bubbleTapped:) forControlEvents:UIControlEventTouchUpInside];
            self.buttons[bundle]=button;
            [root addSubview:button];
        }
        NSUInteger count=[counts[bundle] unsignedIntegerValue];
        button.countLabel.hidden=count<2;
        button.countLabel.text=[NSString stringWithFormat:@"%lu",(unsigned long)count];
        button.accessibilityLabel=[NSString stringWithFormat:@"%@, %lu pending notifications",names[bundle],(unsigned long)count];
    }
    self.window.hidden=NO; // Never make this window key.
    if (!self.displayLink) {
        if (!UIAccessibilityIsReduceMotionEnabled()) {
            self.motion=[CMMotionManager new];
            if (self.motion.deviceMotionAvailable) {
                self.motion.deviceMotionUpdateInterval=1.0/30.0;
                [self.motion startDeviceMotionUpdates];
            }
        }
        self.displayLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        self.displayLink.preferredFramesPerSecond=30;
        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)tick:(CADisplayLink *)link {
    if (self.window.hidden) { [self stopMotion]; return; }
    if (link.timestamp-self.lastPrivacyCheck>.4) {
        self.lastPrivacyCheck=link.timestamp;
        if (!NANFloatingEnabled() || NANIsUILocked() || NANIslandView || NANOpeningApplication ||
            self.window.windowScene.activationState!=UISceneActivationStateForegroundActive) {
            [self hideWindow]; return;
        }
    }
    CFTimeInterval dt=self.lastTick?MIN(.05,MAX(.001,link.timestamp-self.lastTick)):1.0/30.0;
    self.lastTick=link.timestamp;
    UIView *root=self.window.rootViewController.view;
    CGRect safe=UIEdgeInsetsInsetRect(root.bounds,root.safeAreaInsets);
    CGFloat left=CGRectGetMinX(safe)+30,right=CGRectGetMaxX(safe)-30;
    CGFloat top=CGRectGetMinY(safe)+34,bottom=CGRectGetMaxY(safe)-36;
    if (right<=left || bottom<=top) return;
    CMDeviceMotion *motion=self.motion.deviceMotion;
    CMAcceleration gravity=motion?motion.gravity:(CMAcceleration){0,0,0};
    CGFloat ax=gravity.x*470,ay=-gravity.y*470;
    switch (self.window.windowScene.interfaceOrientation) {
        case UIInterfaceOrientationLandscapeLeft: ax=-gravity.y*470; ay=-gravity.x*470; break;
        case UIInterfaceOrientationLandscapeRight: ax=gravity.y*470; ay=gravity.x*470; break;
        case UIInterfaceOrientationPortraitUpsideDown: ax=-ax; ay=-ay; break;
        default: break;
    }
    BOOL reduced=UIAccessibilityIsReduceMotionEnabled();
    NSArray<NANFloatingButton *> *buttons=self.buttons.allValues;
    for (NANFloatingButton *b in buttons) {
        if (b.highlighted) { b.velocity=CGPointZero; continue; }
        CGPoint pos=b.center,vel=b.velocity;
        if (reduced || !motion) vel=CGPointZero;
        else {
            vel.x=(vel.x+ax*dt)*.94; vel.y=(vel.y+ay*dt)*.94;
            vel.x=MAX(-230,MIN(230,vel.x)); vel.y=MAX(-230,MIN(230,vel.y));
            pos.x+=vel.x*dt; pos.y+=vel.y*dt;
        }
        if (pos.x<left) { pos.x=left; vel.x=fabs(vel.x)*.55; }
        if (pos.x>right) { pos.x=right; vel.x=-fabs(vel.x)*.55; }
        if (pos.y<top) { pos.y=top; vel.y=fabs(vel.y)*.55; }
        if (pos.y>bottom) { pos.y=bottom; vel.y=-fabs(vel.y)*.55; }
        b.center=pos; b.velocity=vel;
    }
    // Small, bounded pairwise collision pass prevents app icons overlapping.
    for (NSUInteger i=0;i<buttons.count;i++) for (NSUInteger j=i+1;j<buttons.count;j++) {
        NANFloatingButton *a=buttons[i],*b=buttons[j];
        CGFloat dx=b.center.x-a.center.x,dy=b.center.y-a.center.y;
        CGFloat distance=hypot(dx,dy);
        if (distance>=57 || (a.highlighted && b.highlighted)) continue;
        if (distance<.01) { dx=1; dy=0; distance=1; }
        CGFloat nx=dx/distance,ny=dy/distance,shift=(57-distance)*.5;
        CGPoint pa=a.center,pb=b.center;
        if (!a.highlighted) { pa.x-=nx*shift; pa.y-=ny*shift; }
        if (!b.highlighted) { pb.x+=nx*shift; pb.y+=ny*shift; }
        a.center=CGPointMake(MAX(left,MIN(right,pa.x)),MAX(top,MIN(bottom,pa.y)));
        b.center=CGPointMake(MAX(left,MIN(right,pb.x)),MAX(top,MIN(bottom,pb.y)));
    }
}
- (void)bubbleTapped:(NANFloatingButton *)button {
    if (!NANFloatingEnabled() || NANIsUILocked() || NANIslandView || NANOpeningApplication) return;
    NANFloatingRecord *record=nil;
    for (NANFloatingRecord *candidate in self.records) if ([candidate.model[@"bundleID"] isEqualToString:button.bundleID]) { record=candidate; break; }
    if (!record) return;
    // The real request is retained only in RAM. Do not use a recycled
    // controller for fallback native actions unless its request still matches.
    UIViewController *controller=record.controller;
    if (controller && NANSafeValue(controller,@"notificationRequest")!=record.model[@"nativeRequest"]) controller=nil;
    NANFloatingReopen=YES;
    BOOL shown=NANPresentModel(record.model,controller);
    NANFloatingReopen=NO;
    if (shown) [self hideWindow];
}
@end
static void NANFloatingRefresh(void) {
    if (!NANFloats && NANFloatingEnabled()) NANFloats=[NANFloatingManager new];
    [NANFloats refresh];
}
static void NANFloatingRemember(NSDictionary *model,UIViewController *controller) {
    if (!NANFloatingEnabled()) return;
    if (!NANFloats) NANFloats=[NANFloatingManager new];
    [NANFloats remember:model controller:controller];
    [NANFloats refresh];
}
static void NANFloatingAttend(NSString *fingerprint) { [NANFloats attend:fingerprint]; }
static void NANFloatingClear(void) { [NANFloats clear]; NANFloats=nil; }

'''+anchor)
# Remove the overlay immediately, then invoke the known LaunchServices method
# off the UI thread. Report failure on main and retain the notification bubble.
a=s.index('- (void)openTapped {')
b=s.index('\n- (void)dismissTapped {',a)
s=s[:a]+r'''- (void)openTapped {
    if (NANTestMode) { NANTestMode=NO; NANRemoveIsland(); return; }
    if (NANOpeningApplication || NANIsUILocked() || NANIslandView!=self || !self.bundleID.length) return;
    NSString *bundle=[self.bundleID copy],*fingerprint=[self.fingerprint copy];
    NANOpeningApplication=YES;
    NANRemoveIsland(); // No synchronous LaunchServices call on the UI thread.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.05*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        if (NANIsUILocked() || !NANBool(@"NotificationIslandEnabled",YES)) {
            NANOpeningApplication=NO; NANFloatingRefresh(); return;
        }
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            BOOL opened=NO;
            @try {
                Class cls=NSClassFromString(@"LSApplicationWorkspace");
                SEL shared=NSSelectorFromString(@"defaultWorkspace");
                id workspace=(cls && [cls respondsToSelector:shared])?((id(*)(id,SEL))objc_msgSend)(cls,shared):nil;
                SEL selector=NSSelectorFromString(@"openApplicationWithBundleID:");
                if ([workspace respondsToSelector:selector]) opened=((BOOL(*)(id,SEL,id))objc_msgSend)(workspace,selector,bundle);
            } @catch (__unused NSException *exception) {}
            dispatch_async(dispatch_get_main_queue(), ^{
                NANOpeningApplication=NO;
                if (opened) NANFloatingAttend(fingerprint);
                NANFloatingRefresh();
            });
        });
    });
}
'''+s[b:]
# Explicit expanded Dismiss is an attended item. Existing swipe, double-tap
# and timeout still dismiss only the large overlay, allowing later response.
rep('[_dismissButton addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchUpInside];','[_dismissButton addTarget:self action:@selector(attendedDismissTapped) forControlEvents:UIControlEventTouchUpInside];')
rep('- (void)dismissTapped {',r'''- (void)attendedDismissTapped {
    if (!NANTestMode) NANFloatingAttend(self.fingerprint);
    [self dismissTapped];
}
- (void)dismissTapped {''')
rep('        // Submission is not proof of delivery. The native system owns completion.\n        NANAnimateDismiss();','        // Submission is not proof of delivery. The native system owns completion.\n        NANFloatingAttend(self.fingerprint);\n        NANAnimateDismiss();')
# Update bubble visibility only after island teardown, avoiding a flash
# between two successive notification cards.
rep('    NANExpanded = NO;\n    NANTestMode = NO;\n}',r'''    NANExpanded = NO;
    NANTestMode = NO;
    dispatch_async(dispatch_get_main_queue(),^{ NANFloatingRefresh(); });
}''')
rep('    if (!test && [NANSeenFingerprints containsObject:fingerprint]) {','    if (!test && !NANFloatingReopen && [NANSeenFingerprints containsObject:fingerprint]) {')
rep('    [card setExpanded:NO animated:NO];\n    if (CGRectIsEmpty(card.frame))','    [card setExpanded:NANFloatingReopen animated:NO];\n    if (CGRectIsEmpty(card.frame))')
rep('    NANAnimateShow(card);\n    NANStartTimers();\n    return YES;',r'''    NANFloatingRemember(model,shortLook);
    NANFloatingRefresh();
    NANAnimateShow(card);
    NANStartTimers();
    if (NANFloatingReopen) {
        [NANHideTimer invalidate];
        NANHideTimer=[NSTimer scheduledTimerWithTimeInterval:20.0 repeats:NO block:^(__unused NSTimer *timer){ NANAnimateDismiss(); }];
    }
    return YES;''')
rep('        if (!NANBool(@"NotificationIslandEnabled", YES)) { NANRestoreAllBanners(); NANRemoveIsland(); return; }','        if (!NANBool(@"NotificationIslandEnabled", YES)) { NANFloatingClear(); NANRestoreAllBanners(); NANRemoveIsland(); return; }\n        NANFloatingRefresh();')
rep('        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) [(NANNotificationCard *)NANIslandView applyPrivacy];\n    });\n}\n\n%hook SBSystemApertureWindow','        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) [(NANNotificationCard *)NANIslandView applyPrivacy];\n        NANFloatingRefresh();\n    });\n}\n\n%hook SBSystemApertureWindow')
# Reattach when the system window becomes usable after rotation/unlock.
rep('    NANSystemWindow = self;\n    if (NANIslandView.superview == self) {','    NANSystemWindow = self;\n    if (!NANIslandView && NANFloats.records.count && NANFloats.window.hidden) NANFloatingRefresh();\n    if (NANIslandView.superview == self) {')
rep('1.0.19 Banner Lifecycle loaded','1.0.20 Motion Bubbles loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.20 Motion Bubbles.")
