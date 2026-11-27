#!/usr/bin/env python3
"""1.0.10: dedicated UIKit reply host and customizable island silhouettes."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.10 missing anchor: "+a[:130])
    s=s.replace(a,b,1)
def between(a,b,new):
    global s
    i=s.index(a); j=s.index(b,i+len(a))
    s=s[:i]+new+s[j:]

# A real key-capable UIWindow is deliberately separate from SBSystemApertureWindow.
# Never alter global SpringBoard window behavior or intercept keyboard input.
rep("@interface NANNotificationCard : UIControl <UIGestureRecognizerDelegate>",r'''@interface NANReplyWindow : UIWindow
@end
@implementation NANReplyWindow
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)_canBecomeKeyWindow { return YES; }
@end

@interface NANReplyHostController : UIViewController
@property(nonatomic,strong) UITextField *field;
@property(nonatomic,strong) UIButton *sendButton;
@property(nonatomic,strong) UIButton *cancelButton;
@property(nonatomic,strong) UILabel *heading;
@property(nonatomic,strong) UILabel *contextLabel;
- (void)focusField;
@end
@implementation NANReplyHostController
- (void)loadView {
    UIView *root=[UIView new];
    root.backgroundColor=[UIColor colorWithWhite:0 alpha:.18];
    self.view=root;
    UIView *panel=[UIView new];
    panel.translatesAutoresizingMaskIntoConstraints=NO;
    panel.backgroundColor=UIColor.secondarySystemBackgroundColor;
    panel.layer.cornerRadius=28;
    panel.layer.cornerCurve=kCACornerCurveContinuous;
    panel.clipsToBounds=YES;
    panel.layer.borderWidth=1.0/UIScreen.mainScreen.scale;
    panel.layer.borderColor=UIColor.separatorColor.CGColor;
    [root addSubview:panel];
    self.heading=[UILabel new];
    self.heading.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.heading.textColor=UIColor.labelColor;
    self.contextLabel=[UILabel new];
    self.contextLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
    self.contextLabel.textColor=UIColor.secondaryLabelColor;
    self.contextLabel.numberOfLines=2;
    self.field=[UITextField new];
    self.field.font=[UIFont systemFontOfSize:16];
    self.field.borderStyle=UITextBorderStyleRoundedRect;
    self.field.backgroundColor=UIColor.tertiarySystemBackgroundColor;
    self.field.textColor=UIColor.labelColor;
    self.field.placeholder=@"Type your reply";
    self.field.returnKeyType=UIReturnKeySend;
    self.field.accessibilityLabel=@"Notification reply";
    self.field.enablesReturnKeyAutomatically=YES;
    [self.field addTarget:self action:@selector(focusField) forControlEvents:UIControlEventTouchDown];
    self.sendButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.sendButton setTitle:@"Send" forState:UIControlStateNormal];
    [self.sendButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.sendButton.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.sendButton.backgroundColor=UIColor.systemBlueColor;
    self.sendButton.layer.cornerRadius=18;
    self.cancelButton=[UIButton buttonWithType:UIButtonTypeSystem];
    [self.cancelButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    self.cancelButton.tintColor=UIColor.secondaryLabelColor;
    self.cancelButton.accessibilityLabel=@"Cancel reply";
    UIView *spacer=[UIView new];
    UIStackView *header=[[UIStackView alloc] initWithArrangedSubviews:@[self.heading,spacer,self.cancelButton]];
    header.axis=UILayoutConstraintAxisHorizontal; header.alignment=UIStackViewAlignmentCenter;
    UIStackView *input=[[UIStackView alloc] initWithArrangedSubviews:@[self.field,self.sendButton]];
    input.axis=UILayoutConstraintAxisHorizontal; input.spacing=8; input.alignment=UIStackViewAlignmentFill;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[header,self.contextLabel,input]];
    stack.axis=UILayoutConstraintAxisVertical; stack.spacing=9;
    stack.translatesAutoresizingMaskIntoConstraints=NO;
    [panel addSubview:stack];
    UILayoutGuide *safe=root.safeAreaLayoutGuide;
    NSLayoutConstraint *preferred=[panel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:10];
    preferred.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [panel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [panel.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:2],
        preferred,
        [panel.bottomAnchor constraintLessThanOrEqualToAnchor:root.keyboardLayoutGuide.topAnchor constant:-8],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-14],
        [self.cancelButton.widthAnchor constraintEqualToConstant:44],
        [self.cancelButton.heightAnchor constraintEqualToConstant:32],
        [self.sendButton.widthAnchor constraintEqualToConstant:66],
        [self.field.heightAnchor constraintEqualToConstant:44]
    ]];
}
- (void)focusField {
    if (self.view.window && !self.view.window.hidden) {
        if (!self.view.window.isKeyWindow) [self.view.window makeKeyWindow];
        [self.field becomeFirstResponder];
    }
}
@end

@interface NANNotificationCard : UIControl <UIGestureRecognizerDelegate>''')
rep("@property(nonatomic,weak) UIWindow *replyPreviousKeyWindow;",r'''@property(nonatomic,weak) UIWindow *replyPreviousKeyWindow;
@property(nonatomic,strong) NANReplyWindow *replyWindow;
@property(nonatomic,strong) NANReplyHostController *replyHost;''')
rep("- (void)finishReply;",r'''- (void)finishReply;
- (BOOL)showReplyHost;
- (void)retryReplyFocus;''')
# The original inline placeholder remains a tap target, but the true text field
# resides in the dedicated host. UIKit owns keyboard, selection, dictation.
rep("    _replyField.accessibilityLabel=@", "    _replyField.accessibilityLabel=@") if False else None
rep("    [self addSubview:_replyField];",r'''    [self addSubview:_replyField];
    [_replyField addTarget:self action:@selector(retryReplyFocus) forControlEvents:UIControlEventTouchDown];''')
between("- (void)finishReply {","\n- (void)willMoveToWindow:",r'''- (void)retryReplyFocus {
    if (self.replyAction && !NANIsUILocked() && NANIslandView==self) [self.replyHost focusField];
}
- (BOOL)showReplyHost {
    if (!self.replyAction || NANIsUILocked() || NANIslandView!=self) return NO;
    UIWindow *previous=nil;
    UIWindowScene *scene=nil;
    // Prefer the current key window's own active scene, never a background scene.
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class] ||
            candidate.activationState!=UISceneActivationStateForegroundActive) continue;
        UIWindowScene *ws=(UIWindowScene *)candidate;
        if (ws.screen!=UIScreen.mainScreen) continue;
        for (UIWindow *window in ws.windows) {
            if (window.isKeyWindow && window!=self.window && !window.hidden) {
                previous=window; scene=ws; break;
            }
        }
        if (previous) break;
    }
    if (!scene) scene=self.window.windowScene;
    if (!scene || scene.screen!=UIScreen.mainScreen) return NO;
    if (!previous) for (UIWindow *window in scene.windows) if (window.isKeyWindow) { previous=window; break; }
    NANReplyWindow *window=[[NANReplyWindow alloc] initWithWindowScene:scene];
    window.frame=scene.coordinateSpace.bounds;
    window.backgroundColor=UIColor.clearColor;
    window.windowLevel=MAX(UIWindowLevelAlert+1,self.window.windowLevel+1);
    NANReplyHostController *host=[NANReplyHostController new];
    window.rootViewController=host;
    [host loadViewIfNeeded];
    host.heading.text=[NSString stringWithFormat:@"Reply · %@",self.appLabel.text ?: @"Notification"];
    host.contextLabel.text=self.bodyLabel.text;
    [host.sendButton addTarget:self action:@selector(submitReply) forControlEvents:UIControlEventTouchUpInside];
    [host.cancelButton addTarget:self action:@selector(cancelReply) forControlEvents:UIControlEventTouchUpInside];
    [host.field addTarget:self action:@selector(submitReply) forControlEvents:UIControlEventEditingDidEndOnExit];
    self.replyPreviousKeyWindow=previous;
    self.replyWindow=window;
    self.replyHost=host;
    [window makeKeyAndVisible];
    [host.view setNeedsLayout]; [host.view layoutIfNeeded];
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf retryReplyFocus]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.22*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        typeof(self) card=weakSelf;
        if (card.replyWindow==window && !host.field.isFirstResponder) [card retryReplyFocus];
    });
    return YES;
}
- (void)finishReply {
    NANReplyWindow *window=self.replyWindow;
    UIWindow *previous=self.replyPreviousKeyWindow;
    BOOL wasKey=window.isKeyWindow;
    [self.replyHost.field resignFirstResponder];
    self.replyHost.field.text=@"";
    self.replyHost.contextLabel.text=@"";
    window.hidden=YES;
    window.rootViewController=nil;
    self.replyHost=nil; self.replyWindow=nil; self.replyPreviousKeyWindow=nil;
    [self.replyField resignFirstResponder];
    self.replyField.text=@"";
    self.replyAction=nil;
    self.replyField.hidden=YES; self.replySend.hidden=YES; self.replyCancel.hidden=YES;
    if (wasKey && previous && !previous.hidden && previous.windowScene==window.windowScene) [previous makeKeyWindow];
}
''')
rep("NSString *text=[self.replyField.text stringByTrimmingCharactersInSet:", "NSString *text=[(self.replyHost.field.text ?: self.replyField.text) stringByTrimmingCharactersInSet:")
between("    UIWindow *previous=nil;\n    for (UIWindow *w in self.window.windowScene.windows)", "\n}\n\n- (void)applyModel:",r'''    if (![self showReplyHost]) {
        [self cancelReply];
        self.nativeActionStatus.text=@"Reply window unavailable";
        self.nativeActionStatus.hidden=NO;
        [self setNeedsLayout];
    }''')
# Do not replace a draft with a new notification; leave that notification native.
rep("    NANRemoveIslandOnMain();\n    NANTestMode = test;",r'''    if ([NANIslandView isKindOfClass:NANNotificationCard.class] && ((NANNotificationCard *)NANIslandView).replyAction) return NO;
    NANRemoveIslandOnMain();
    NANTestMode = test;''')
# Explicitly tear down the host on removal rather than relying on view callbacks.
rep("    [NANIslandView removeFromSuperview];",r'''    if ([NANIslandView isKindOfClass:NANNotificationCard.class]) [(NANNotificationCard *)NANIslandView finishReply];
    [NANIslandView removeFromSuperview];''')
# Respect lock and preference changes; the timer must not expire while composing.
rep("            [card applyPrivacy];\n            [NANHideTimer invalidate];",r'''            [card applyPrivacy];
            if (card.replyAction) {
                if (!NANBool(@"NotificationIslandNativeActions",YES)) [card cancelReply];
                else return;
            }
            [NANHideTimer invalidate];''')
# Visual shape is independent of existing color/blur mode. Default Fluid.
rep("static BOOL NANIsDocked(void) {",r'''static NSInteger NANShapeStyle(void) {
    return NANInteger(@"NotificationIslandShapeStyle",1,0,3);
}
static BOOL NANIsDocked(void) {
    if (NANShapeStyle()>=2) return NO;''')
rep("    CGFloat w = CGRectGetWidth(b), h = CGRectGetHeight(b);",r'''    CGFloat w = CGRectGetWidth(b), h = CGRectGetHeight(b);
    if (NANShapeStyle()==1) {
        CGFloat center=w*.5, half=MIN(75.0,center-18.0);
        CGFloat l=center-half,r=center+half;
        CGFloat shoulder=MAX(25.0,reserve-17.0);
        CGFloat bottom=MIN(NANFloat(@"NotificationIslandCornerRadius",32,16,40),MIN(w*.25,(h-reserve)*.45));
        CGFloat side=MIN(32.0,MAX(7.0,(l-3.0)*.72));
        CGFloat y=MIN(h-bottom,shoulder+side);
        CGFloat cap=MIN(21.0,half*.45);
        UIBezierPath *p=[UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(l+cap,0)];
        [p addLineToPoint:CGPointMake(r-cap,0)];
        [p addCurveToPoint:CGPointMake(r,cap) controlPoint1:CGPointMake(r,0) controlPoint2:CGPointMake(r,cap*.45)];
        [p addLineToPoint:CGPointMake(r,MAX(cap,shoulder-13))];
        [p addCurveToPoint:CGPointMake(w-side,shoulder) controlPoint1:CGPointMake(r,shoulder+1) controlPoint2:CGPointMake(w-side,shoulder)];
        [p addCurveToPoint:CGPointMake(w,y) controlPoint1:CGPointMake(w-side*.25,shoulder) controlPoint2:CGPointMake(w,y-side*.35)];
        [p addLineToPoint:CGPointMake(w,h-bottom)];
        [p addCurveToPoint:CGPointMake(w-bottom,h) controlPoint1:CGPointMake(w,h-bottom*.35) controlPoint2:CGPointMake(w-bottom*.35,h)];
        [p addLineToPoint:CGPointMake(bottom,h)];
        [p addCurveToPoint:CGPointMake(0,h-bottom) controlPoint1:CGPointMake(bottom*.35,h) controlPoint2:CGPointMake(0,h-bottom*.35)];
        [p addLineToPoint:CGPointMake(0,y)];
        [p addCurveToPoint:CGPointMake(side,shoulder) controlPoint1:CGPointMake(0,y-side*.35) controlPoint2:CGPointMake(side*.25,shoulder)];
        [p addCurveToPoint:CGPointMake(l,MAX(cap,shoulder-13)) controlPoint1:CGPointMake(side,shoulder) controlPoint2:CGPointMake(l,shoulder+1)];
        [p addLineToPoint:CGPointMake(l,cap)];
        [p addCurveToPoint:CGPointMake(l+cap,0) controlPoint1:CGPointMake(l,cap*.45) controlPoint2:CGPointMake(l,0)];
        [p closePath]; return p;
    }''')
# Make the detached shapes visually distinct while preserving adjustable widths.
rep("    if (expanded) height += NANActionReserve();",r'''    if (NANShapeStyle()==2 && !expanded) { width=MIN(width,300.0); height=MAX(height,64.0); }
    if (NANShapeStyle()==3) width=MIN(width,maxWidth-8.0);
    if (expanded) height += NANActionReserve();''')
rep("    if (!docked) self.layer.cornerCurve=kCACornerCurveContinuous;",r'''    NSInteger shape=NANShapeStyle();
    if (!docked) {
        self.layer.cornerCurve=kCACornerCurveContinuous;
        if (shape==2 && !NANExpanded) self.layer.cornerRadius=MIN(self.bounds.size.height*.5,self.bounds.size.width*.5);
        if (shape==3) self.layer.cornerRadius=MIN(NANFloat(@"NotificationIslandCornerRadius",32,16,40),MIN(self.bounds.size.height*.5,self.bounds.size.width*.5));
    }
    self.layer.borderWidth=(!docked && shape==3)?1.0/UIScreen.mainScreen.scale:0;
    self.layer.borderColor=[UIColor colorWithWhite:1 alpha:.22].CGColor;''')
# Maintain readable text in the legacy light palette, including new shape styles.
rep("    self.backgroundEffectView.hidden = (mode == 0);",r'''    UIColor *primary=mode==2?UIColor.blackColor:UIColor.whiteColor;
    self.appLabel.textColor=primary; self.titleLabel.textColor=primary;
    self.bodyLabel.textColor=[primary colorWithAlphaComponent:.86];
    self.timeLabel.textColor=[primary colorWithAlphaComponent:.58];
    self.backgroundEffectView.hidden = (mode == 0);''')
rep("1.0.9 Inline Actions loaded","1.0.10 Island Studio loaded")
p.write_text(s)
print("Prepared Notify Island 1.0.10 Island Studio.")
