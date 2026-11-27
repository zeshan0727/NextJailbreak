#!/usr/bin/env python3
"""Native action bridge and expanded double tap, atop the 1.0.7 engine."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.8 missing anchor: "+a[:120])
    s=s.replace(a,b,1)
rep("static BOOL NANIsDocked(void) {",r'''// Action discovery is read-only. The original live notification controller
// remains the sole execution authority; no fabricated responses or action IDs.
static NSArray *NANActionsForRequest(id request) {
    Class cls = NSClassFromString(@"NCNotificationAction");
    if (!request || !cls) return @[];
    NSMutableArray *sources=[NSMutableArray new];
    id preferred=NANSafeValue(request,@"defaultEnvironmentActions");
    if ([preferred isKindOfClass:NSArray.class] && [preferred count]) {
        [sources addObject:preferred];
    } else {
        id dict=NANSafeValue(request,@"supplementaryActions");
        if ([dict isKindOfClass:NSDictionary.class]) {
            for (id group in [dict allValues])
                if ([group isKindOfClass:NSArray.class]) [sources addObject:group];
        }
        id minimal=NANSafeValue(request,@"minimalEnvironmentActions");
        if ([minimal isKindOfClass:NSArray.class]) [sources addObject:minimal];
    }
    NSMutableArray *result=[NSMutableArray new];
    NSMutableSet *ids=[NSMutableSet new];
    NSArray *excluded=@[@"defaultAction",@"clearAction",@"closeAction",@"cancelAction",@"silenceAction"];
    NSMutableSet *excludedIDs=[NSMutableSet new];
    for (NSString *key in excluded) {
        NSString *identifier=NANString(NANSafeValue(request,key),@[@"identifier"]);
        if (identifier.length) [excludedIDs addObject:identifier];
    }
    for (NSArray *group in sources) for (id action in group) {
        if (![action isKindOfClass:cls]) continue;
        NSString *identifier=NANString(action,@[@"identifier"]);
        NSString *title=NANString(action,@[@"title"]);
        if (!identifier.length || !title.length || [ids containsObject:identifier] || [excludedIDs containsObject:identifier]) continue;
        if ([NANSafeValue(action,@"systemAction") boolValue]) continue;
        [ids addObject:identifier]; [result addObject:action];
        if (result.count>=8) return result;
    }
    return result;
}
static BOOL NANActionMethodMatches(id target, SEL selector, NSUInteger arguments) {
    if (!target || ![target respondsToSelector:selector]) return NO;
    NSMethodSignature *sig=[target methodSignatureForSelector:selector];
    return sig && sig.numberOfArguments==arguments && strcmp(sig.methodReturnType,@encode(void))==0;
}
static BOOL NANActionContextMatches(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded || !controller.view.window) return NO;
    id req=NANSafeValue(controller,@"notificationRequest");
    NSString *section=NANString(req,@[@"sectionIdentifier",@"_sectionIdentifier"]);
    NSString *identifier=NANString(req,@[@"notificationIdentifier",@"requestIdentifier",@"identifier"]);
    return identifier.length && [identifier isEqualToString:NANCurrentModel[@"requestIdentifier"]] &&
           [section isEqualToString:NANCurrentModel[@"bundleID"]];
}
static CGFloat NANActionReserve(void) {
    if (NANTestMode || NANIsUILocked() || !NANBool(@"NotificationIslandNativeActions",YES)) return 0;
    NSArray *actions=NANCurrentModel[@"nativeActions"];
    return actions.count ? 46.0 : 0.0;
}
static BOOL NANIsDocked(void) {''')
# Existing frame keeps a constant content area for the original buttons.
rep("    width = MIN(width, maxWidth); height = MIN(height, maxHeight);",r'''    if (expanded) height += NANActionReserve();
    width = MIN(width, maxWidth); height = MIN(height, maxHeight);
    // Preserve a readable expanded card when the docked height is limited.
    if (docked) height = MIN(height, maxHeight + CGRectGetMinY(safe) - CGRectGetMinY(bounds) - 8.0 - NANDockReserve());''')
rep("@interface NANNotificationCard : UIControl","@interface NANNotificationCard : UIControl <UIGestureRecognizerDelegate>")
rep("@property(nonatomic,strong) CAShapeLayer *apertureMask;",r'''@property(nonatomic,strong) CAShapeLayer *apertureMask;
@property(nonatomic,strong) UIScrollView *nativeActionScroll;
@property(nonatomic,strong) UILabel *nativeActionStatus;
@property(nonatomic,strong) NSArray<UIButton *> *nativeActionButtons;
@property(nonatomic,strong) NSArray *nativeActions;
@property(nonatomic,strong) UITapGestureRecognizer *doubleTap;
@property(nonatomic) BOOL actionSubmitted;
@property(nonatomic) BOOL lastActionLocked;''')
rep("- (void)applyModel:(NSDictionary *)model;",r'''- (void)applyModel:(NSDictionary *)model;
- (void)buildNativeActions;
- (void)nativeActionTapped:(UIButton *)button;
- (void)doubleTapDismiss:(UITapGestureRecognizer *)recognizer;''')
rep("    [self addGestureRecognizer:longPress];",r'''    [self addGestureRecognizer:longPress];
    _doubleTap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTapDismiss:)];
    _doubleTap.numberOfTapsRequired=2;
    _doubleTap.delegate=self;
    _doubleTap.cancelsTouchesInView=YES;
    [self addGestureRecognizer:_doubleTap];
    _nativeActionScroll=[UIScrollView new];
    _nativeActionScroll.showsHorizontalScrollIndicator=NO;
    _nativeActionScroll.alwaysBounceHorizontal=NO;
    _nativeActionScroll.hidden=YES;
    [self addSubview:_nativeActionScroll];
    _nativeActionStatus=[UILabel new];
    _nativeActionStatus.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _nativeActionStatus.textColor=UIColor.secondaryLabelColor;
    _nativeActionStatus.textAlignment=NSTextAlignmentCenter;
    _nativeActionStatus.adjustsFontSizeToFitWidth=YES;
    _nativeActionStatus.minimumScaleFactor=.65;
    _nativeActionStatus.hidden=YES;
    [self addSubview:_nativeActionStatus];''')
rep("- (void)applyModel:(NSDictionary *)model {",r'''- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch {
    if (recognizer != self.doubleTap) return YES;
    if (!NANExpanded || NANAnimating || NANClosing) return NO;
    for (UIView *v=touch.view; v && v!=self; v=v.superview) {
        if ([v isKindOfClass:UIControl.class] || v==self.nativeActionScroll) return NO;
    }
    return YES;
}
- (void)doubleTapDismiss:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state==UIGestureRecognizerStateRecognized && NANExpanded && !NANAnimating) NANAnimateDismiss();
}
- (void)buildNativeActions {
    self.nativeActions=[NANCurrentModel[@"nativeActions"] isKindOfClass:NSArray.class] ? NANCurrentModel[@"nativeActions"] : @[];
    for (UIView *v in self.nativeActionScroll.subviews.copy) [v removeFromSuperview];
    NSMutableArray *buttons=[NSMutableArray new];
    NSInteger i=0;
    for (id action in self.nativeActions) {
        UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
        NSString *title=NANString(action,@[@"title"]);
        [b setTitle:title forState:UIControlStateNormal];
        b.accessibilityLabel=title; b.tag=i++;
        b.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        b.titleLabel.adjustsFontSizeToFitWidth=YES;
        b.titleLabel.minimumScaleFactor=.75;
        b.backgroundColor=[UIColor colorWithWhite:.22 alpha:1];
        UIColor *t=[NANSafeValue(action,@"destructiveAction") boolValue]?UIColor.systemRedColor:UIColor.whiteColor;
        [b setTitleColor:t forState:UIControlStateNormal];
        b.layer.cornerRadius=10;
        [b addTarget:self action:@selector(nativeActionTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.nativeActionScroll addSubview:b]; [buttons addObject:b];
    }
    self.nativeActionButtons=buttons;
}
- (void)nativeActionTapped:(UIButton *)button {
    // All execution is explicit and restricted to the authenticated live
    // request. Never send a response for a recycled notification controller.
    if (self.actionSubmitted || NANTestMode || NANIsUILocked() || NANAnimating || NANClosing ||
        !NANBool(@"NotificationIslandNativeActions",YES) || NANIslandView!=self || !NANExpanded) return;
    NSInteger index=button.tag;
    if (index<0 || index>=(NSInteger)self.nativeActions.count) return;
    id selected=self.nativeActions[index];
    NSString *identifier=NANString(selected,@[@"identifier"]);
    UIViewController *controller=NANCurrentShortLook;
    if (!NANActionContextMatches(controller)) {
        self.nativeActionStatus.text=@"Use the original notification in Notification Center";
        self.nativeActionStatus.hidden=NO; self.nativeActionScroll.hidden=YES;
        return;
    }
    id request=NANSafeValue(controller,@"notificationRequest");
    id liveAction=nil;
    for (id action in NANActionsForRequest(request)) {
        if ([NANString(action,@[@"identifier"]) isEqualToString:identifier]) { liveAction=action; break; }
    }
    if (!liveAction) return;
    // Unknown/nonstandard actions, destructive actions, and text input use
    // the native long-look. iOS owns the keyboard, reply response, and auth.
    id behavior=NANSafeValue(liveAction,@"behavior");
    id parameters=NANSafeValue(liveAction,@"behaviorParameters");
    BOOL simple=[behavior isKindOfClass:NSNumber.class] && [behavior unsignedLongLongValue]==0 &&
        (!parameters || ([parameters isKindOfClass:NSDictionary.class] && ![parameters count])) &&
        ![NANSafeValue(liveAction,@"destructiveAction") boolValue] &&
        ![NANSafeValue(liveAction,@"requiresAuthentication") boolValue];
    SEL execute=NSSelectorFromString(@"_askDelegateToExecuteAction:withParameters:animated:");
    SEL longLook=NSSelectorFromString(@"presentLongLookAnimated:completion:");
    id delegate=NANSafeValue(controller,@"delegate");
    BOOL direct=simple && delegate && NANActionMethodMatches(controller,execute,5);
    BOOL handoff=NANActionMethodMatches(controller,longLook,4);
    if (!direct && !handoff) {
        self.nativeActionStatus.text=@"Open the original notification to use its actions";
        self.nativeActionStatus.hidden=NO; self.nativeActionScroll.hidden=YES;
        return;
    }
    self.actionSubmitted=YES;
    // Restore only the native transient banner, never manipulate list history.
    NANRestoreBanner(controller.view);
    @try {
        if (direct) {
            ((void(*)(id,SEL,id,id,BOOL))objc_msgSend)(controller,execute,liveAction,nil,YES);
        } else {
            ((void(*)(id,SEL,BOOL,id))objc_msgSend)(controller,longLook,YES,nil);
        }
    } @catch (__unused NSException *exception) {
        self.actionSubmitted=NO;
        self.nativeActionStatus.text=@"Action unavailable; use Notification Center";
        self.nativeActionStatus.hidden=NO; self.nativeActionScroll.hidden=YES;
        return;
    }
    // No success claim: the app/system determines completion.
    NANRemoveIsland();
}

- (void)applyModel:(NSDictionary *)model {''')
rep("    self.bundleID = [model", "    [self buildNativeActions];\n    self.bundleID = [model")
rep("    self.openButton.enabled = !locked || NANTestMode;",r'''    self.openButton.enabled = !locked || NANTestMode;
    // Do not reveal or enable application actions while authentication is
    // required. Reflow when authentication changes, not on every timer tick.
    if (locked != self.lastActionLocked) {
        self.lastActionLocked=locked;
        self.nativeActionStatus.hidden=YES;
        if (locked) self.nativeActionScroll.hidden=YES;
        if (!NANAnimating && !NANClosing && NANExpanded) [self setExpanded:YES animated:NO];
        [self setNeedsLayout];
    }''')
# Existing layout from 1.0.7 offsets all text below aperture.
rep("    CGFloat scale = NANFloat(@\"NotificationIslandTextScale\", 1.0, 0.80, 1.35);",r'''    CGFloat actionHeight = NANExpanded && !self.lastActionLocked && self.nativeActions.count &&
        NANBool(@"NotificationIslandNativeActions",YES) && contentHeight >= 171 ? 46.0 : 0.0;
    // Keep the old text area and add the app action strip above the fallback row.
    contentHeight -= actionHeight;
    CGFloat scale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);''')
rep("    if (docked) {\n        for (UIView *v in @[self.iconView",r'''    self.nativeActionScroll.hidden = actionHeight==0 || !self.nativeActionStatus.hidden;
    if (actionHeight==0) self.nativeActionStatus.hidden=YES;
    if (actionHeight>0) {
        CGFloat actionY=CGRectGetMinY(self.openButton.frame);
        CGFloat stripW=MAX(0,self.bounds.size.width-20.0);
        self.nativeActionScroll.frame=CGRectMake(10,actionY+reserve,stripW,38);
        self.nativeActionStatus.frame=self.nativeActionScroll.frame;
        CGFloat x=0, gap=8;
        CGFloat equal=(stripW-gap*MAX(0,(NSInteger)self.nativeActionButtons.count-1))/MAX(1,self.nativeActionButtons.count);
        for (UIButton *button in self.nativeActionButtons) {
            CGFloat width=MAX(86,MIN(190,MAX(equal,[button.titleLabel.text sizeWithAttributes:@{NSFontAttributeName:button.titleLabel.font}].width+24)));
            button.frame=CGRectMake(x,0,width,38); x+=width+gap;
        }
        self.nativeActionScroll.contentSize=CGSizeMake(MAX(stripW,x-gap),38);
        self.openButton.frame=CGRectOffset(self.openButton.frame,0,actionHeight);
        self.dismissButton.frame=CGRectOffset(self.dismissButton.frame,0,actionHeight);
    }
    if (docked) {
        for (UIView *v in @[self.iconView''')
rep('        @"deliveryDate": hasDate ? timestamp : NSNull.null','        @"deliveryDate": hasDate ? timestamp : NSNull.null,\n        @"requestIdentifier": identifier ?: @"",\n        @"nativeActions": NANActionsForRequest(request)')
# If a native list view for the very same request becomes available, use
# that live controller for user-selected actions even after the banner ends.
rep('    BOOL banner = NANIsTransientBanner(controller);',r'''    BOOL banner = NANIsTransientBanner(controller);
    if (NANIslandView && !NANTestMode && [NANFingerprint(NANCurrentModel) isEqualToString:NANFingerprint(model)] &&
        !banner && NANActionContextMatches(controller)) {
        NANCurrentShortLook=controller;
        return;
    }''')
rep("1.0.7 Island Integration loaded","1.0.8 Adaptive Actions loaded")
p.write_text(s)
print("Prepared Notify Island 1.0.8 Adaptive Actions.")
