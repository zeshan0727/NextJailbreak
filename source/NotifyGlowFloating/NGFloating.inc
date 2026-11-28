// Notify Glow - Next Jailbreak | Floating Icon Engine 1.0.7
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <notify.h>

static BOOL UVNGFloatingPreview;
static CFStringRef const UVNGTestFloating=CFSTR("com.nextsolution.notifyglow/test-floating");
static CFStringRef const UVNGStopFloating=CFSTR("com.nextsolution.notifyglow/stop-floating");

static id NGFGet(id o, NSString *name) {
    if(!o)return nil;
    @try {return [o valueForKey:name];} @catch(__unused NSException *e){return nil;}
}
static NSString *NGFString(id o, NSString *name) {
    id v=NGFGet(o,name);return [v isKindOfClass:NSString.class] ? v : nil;
}
static id NGFShared(NSString *name) {
    Class c=NSClassFromString(name);
    for(NSString *s in @[@"sharedInstanceIfExists",@"sharedInstance"]){
        SEL sel=NSSelectorFromString(s);
        if([c respondsToSelector:sel]){
            @try {id v=((id(*)(id,SEL))objc_msgSend)(c,sel); if(v)return v;} @catch(__unused NSException *e){}
        }
    }
    return nil;
}
static BOOL NGFReadBool(id o, NSString *name, BOOL fallback) {
    SEL s=NSSelectorFromString(name);
    @try {if([o respondsToSelector:s])return ((BOOL(*)(id,SEL))objc_msgSend)(o,s);}
    @catch(__unused NSException *e){}
    return fallback;
}
static BOOL NGFUnlocked(void) {
    return !NGFReadBool(NGFShared(@"SBLockScreenManager"),@"isUILocked",YES);
}
static BOOL NGFScreenOn(void) {
    return NGFReadBool(NGFShared(@"SBBacklightController"),@"screenIsOn",NO);
}
static BOOL NGFCoverVisible(void) {
    return NGFReadBool(NGFShared(@"SBCoverSheetPresentationManager"),@"isVisible",NO);
}
static NSString *NGFRequestKey(id req) {
    NSString *section=NGFString(req,@"sectionIdentifier"),*identifier=NGFString(req,@"notificationIdentifier");
    if(!identifier.length)identifier=NGFString(req,@"identifier");
    if(!section.length||!identifier.length)return nil;
    return [NSString stringWithFormat:@"%@|%@",section,identifier];
}
static id NGFControllerRequest(id controller) {
    for(NSString *key in @[@"notificationRequest",@"request",@"_notificationRequest"]){
        id r=NGFGet(controller,key);if(NGFRequestKey(r))return r;
    }
    return nil;
}
static BOOL NGFModeAllowed(void) {
    if(!UVNGEnabled||!UVNGShowAppIcon||!UVNGFloatingEnabled)return NO;
    UIDevice *d=UIDevice.currentDevice;
    d.batteryMonitoringEnabled=YES;
    if(d.batteryLevel>=0&&d.batteryLevel*100<UVNGLowBatteryCutoff)return NO;
    if(UVNGChargingOnly&&d.batteryState==UIDeviceBatteryStateUnplugged)return NO;
    return YES;
}

@interface NGFFloatWindow : UIWindow
@end
@implementation NGFFloatWindow
- (BOOL)canBecomeKeyWindow {return NO;}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e {
    UIView *v=[super hitTest:p withEvent:e];
    return (v==self||v==self.rootViewController.view)?nil:v;
}
@end

@interface NGFFloatBall : NSObject
@property(nonatomic,copy) NSString *section;
@property(nonatomic,copy) NSString *group;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *keys;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSDate *> *dates;
@property(nonatomic,strong) UIButton *button;
@property(nonatomic,strong) UIImageView *image;
@property(nonatomic,strong) UILabel *badge;
@property(nonatomic) CGPoint pos;
@property(nonatomic) CGPoint vel;
@property(nonatomic) BOOL held;
@property(nonatomic) BOOL preview;
@end
@implementation NGFFloatBall
@end

