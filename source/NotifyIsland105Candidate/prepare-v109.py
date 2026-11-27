#!/usr/bin/env python3
"""1.0.9: preserve authentic notification requests, inline reply, rounding, shuffled previews."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.9 missing anchor: "+a[:140])
    s=s.replace(a,b,1)
def between(a,b,new):
    global s
    i=s.index(a); j=s.index(b,i+len(a))
    s=s[:i]+new+s[j:]

# Use real request action arrays from every environment, not only the first nonempty one.
between("    id preferred=NANSafeValue(request", "    NSMutableArray *result",r'''    for (NSString *key in @[@"defaultEnvironmentActions",@"minimalEnvironmentActions",@"supplementaryActions",@"actions"]) {
        id root=NANSafeValue(request,key);
        NSMutableArray *pending=[NSMutableArray new];
        if (root) [pending addObject:root];
        NSUInteger budget=128;
        while (pending.count && budget--) {
            id value=pending.lastObject; [pending removeLastObject];
            if ([value isKindOfClass:NSArray.class]) {
                if ([value count] <= 128) [pending addObjectsFromArray:value];
                NSMutableArray *direct=[NSMutableArray new];
                for (id entry in value) if ([entry isKindOfClass:cls]) [direct addObject:entry];
                if (direct.count) [sources addObject:direct];
            } else if ([value isKindOfClass:NSDictionary.class] && [value count]<=128) {
                [pending addObjectsFromArray:[value allValues]];
            } else if ([value isKindOfClass:cls]) {
                [sources addObject:@[value]];
            }
        }
    }
''')
rep('        @"nativeActions": NANActionsForRequest(request)', '        @"nativeActions": NANActionsForRequest(request),\n        @"nativeRequest": request')
rep("static BOOL NANActionContextMatches(UIViewController *controller) {",r'''static BOOL NANRequestMatches(id req) {
    if (!req || NANTestMode) return NO;
    NSString *section=NANString(req,@[@"sectionIdentifier",@"_sectionIdentifier"]);
    NSString *identifier=NANString(req,@[@"notificationIdentifier",@"requestIdentifier",@"identifier"]);
    return identifier.length && [identifier isEqualToString:NANCurrentModel[@"requestIdentifier"]] &&
           [section isEqualToString:NANCurrentModel[@"bundleID"]];
}
// Keep the original in-memory request (never a synthetic one) even after a
// transient banner is recycled. Use SpringBoard's authenticated dispatcher,
// not direct app injection. Runtime signature checks are intentionally strict.
static BOOL NANDispatchRealAction(id request,id action,NSDictionary *parameters) {
    if (NANIsUILocked() || !NANRequestMatches(request)) return NO;
    id wrapper=NANSafeValue(UIApplication.sharedApplication,@"notificationDispatcher");
    id dispatcher=NANSafeValue(wrapper,@"dispatcher");
    id destination=NANSafeValue(wrapper,@"bannerDestination");
    SEL selector=NSSelectorFromString(@"destination:executeAction:forNotificationRequest:requestAuthentication:withParameters:completion:");
    if (destination && NANActionMethodMatches(dispatcher,selector,8)) {
        NSMethodSignature *sig=[dispatcher methodSignatureForSelector:selector];
        BOOL objects=YES;
        for (NSUInteger i=2;i<8;i++) if (i!=5 && [sig getArgumentTypeAtIndex:i][0]!='@') objects=NO;
        const char *auth=[sig getArgumentTypeAtIndex:5];
        if (objects && (auth[0]=='B' || auth[0]=='c')) {
            @try {
                void (^completion)(void)=^{};
                ((void(*)(id,SEL,id,id,id,BOOL,id,id))objc_msgSend)(dispatcher,selector,destination,action,request,YES,parameters,completion);
                return YES;
            } @catch (__unused NSException *e) {
                // Never retry an execution after an exception; it might have been submitted.
                return NO;
            }
        }
    }
    // Fallback only to a current, exactly matching native controller.
    UIViewController *controller=NANCurrentShortLook;
    SEL execute=NSSelectorFromString(@"_askDelegateToExecuteAction:withParameters:animated:");
    if (controller && controller.isViewLoaded && controller.view.window &&
        NANRequestMatches(NANSafeValue(controller,@"notificationRequest")) &&
        NANSafeValue(controller,@"delegate") && NANActionMethodMatches(controller,execute,5)) {
        NSMethodSignature *sig=[controller methodSignatureForSelector:execute];
        const char *anim=[sig getArgumentTypeAtIndex:4];
        if ([sig getArgumentTypeAtIndex:2][0]!='@' || [sig getArgumentTypeAtIndex:3][0]!='@' || (anim[0]!='B' && anim[0]!='c')) return NO;
        @try {
            ((void(*)(id,SEL,id,id,BOOL))objc_msgSend)(controller,execute,action,parameters,YES);
            return YES;
        } @catch (__unused NSException *e) { return NO; }
    }
    return NO;
}
static BOOL NANActionContextMatches(UIViewController *controller) {''')
# The native bridge has an explicit send button. No fake reply action, no
# automatic action execution, and no sending from locked/test states.
rep("@property(nonatomic) BOOL actionSubmitted;",r'''@property(nonatomic) BOOL actionSubmitted;
@property(nonatomic,strong) UITextField *replyField;
@property(nonatomic,strong) UIButton *replySend;
@property(nonatomic,strong) UIButton *replyCancel;
@property(nonatomic,strong) id replyAction;
@property(nonatomic,weak) UIWindow *replyPreviousKeyWindow;''')
rep("- (void)nativeActionTapped:(UIButton *)button;",r'''- (void)nativeActionTapped:(UIButton *)button;
- (void)submitReply;
- (void)cancelReply;
- (void)finishReply;
- (void)executeRealAction:(id)action text:(NSString *)text;''')
rep("    _nativeActionStatus.hidden=YES;\n    [self addSubview:_nativeActionStatus];",r'''    _nativeActionStatus.hidden=YES;
    [self addSubview:_nativeActionStatus];
    _replyField=[UITextField new];
    _replyField.borderStyle=UITextBorderStyleRoundedRect;
    _replyField.placeholder=@"Type your reply";
    _replyField.textColor=UIColor.labelColor;
    _replyField.backgroundColor=UIColor.systemBackgroundColor;
    _replyField.font=[UIFont systemFontOfSize:14];
    _replyField.hidden=YES;
    _replyField.accessibilityLabel=@"Notification reply";
    [self addSubview:_replyField];
    _replySend=[UIButton buttonWithType:UIButtonTypeSystem];
    [_replySend setTitle:@"Send" forState:UIControlStateNormal];
    [_replySend setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _replySend.backgroundColor=UIColor.systemBlueColor;
    _replySend.layer.cornerRadius=16;
    [_replySend addTarget:self action:@selector(submitReply) forControlEvents:UIControlEventTouchUpInside];
    _replySend.hidden=YES; [self addSubview:_replySend];
    _replyCancel=[UIButton buttonWithType:UIButtonTypeSystem];
    [_replyCancel setTitle:@"×" forState:UIControlStateNormal];
    _replyCancel.accessibilityLabel=@"Cancel reply";
    [_replyCancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _replyCancel.backgroundColor=[UIColor colorWithWhite:.22 alpha:1];
    _replyCancel.layer.cornerRadius=16;
    [_replyCancel addTarget:self action:@selector(cancelReply) forControlEvents:UIControlEventTouchUpInside];
    _replyCancel.hidden=YES; [self addSubview:_replyCancel];''')
between("- (void)nativeActionTapped:(UIButton *)button {","\n- (void)applyModel:",r'''- (void)finishReply {
    [self.replyField resignFirstResponder];
    self.replyField.text=@"";
    self.replyAction=nil;
    self.replyField.hidden=YES; self.replySend.hidden=YES; self.replyCancel.hidden=YES;
    UIWindow *previous=self.replyPreviousKeyWindow;
    self.replyPreviousKeyWindow=nil;
    if (previous && self.window.isKeyWindow && previous!=self.window) [previous makeKeyWindow];
}
- (void)willMoveToWindow:(UIWindow *)newWindow {
    if (!newWindow && self.replyAction) [self finishReply];
    [super willMoveToWindow:newWindow];
}
- (void)cancelReply {
    [self finishReply];
    [self setNeedsLayout];
    [NANHideTimer invalidate];
    NANHideTimer=[NSTimer scheduledTimerWithTimeInterval:NANDismissInterval() repeats:NO block:^(__unused NSTimer *timer){ NANAnimateDismiss(); }];
}
- (void)submitReply {
    if (!self.replyAction || self.actionSubmitted) return;
    NSString *text=[self.replyField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length || text.length>4000) return;
    id action=self.replyAction;
    [self finishReply];
    [self executeRealAction:action text:text];
}
- (void)executeRealAction:(id)selected text:(NSString *)text {
    if (self.actionSubmitted || NANTestMode || NANIsUILocked() || NANAnimating || NANClosing ||
        !NANBool(@"NotificationIslandNativeActions",YES) || NANIslandView!=self || !NANExpanded) return;
    id request=NANCurrentModel[@"nativeRequest"];
    if (!NANRequestMatches(request)) return;
    NSString *identifier=NANString(selected,@[@"identifier"]);
    id liveAction=nil;
    for (id action in NANActionsForRequest(request)) {
        if ([NANString(action,@[@"identifier"]) isEqualToString:identifier]) { liveAction=action; break; }
    }
    if (!liveAction) return;
    NSNumber *behavior=NANSafeValue(liveAction,@"behavior");
    if (![behavior isKindOfClass:NSNumber.class] || (behavior.unsignedLongLongValue!=0 && behavior.unsignedLongLongValue!=1)) return;
    if ((behavior.unsignedLongLongValue==1)!= (text.length>0)) return;
    NSDictionary *parameters=text.length?@{UIUserNotificationActionResponseTypedTextKey:text}:nil;
    self.actionSubmitted=YES;
    [NANHideTimer invalidate]; NANHideTimer=nil;
    if (NANDispatchRealAction(request,liveAction,parameters)) {
        // Submission is not proof of delivery. The native system owns completion.
        NANAnimateDismiss();
    } else {
        // Do not offer an automatic retry of an uncertain submission.
        self.nativeActionStatus.text=@"Action unavailable";
        self.nativeActionStatus.hidden=NO;
        [self setNeedsLayout];
        NANHideTimer=[NSTimer scheduledTimerWithTimeInterval:4 repeats:NO block:^(__unused NSTimer *timer){ NANAnimateDismiss(); }];
    }
}
- (void)nativeActionTapped:(UIButton *)button {
    if (self.actionSubmitted || NANTestMode || NANIsUILocked() || NANAnimating || NANClosing ||
        !NANBool(@"NotificationIslandNativeActions",YES) || NANIslandView!=self || !NANExpanded) return;
    NSInteger index=button.tag;
    if (index<0 || index>=(NSInteger)self.nativeActions.count) return;
    id selected=self.nativeActions[index];
    NSNumber *behavior=NANSafeValue(selected,@"behavior");
    if (![behavior isKindOfClass:NSNumber.class]) return;
    if (behavior.unsignedLongLongValue==0) { [self executeRealAction:selected text:nil]; return; }
    if (behavior.unsignedLongLongValue!=1 || !self.window || self.replyAction) return;
    self.replyAction=selected;
    self.nativeActionStatus.hidden=YES;
    [NANHideTimer invalidate]; NANHideTimer=nil;
    [self setNeedsLayout]; [self layoutIfNeeded];
    UIWindow *previous=nil;
    for (UIWindow *w in self.window.windowScene.windows) if (w.isKeyWindow && w!=self.window) { previous=w; break; }
    if (previous) { self.replyPreviousKeyWindow=previous; [self.window makeKeyWindow]; }
    if (![self.replyField becomeFirstResponder]) {
        [self cancelReply];
        self.nativeActionStatus.text=@"Reply keyboard unavailable";
        self.nativeActionStatus.hidden=NO;
        [self setNeedsLayout];
    }
}
''')
# Only show supported simple or text input actions; no misleading button for unknown behavior.
rep('        if ([NANSafeValue(action,@"systemAction") boolValue]) continue;',r'''        if ([NANSafeValue(action,@"systemAction") boolValue]) continue;
        id behavior=NANSafeValue(action,@"behavior");
        if (![behavior isKindOfClass:NSNumber.class] || [behavior unsignedLongLongValue]>1) continue;''')
rep("        if (locked) self.nativeActionScroll.hidden=YES;",r'''        if (locked) {
            self.nativeActionScroll.hidden=YES;
            if (self.replyAction) [self cancelReply];
        }''')
rep("    self.nativeActionScroll.hidden = actionHeight==0 || !self.nativeActionStatus.hidden;",r'''    BOOL replying=self.replyAction && actionHeight>0 && !self.lastActionLocked;
    self.replyField.hidden=!replying; self.replySend.hidden=!replying; self.replyCancel.hidden=!replying;
    self.nativeActionScroll.hidden = actionHeight==0 || !self.nativeActionStatus.hidden || replying;''')
rep("        self.nativeActionStatus.frame=self.nativeActionScroll.frame;",r'''        self.nativeActionStatus.frame=self.nativeActionScroll.frame;
        CGFloat replyY=actionY+reserve;
        CGFloat fieldW=MAX(40,stripW-104);
        self.replyField.frame=CGRectMake(10,replyY,fieldW,38);
        self.replySend.frame=CGRectMake(16+fieldW,replyY,62,38);
        self.replyCancel.frame=CGRectMake(84+fieldW,replyY,30,38);''')
# A rounded, configurable continuous silhouette for docked and detached cards.
rep("    CGFloat topRadius = 19.0, bottomRadius = MIN(24.0, (h-reserve)*0.4);",r'''    CGFloat roundness=NANFloat(@"NotificationIslandCornerRadius",32.0,16.0,40.0);
    CGFloat topRadius=MIN(24.0,roundness), bottomRadius=MIN(roundness,MIN(w*.25,(h-reserve)*.45));
    CGFloat shoulderCurve=MIN(roundness,MIN(36.0,MAX(12.0,(w/2-half-9)*.8)));''')
rep("    [path addLineToPoint:CGPointMake(w-20,shoulder)];\n    [path addQuadCurveToPoint:CGPointMake(w,reserve+5) controlPoint:CGPointMake(w,shoulder)];",r'''    [path addLineToPoint:CGPointMake(w-shoulderCurve,shoulder)];
    [path addQuadCurveToPoint:CGPointMake(w,shoulder+shoulderCurve) controlPoint:CGPointMake(w,shoulder)];''')
rep("    [path addLineToPoint:CGPointMake(0,reserve+5)];\n    [path addQuadCurveToPoint:CGPointMake(20,shoulder) controlPoint:CGPointMake(0,shoulder)];",r'''    [path addLineToPoint:CGPointMake(0,shoulder+shoulderCurve)];
    [path addQuadCurveToPoint:CGPointMake(shoulderCurve,shoulder) controlPoint:CGPointMake(0,shoulder)];''')
# Make the radius bounded by both dimensions so small layouts stay valid.
s=s.replace("MAX(18.0, MIN(self.bounds.size.height/2.0, NANExpanded ? 30.0 : 28.0))","MIN(NANFloat(@\"NotificationIslandCornerRadius\",32,16,40),MIN(self.bounds.size.height/2.0,self.bounds.size.width/2.0))")
s=s.replace("MAX(18.0, MIN(frame.size.height / 2.0, expanded ? 30.0 : 28.0))","MIN(NANFloat(@\"NotificationIslandCornerRadius\",32,16,40),MIN(frame.size.height/2.0,frame.size.width/2.0))")
s=s.replace("MAX(18.0, MIN(target.size.height/2.0, NANExpanded ? 30.0 : 28.0))","MIN(NANFloat(@\"NotificationIslandCornerRadius\",32,16,40),MIN(target.size.height/2.0,target.size.width/2.0))")
rep("    CGFloat scale = NANFloat(@\"NotificationIslandTextScale\", 1.0, 0.80, 1.35);",r'''    self.openButton.layer.cornerRadius=MIN(19.0,NANFloat(@"NotificationIslandCornerRadius",32,16,40)*.6);
    self.dismissButton.layer.cornerRadius=self.openButton.layer.cornerRadius;
    for (UIButton *b in self.nativeActionButtons) b.layer.cornerRadius=self.openButton.layer.cornerRadius;
    if (!docked) self.layer.cornerCurve=kCACornerCurveContinuous;
    CGFloat scale = NANFloat(@"NotificationIslandTextScale", 1.0, 0.80, 1.35);''')
# In-memory shuffled pool of installed, visible application identities. The
# preview is explicitly synthetic; never generate or deliver real app pushes.
rep("static void NANTest(CFNotificationCenterRef",r'''static NSString *NANRandomPreviewBundle(void) {
    static NSMutableArray<NSString *> *bag;
    static NSSet<NSString *> *previousPool;
    static NSString *last;
    Class cls=NSClassFromString(@"LSApplicationWorkspace");
    id workspace=NANSafeValue(cls,@"defaultWorkspace");
    id apps=NANSafeValue(workspace,@"allApplications");
    NSMutableSet *pool=[NSMutableSet new];
    if ([apps isKindOfClass:NSArray.class]) for (id proxy in apps) {
        NSString *bundle=NANString(proxy,@[@"applicationIdentifier",@"bundleIdentifier"]);
        NSString *type=NANString(proxy,@[@"applicationType"]);
        id tags=NANSafeValue(proxy,@"appTags");
        if (!bundle.length || [bundle isEqualToString:@"com.apple.springboard"] ||
            [NANSafeValue(proxy,@"isPlaceholder") boolValue] ||
            ([tags respondsToSelector:@selector(containsObject:)] && [tags containsObject:@"hidden"])) continue;
        if (type.length && ![@[@"User",@"System"] containsObject:type]) continue;
        if (!NANString(proxy,@[@"localizedName",@"localizedShortName"]).length) continue;
        [pool addObject:bundle];
    }
    if (!pool.count) [pool addObject:@"com.apple.MobileSMS"];
    if (![pool isEqualToSet:previousPool] || !bag.count) {
        previousPool=[pool copy]; bag=[pool.allObjects mutableCopy];
        for (NSUInteger i=bag.count;i>1;i--) [bag exchangeObjectAtIndex:i-1 withObjectAtIndex:arc4random_uniform((uint32_t)i)];
        if (bag.count>1 && [bag.lastObject isEqualToString:last]) [bag exchangeObjectAtIndex:0 withObjectAtIndex:bag.count-1];
    }
    last=bag.lastObject; [bag removeLastObject];
    return last;
}
static void NANTest(CFNotificationCenterRef''')
rep('        NSDictionary *sample = @{\n            @"bundleID": @"com.apple.MobileSMS",\n            @"appName": @"Messages",',r'''        NSString *sampleBundle=NANRandomPreviewBundle();
        NSDictionary *sample = @{
            @"bundleID": sampleBundle,
            @"appName": NANApplicationName(sampleBundle),''')
rep('@"title": @"Test Notification"', '@"title": @"Test Notification • Preview"')
rep("1.0.8 Adaptive Actions loaded","1.0.9 Inline Actions loaded")
p.write_text(s)
print("Prepared Notify Island 1.0.9 Inline Actions.")