@interface NGFFloatEngine : NSObject
@property(nonatomic,strong) NGFFloatWindow *window;
@property(nonatomic,strong) CMMotionManager *motion;
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic,strong) NSTimer *stateTimer;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NGFFloatBall *> *groups;
@property(nonatomic,strong) NSMutableDictionary<NSString *,NSString *> *keyGroups;
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *attended;
@property(nonatomic,strong) NSArray<NGFFloatBall *> *balls;
@property(nonatomic,strong) NSCache<NSString *,UIImage *> *images;
@property(nonatomic,strong) UIView *panel;
@property(nonatomic,strong) NGFFloatBall *selected;
@property(nonatomic) CGSize priorSize;
@property(nonatomic) CFTimeInterval priorTime;
@property(nonatomic) CGPoint filteredGravity;
@property(nonatomic) BOOL suspendedForCenter;
@property(nonatomic) CFTimeInterval centerStart;
@property(nonatomic) BOOL sawCenter;
@property(nonatomic) NSInteger frameCap;
@property(nonatomic) CGFloat diameter;
@property(nonatomic) int lockToken;
@property(nonatomic) int blankToken;
+ (instancetype)shared;
- (void)record:(id)request;
- (void)removeRequest:(id)request;
- (void)removeKeys:(id)requests;
- (void)refresh;
- (void)reload;
- (void)preview;
- (void)stopPreview;
- (void)clear;
@end

@implementation NGFFloatEngine
+ (instancetype)shared {
    static NGFFloatEngine *e;static dispatch_once_t once;
    dispatch_once(&once,^{e=[NGFFloatEngine new];});
    return e;
}
- (instancetype)init {
    if((self=[super init])){
        _groups=[NSMutableDictionary new];_keyGroups=[NSMutableDictionary new];
        _attended=[NSMutableOrderedSet new];_balls=@[];_images=[NSCache new];_images.countLimit=96;
        _motion=[CMMotionManager new];_motion.deviceMotionUpdateInterval=1.0/60.0;
        _motion.accelerometerUpdateInterval=1.0/60.0;
        _lockToken=-1;_blankToken=-1;
        __weak typeof(self) weak=self;
        int t=-1;
        if(notify_register_dispatch("com.apple.springboard.lockstate",&t,dispatch_get_main_queue(),^(__unused int token){[weak refresh];})==NOTIFY_STATUS_OK)_lockToken=t;
        t=-1;
        if(notify_register_dispatch("com.apple.springboard.hasBlankedScreen",&t,dispatch_get_main_queue(),^(__unused int token){[weak refresh];})==NOTIFY_STATUS_OK)_blankToken=t;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){[weak refresh];}];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n){[weak refresh];}];
    }
    return self;
}
- (BOOL)blanked {
    if(self.blankToken<0)return NO;
    uint64_t state=0;
    return notify_get_state(self.blankToken,&state)==NOTIFY_STATUS_OK&&state!=0;
}
- (BOOL)locked {
    if(!NGFUnlocked())return YES;
    uint64_t state=0;
    return self.lockToken>=0&&notify_get_state(self.lockToken,&state)==NOTIFY_STATUS_OK&&state!=0;
}
- (void)pause {
    [self.link invalidate];self.link=nil;self.priorTime=0;self.frameCap=0;
    if(self.motion.deviceMotionActive)[self.motion stopDeviceMotionUpdates];
    if(self.motion.accelerometerActive)[self.motion stopAccelerometerUpdates];
    self.window.hidden=YES;
    for(NGFFloatBall *b in self.balls){b.held=NO;}
}
- (BOOL)ensureWindow {
    UIWindowScene *scene=nil;
    for(UIScene *s in UIApplication.sharedApplication.connectedScenes){
        if(![s isKindOfClass:UIWindowScene.class])continue;
        UIWindowScene *candidate=(UIWindowScene *)s;
        if(candidate.screen!=UIScreen.mainScreen)continue;
        if(!scene||s.activationState==UISceneActivationStateForegroundActive)scene=candidate;
        if(s.activationState==UISceneActivationStateForegroundActive)break;
    }
    if(!scene)return NO;
    if(self.window&&self.window.windowScene==scene)return YES;
    self.window.hidden=YES;
    [self.panel removeFromSuperview];self.panel=nil;self.selected=nil;
    NGFFloatWindow *w=[[NGFFloatWindow alloc]initWithWindowScene:scene];
    w.frame=scene.coordinateSpace.bounds;w.windowLevel=UIWindowLevelAlert+119;
    w.backgroundColor=UIColor.clearColor;w.hidden=YES;w.opaque=NO;
    UIViewController *vc=[UIViewController new];vc.view.backgroundColor=UIColor.clearColor;
    vc.view.opaque=NO;vc.view.frame=w.bounds;vc.view.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    w.rootViewController=vc;self.window=w;self.priorSize=CGSizeZero;
    for(NGFFloatBall *b in self.balls)[vc.view addSubview:b.button];
    return YES;
}
- (void)updateRate:(NSInteger)cap {
    if(!self.link||self.frameCap==cap)return;
    self.frameCap=cap;
    self.link.preferredFrameRateRange=CAFrameRateRangeMake(MIN(30,cap),cap,cap);
}
- (void)refresh {
    if(self.groups.count==0){
        [self pause];[self.stateTimer invalidate];self.stateTimer=nil;
        [self.panel removeFromSuperview];self.panel=nil;self.selected=nil;self.window=nil;
        return;
    }
    if(!self.stateTimer){
        __weak typeof(self) weak=self;
        self.stateTimer=[NSTimer timerWithTimeInterval:.5 repeats:YES block:^(__unused NSTimer *t){[weak refresh];}];
        [[NSRunLoop mainRunLoop]addTimer:self.stateTimer forMode:NSRunLoopCommonModes];
    }
    BOOL cover=NGFCoverVisible();
    if(self.suspendedForCenter){
        if(cover)self.sawCenter=YES;
        if(!cover&&(self.sawCenter||CACurrentMediaTime()-self.centerStart>2.5))self.suspendedForCenter=NO;
    }
    if([self locked]||[self blanked]||!NGFScreenOn()||cover||self.suspendedForCenter||
       (!NGFModeAllowed()&&!UVNGFloatingPreview)){
        [self.panel removeFromSuperview];self.panel=nil;self.selected=nil;
        [self pause];return;
    }
    if(![self ensureWindow]){[self pause];return;}
    self.window.frame=self.window.windowScene.coordinateSpace.bounds;
    self.window.rootViewController.view.frame=self.window.bounds;
    self.window.hidden=NO;
    if(!self.link){
        self.priorTime=0;
        if(self.motion.deviceMotionAvailable)[self.motion startDeviceMotionUpdates];
        else if(self.motion.accelerometerAvailable)[self.motion startAccelerometerUpdates];
        self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    NSInteger maxFPS=MAX(30,MIN(120,UIScreen.mainScreen.maximumFramesPerSecond));
    if(NSProcessInfo.processInfo.lowPowerModeEnabled)maxFPS=MIN(maxFPS,60);
    if(NSProcessInfo.processInfo.thermalState>=NSProcessInfoThermalStateSerious)maxFPS=MIN(maxFPS,30);
    [self updateRate:maxFPS];
}
- (void)rebuild {
    self.balls=self.groups.allValues;
    if(!self.groups.count){[self refresh];return;}
    [self refresh];self.priorSize=CGSizeZero;
}
- (void)style:(NGFFloatBall *)b {
    CGFloat d=self.diameter>0?self.diameter:UVNGFloatingSize;
    b.button.bounds=CGRectMake(0,0,d,d);b.button.center=b.pos;
    b.button.backgroundColor=UIColor.clearColor;
    b.image.frame=b.button.bounds;b.image.alpha=UVNGIconOpacity;
    b.image.layer.cornerRadius=UVNGIconShape==2?d/2:d*.23;
    b.image.clipsToBounds=YES;
    UIColor *c=UVNGColorForIdentifier(b.section);
    b.button.layer.shadowColor=c.CGColor;b.button.layer.shadowOffset=CGSizeZero;
    b.button.layer.shadowOpacity=UVNGFloatingGlow;b.button.layer.shadowRadius=6+UVNGFloatingGlow*6;
    b.button.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:b.button.bounds cornerRadius:b.image.layer.cornerRadius].CGPath;
    b.badge.frame=CGRectMake(d-16,-5,MAX(22,b.keys.count>99?34:24),22);
    b.badge.layer.cornerRadius=11;
    b.badge.text=b.keys.count>999?@"999+":[NSString stringWithFormat:@"%lu",(unsigned long)b.keys.count];
    b.button.accessibilityLabel=[NSString stringWithFormat:@"%@, %lu notifications",b.section,(unsigned long)b.keys.count];
    [b.image.layer removeAllAnimations];
    if(UVNGIconAnimation==1)UVNGAnimate(b.image.layer,@"opacity",@1,@.55,.7,YES);
    else if(UVNGIconAnimation==2)UVNGAnimate(b.image.layer,@"transform.scale",@.92,@1.08,.6,YES);
    else if(UVNGIconAnimation==3)UVNGAnimate(b.image.layer,@"transform.rotation.z",@0,@(2*M_PI),2,NO);
    else if(UVNGIconAnimation==4)UVNGAnimate(b.button.layer,@"shadowOpacity",@.1,@(UVNGFloatingGlow),.5,YES);
    else [b.button.layer removeAnimationForKey:@"ng.shadowOpacity"];
}
- (NGFFloatBall *)newBall:(NSString *)section group:(NSString *)group preview:(BOOL)preview {
    NGFFloatBall *b=[NGFFloatBall new];b.section=section;b.group=group;b.preview=preview;
    b.keys=[NSMutableOrderedSet new];b.dates=[NSMutableDictionary new];
    b.button=[UIButton buttonWithType:UIButtonTypeCustom];b.button.clipsToBounds=NO;
    UIImage *im=[self.images objectForKey:section];
    if(!im){im=UVNGAppIcon(section);if(im)[self.images setObject:im forKey:section];}
    b.image=[[UIImageView alloc]initWithImage:im?:[UIImage systemImageNamed:UVNGSymbolForIdentifier(section)]];
    b.image.userInteractionEnabled=NO;b.image.contentMode=UIViewContentModeScaleAspectFit;
    b.image.tintColor=UVNGColorForIdentifier(section);
    [b.button addSubview:b.image];
    b.badge=[UILabel new];b.badge.userInteractionEnabled=NO;b.badge.textAlignment=NSTextAlignmentCenter;
    b.badge.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBold];b.badge.textColor=UIColor.whiteColor;
    b.badge.backgroundColor=UIColor.systemRedColor;b.badge.clipsToBounds=YES;
    b.badge.layer.borderWidth=1;b.badge.layer.borderColor=UIColor.whiteColor.CGColor;
    [b.button addSubview:b.badge];
    [b.button addTarget:self action:@selector(hold:) forControlEvents:UIControlEventTouchDown];
    [b.button addTarget:self action:@selector(releaseBall:) forControlEvents:UIControlEventTouchCancel|UIControlEventTouchUpOutside];
    [b.button addTarget:self action:@selector(tap:) forControlEvents:UIControlEventTouchUpInside];
    CGSize size=self.window?self.window.bounds.size:UIScreen.mainScreen.bounds.size;
    CGFloat spread=MAX(1,size.width-UVNGFloatingSize*2);
    b.pos=CGPointMake(UVNGFloatingSize+arc4random_uniform((uint32_t)spread),size.height*.28+arc4random_uniform((uint32_t)MAX(1,size.height*.4)));
    b.vel=CGPointMake((NSInteger)arc4random_uniform(301)-150,(NSInteger)arc4random_uniform(241)-120);
    self.groups[group]=b;
    [self.window.rootViewController.view addSubview:b.button];
    return b;
}
- (void)addKey:(NSString *)key section:(NSString *)section date:(NSDate *)date preview:(BOOL)preview {
    if(!key.length||!section.length||self.keyGroups[key]||[self.attended containsObject:key])return;
    NSString *group=preview?[@"preview|" stringByAppendingString:section]:section;
    NGFFloatBall *b=self.groups[group];BOOL fresh=!b;
    if(!b)b=[self newBall:section group:group preview:preview];
    [b.keys addObject:key];b.dates[key]=date?:NSDate.date;self.keyGroups[key]=group;
    if(fresh)[self rebuild];
    [self style:b];
}
- (void)record:(id)request {
    if(!NGFModeAllowed())return;
    NSString *key=NGFRequestKey(request),*section=NGFString(request,@"sectionIdentifier");
    if(!key||!UVNGAppAllowed(section))return;
    id stamp=NGFGet(request,@"timestamp");
    [self addKey:key section:section date:[stamp isKindOfClass:NSDate.class]?stamp:nil preview:NO];
}
- (void)attend:(NSString *)key {
    if(!key)return;
    NSString *group=self.keyGroups[key];NGFFloatBall *b=group?self.groups[group]:nil;
    if(!b)return;
    [self.attended addObject:key];
    if(self.attended.count>2048)[self.attended removeObjectAtIndex:0];
    [b.keys removeObject:key];[b.dates removeObjectForKey:key];[self.keyGroups removeObjectForKey:key];
    if(!b.keys.count){
        [b.button removeFromSuperview];[self.groups removeObjectForKey:group];
        if(self.selected==b)[self closePanel];
        [self rebuild];
    }else{
        [self style:b];
        if(self.selected==b)[self showPanel:b];
    }
    UVNGFloatingPreview=NO;
    for(NGFFloatBall *other in self.balls)if(other.preview){UVNGFloatingPreview=YES;break;}
    [self refresh];
}
- (void)removeRequest:(id)request {[self attend:NGFRequestKey(request)];}
- (void)removeKeys:(id)requests {
    if([requests conformsToProtocol:@protocol(NSFastEnumeration)]){
        for(id req in requests)[self removeRequest:req];
    }else [self removeRequest:requests];
}
- (void)closePanel {
    [self.panel removeFromSuperview];self.panel=nil;self.selected.held=NO;self.selected=nil;
}
- (NGFFloatBall *)ballForButton:(UIButton *)button {
    for(NGFFloatBall *b in self.balls)if(b.button==button)return b;
    return nil;
}
- (void)hold:(UIButton *)sender {NGFFloatBall *b=[self ballForButton:sender];b.held=YES;b.vel=CGPointZero;}
- (void)releaseBall:(UIButton *)sender {[self ballForButton:sender].held=NO;}
- (void)tap:(UIButton *)sender {
    NGFFloatBall *b=[self ballForButton:sender];if(!b)return;b.held=NO;
    if([self locked]||!NGFScreenOn()||NGFCoverVisible()){[self refresh];return;}
    [self showPanel:b];
}
- (UIButton *)panelButton:(NSString *)title action:(SEL)action tag:(NSInteger)tag {
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    b.backgroundColor=UIColor.tertiarySystemBackgroundColor;b.layer.cornerRadius=10;b.tag=tag;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return b;
}
- (void)showPanel:(NGFFloatBall *)b {
    [self closePanel];if(!b||[self locked])return;
    self.selected=b;b.held=YES;b.vel=CGPointZero;
    UIView *root=self.window.rootViewController.view;
    CGFloat w=MIN(330,root.bounds.size.width-24),h=MIN(360,root.bounds.size.height-44);
    UIView *panel=[[UIView alloc]initWithFrame:CGRectMake((root.bounds.size.width-w)/2,(root.bounds.size.height-h)/2,w,h)];
    panel.backgroundColor=UIColor.secondarySystemBackgroundColor;panel.layer.cornerRadius=20;
    panel.layer.shadowColor=UIColor.blackColor.CGColor;panel.layer.shadowOpacity=.25;panel.layer.shadowRadius=16;
    UILabel *title=[[UILabel alloc]initWithFrame:CGRectMake(16,12,w-64,32)];
    title.font=[UIFont systemFontOfSize:19 weight:UIFontWeightBold];title.text=b.preview?@"Preview notifications":@"Notifications";
    [panel addSubview:title];
    UIButton *close=[self panelButton:@"×" action:@selector(closeTapped:) tag:0];close.frame=CGRectMake(w-47,12,35,32);[panel addSubview:close];
    UILabel *subtitle=[[UILabel alloc]initWithFrame:CGRectMake(16,47,w-32,23)];
    subtitle.font=[UIFont systemFontOfSize:12];subtitle.textColor=UIColor.secondaryLabelColor;
    subtitle.text=[NSString stringWithFormat:@"%lu pending · Next Jailbreak",(unsigned long)b.keys.count];[panel addSubview:subtitle];
    UIScrollView *scroll=[[UIScrollView alloc]initWithFrame:CGRectMake(12,76,w-24,h-136)];
    NSDateFormatter *fmt=[NSDateFormatter new];fmt.dateStyle=NSDateFormatterShortStyle;fmt.timeStyle=NSDateFormatterShortStyle;
    NSUInteger i=0;
    for(NSString *key in b.keys){
        CGFloat y=i*58;
        UILabel *label=[[UILabel alloc]initWithFrame:CGRectMake(4,y,w-145,52)];
        label.numberOfLines=2;label.font=[UIFont systemFontOfSize:13];label.textColor=UIColor.labelColor;
        label.text=[NSString stringWithFormat:@"Notification %lu\n%@",(unsigned long)i+1,[fmt stringFromDate:b.dates[key]?:NSDate.date]];
        [scroll addSubview:label];
        UIButton *done=[self panelButton:@"Attended" action:@selector(attendTapped:) tag:(NSInteger)i];
        done.frame=CGRectMake(w-128,y+5,96,43);[scroll addSubview:done];i++;
    }
    scroll.contentSize=CGSizeMake(w-24,i*58);[panel addSubview:scroll];
    UIButton *native=[self panelButton:b.preview?@"Close preview":@"Open Notification Centre" action:@selector(nativeTapped:) tag:0];
    native.frame=CGRectMake(12,h-52,w-24,40);[panel addSubview:native];
    self.panel=panel;[root addSubview:panel];
}
- (void)closeTapped:(__unused UIButton *)sender {[self closePanel];}
- (void)attendTapped:(UIButton *)sender {
    if([self locked]||!NGFScreenOn()){[self refresh];return;}
    NGFFloatBall *b=self.selected;
    if(b&&sender.tag>=0&&(NSUInteger)sender.tag<b.keys.count)[self attend:b.keys[(NSUInteger)sender.tag]];
}
- (void)nativeTapped:(__unused UIButton *)sender {
    if([self locked]||!NGFScreenOn()){[self refresh];return;}
    if(self.selected.preview){[self stopPreview];return;}
    id manager=NGFShared(@"SBCoverSheetPresentationManager");
    SEL modern=NSSelectorFromString(@"setCoverSheetPresented:animated:options:withCompletion:");
    SEL legacy=NSSelectorFromString(@"setCoverSheetPresented:animated:withCompletion:");
    BOOL supported=[manager respondsToSelector:modern]||[manager respondsToSelector:legacy];
    if(!supported){
        UILabel *hint=[[UILabel alloc]initWithFrame:CGRectMake(12,self.panel.bounds.size.height-84,self.panel.bounds.size.width-24,28)];
        hint.text=@"Swipe down to open Notification Centre";hint.font=[UIFont systemFontOfSize:11];hint.textAlignment=NSTextAlignmentCenter;hint.textColor=UIColor.secondaryLabelColor;[self.panel addSubview:hint];return;
    }
    [self closePanel];self.suspendedForCenter=YES;self.sawCenter=NO;self.centerStart=CACurrentMediaTime();[self pause];
    @try {
        if([manager respondsToSelector:modern])((void(*)(id,SEL,BOOL,BOOL,NSUInteger,id))objc_msgSend)(manager,modern,YES,YES,0,nil);
        else ((void(*)(id,SEL,BOOL,BOOL,id))objc_msgSend)(manager,legacy,YES,YES,nil);
    }@catch(__unused NSException *e){self.suspendedForCenter=NO;[self refresh];}
}
- (void)clear {
    [self closePanel];[self pause];
    for(NGFFloatBall *b in self.balls)[b.button removeFromSuperview];
    [self.groups removeAllObjects];[self.keyGroups removeAllObjects];[self.attended removeAllObjects];
    self.balls=@[];UVNGFloatingPreview=NO;[self refresh];
}
- (void)stopPreview {
    NSMutableArray *keys=[NSMutableArray new];
    for(NGFFloatBall *b in self.balls)if(b.preview)[keys addObjectsFromArray:b.keys.array];
    for(NSString *k in keys)[self attend:k];UVNGFloatingPreview=NO;[self refresh];
}
- (void)preview {
    [self stopPreview];if([self locked]||!NGFScreenOn())return;
    UVNGFloatingPreview=YES;
    for(NSString *app in @[@"com.apple.MobileSMS",@"com.apple.mobilemail",@"net.whatsapp.WhatsApp"]){
        NSUInteger count=[app isEqualToString:@"com.apple.MobileSMS"]?3:1;
        for(NSUInteger i=0;i<count;i++)[self addKey:[@"preview|" stringByAppendingString:NSUUID.UUID.UUIDString] section:app date:NSDate.date preview:YES];
    }
    [self refresh];
}
- (void)reload {
    if(!UVNGEnabled||!UVNGShowAppIcon||!UVNGFloatingEnabled){[self clear];return;}
    self.priorSize=CGSizeZero;
    for(NGFFloatBall *b in self.balls)[self style:b];[self refresh];
}
static CGFloat NGFClamp(CGFloat x,CGFloat lo,CGFloat hi){return MIN(MAX(x,lo),MAX(lo,hi));}
- (void)step:(CADisplayLink *)link {
    if(!self.window||!self.balls.count)return;
    CFTimeInterval now=link.timestamp;
    CGFloat dt=self.priorTime?NGFClamp(now-self.priorTime,1.0/240,1.0/30):1.0/120;
    self.priorTime=now;
    CGSize size=self.window.bounds.size;
    if(size.width<10||size.height<10)return;
    if(!CGSizeEqualToSize(size,self.priorSize)){
        if(self.priorSize.width>0){
            for(NGFFloatBall *b in self.balls)b.pos=CGPointMake(b.pos.x*size.width/self.priorSize.width,b.pos.y*size.height/self.priorSize.height);
        }
        self.priorSize=size;
        self.diameter=NGFClamp(MIN(UVNGFloatingSize,sqrt(size.width*size.height*.47/MAX(1,self.balls.count))),24,84);
        for(NGFFloatBall *b in self.balls)[self style:b];
        if(self.panel&&self.selected)[self showPanel:self.selected];
    }
    CMDeviceMotion *m=self.motion.deviceMotion;
    CMAcceleration g=m?m.gravity:self.motion.accelerometerData.acceleration;
    CMAcceleration a=m?m.userAcceleration:(CMAcceleration){0,0,0};
    CMRotationRate r=m?m.rotationRate:(CMRotationRate){0,0,0};
    CGFloat gx=g.x+a.x*.25+r.y*.035,gy=-g.y-a.y*.25+r.x*.035;
    switch(self.window.windowScene.interfaceOrientation){
        case UIInterfaceOrientationLandscapeLeft:{CGFloat v=gx;gx=gy;gy=-v;break;}
        case UIInterfaceOrientationLandscapeRight:{CGFloat v=gx;gx=-gy;gy=v;break;}
        case UIInterfaceOrientationPortraitUpsideDown:gx=-gx;gy=-gy;break;
        default:break;
    }
    if(!m&&!self.motion.accelerometerData){gx=0;gy=.35;}
    if(!isfinite(gx)||!isfinite(gy)){gx=0;gy=0;}
    CGFloat smooth=1-exp(-dt*14);
    self.filteredGravity=CGPointMake(self.filteredGravity.x+(NGFClamp(gx,-2,2)-self.filteredGravity.x)*smooth,self.filteredGravity.y+(NGFClamp(gy,-2,2)-self.filteredGravity.y)*smooth);
    CGFloat rad=self.diameter/2+2, restitution=UVNGFloatingBounce;
    // Full window coordinates (not safe-area or bottom strip); only the icon radius is inset.
    NSInteger sub=MAX(1,(NSInteger)ceil(dt*120));CGFloat h=dt/sub;
    NSArray<NGFFloatBall *> *balls=self.balls;NSUInteger count=balls.count;
    for(NSInteger z=0;z<sub;z++){
        CGFloat drag=exp(-h*1.25);
        for(NGFFloatBall *b in balls){
            if(b.held)continue;
            CGPoint v=b.vel,p=b.pos;
            v.x=(v.x+self.filteredGravity.x*950*UVNGFloatingSensitivity*h)*drag;
            v.y=(v.y+self.filteredGravity.y*950*UVNGFloatingSensitivity*h)*drag;
            CGFloat speed=hypot(v.x,v.y);if(speed>1250){v.x*=1250/speed;v.y*=1250/speed;}
            p.x+=v.x*h;p.y+=v.y*h;
            if(p.x<rad){p.x=rad;if(v.x<0)v.x=-v.x*restitution;}
            if(p.x>size.width-rad){p.x=size.width-rad;if(v.x>0)v.x=-v.x*restitution;}
            if(p.y<rad){p.y=rad;if(v.y<0)v.y=-v.y*restitution;}
            if(p.y>size.height-rad){p.y=size.height-rad;if(v.y>0)v.y=-v.y*restitution;}
            if(fabs(v.x)<1)v.x=0;if(fabs(v.y)<1)v.y=0;
            b.pos=p;b.vel=v;
        }
        for(NSUInteger i=0;i<count;i++)for(NSUInteger j=i+1;j<count;j++){
            NGFFloatBall *a=balls[i],*b=balls[j];if(a.held&&b.held)continue;
            CGPoint ap=a.pos,bp=b.pos,av=a.vel,bv=b.vel;
            CGFloat dx=bp.x-ap.x,dy=bp.y-ap.y,d2=dx*dx+dy*dy,minDist=rad*2+3;
            if(d2>=minDist*minDist)continue;
            CGFloat d=sqrt(MAX(.0001,d2)),nx=d2<.0001?1:dx/d,ny=d2<.0001?0:dy/d;
            CGFloat overlap=minDist-d,wa=a.held?0:(b.held?1:.5),wb=b.held?0:(a.held?1:.5);
            ap.x-=nx*overlap*wa;ap.y-=ny*overlap*wa;bp.x+=nx*overlap*wb;bp.y+=ny*overlap*wb;
            CGFloat rel=(bv.x-av.x)*nx+(bv.y-av.y)*ny;
            if(rel<0){CGFloat impulse=-(1+restitution)*rel;av.x-=impulse*wa*nx;av.y-=impulse*wa*ny;bv.x+=impulse*wb*nx;bv.y+=impulse*wb*ny;}
            a.pos=ap;a.vel=av;b.pos=bp;b.vel=bv;
        }
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for(NGFFloatBall *b in balls){
        b.pos=CGPointMake(NGFClamp(b.pos.x,rad,size.width-rad),NGFClamp(b.pos.y,rad,size.height-rad));
        b.button.center=b.pos;
    }
    [CATransaction commit];
}
@end

static void NGFOnMain(dispatch_block_t work){if(NSThread.isMainThread)work();else dispatch_async(dispatch_get_main_queue(),work);}
static BOOL NGFVoidMethod(Class c,SEL s,unsigned int arguments){
    Method m=class_getInstanceMethod(c,s);if(!m||method_getNumberOfArguments(m)!=arguments)return NO;
    char type[16]={0};method_getReturnType(m,type,sizeof(type));return type[0]=='v';
}
