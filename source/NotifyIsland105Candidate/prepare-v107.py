#!/usr/bin/env python3
"""Keep 1.0.6 delivery/animation engine; dock card to aperture without obscuring content."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(old,new):
    global s
    if old not in s: raise SystemExit("1.0.7 missing anchor: "+old[:120])
    s=s.replace(old,new,1)

rep("static CGRect NANFrame(BOOL expanded) {",r'''// iPhone 14 Pro Max portrait aperture is at the top center. Use the
// actual window coordinate space; safe-area values are advisory because
// SpringBoard's aperture window may return zero insets.
static BOOL NANIsDocked(void) {
    UIWindow *w = NANSystemWindow;
    if (!w || CGRectGetWidth(w.bounds) >= CGRectGetHeight(w.bounds) ||
        CGRectGetWidth(w.bounds) < 320.0 ||
        UIInterfaceOrientationIsLandscape(w.windowScene.interfaceOrientation)) return NO;
    id value = NANPreference(@"NotificationIslandVerticalPosition");
    return ![value isKindOfClass:NSNumber.class] ||
           !isfinite([value doubleValue]) || [value doubleValue] <= 0.015;
}
static CGFloat NANDockReserve(void) {
    CGFloat safeTop = NANSystemWindow.safeAreaInsets.top;
    // Start at y=8; keep all labels and controls below the physical sensors.
    return MAX(52.0, MIN(68.0, safeTop - 8.0 + 6.0));
}

// Shape with a narrow black cap that blends around the aperture and broadens
// below the status bar into a readable notification body.
static UIBezierPath *NANDockPath(CGRect b, CGFloat reserve) {
    CGFloat w = CGRectGetWidth(b), h = CGRectGetHeight(b);
    CGFloat c = w * 0.5, half = MIN(78.0, w * 0.5 - 14.0);
    CGFloat l = c-half, r = c+half;
    CGFloat shoulder = MAX(26.0, reserve-15.0);
    CGFloat topRadius = 19.0, bottomRadius = MIN(24.0, (h-reserve)*0.4);
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(l+topRadius,0)];
    [path addLineToPoint:CGPointMake(r-topRadius,0)];
    [path addQuadCurveToPoint:CGPointMake(r,topRadius) controlPoint:CGPointMake(r,0)];
    [path addLineToPoint:CGPointMake(r,shoulder-8)];
    [path addQuadCurveToPoint:CGPointMake(r+9,shoulder) controlPoint:CGPointMake(r,shoulder)];
    [path addLineToPoint:CGPointMake(w-20,shoulder)];
    [path addQuadCurveToPoint:CGPointMake(w,reserve+5) controlPoint:CGPointMake(w,shoulder)];
    [path addLineToPoint:CGPointMake(w,h-bottomRadius)];
    [path addQuadCurveToPoint:CGPointMake(w-bottomRadius,h) controlPoint:CGPointMake(w,h)];
    [path addLineToPoint:CGPointMake(bottomRadius,h)];
    [path addQuadCurveToPoint:CGPointMake(0,h-bottomRadius) controlPoint:CGPointMake(0,h)];
    [path addLineToPoint:CGPointMake(0,reserve+5)];
    [path addQuadCurveToPoint:CGPointMake(20,shoulder) controlPoint:CGPointMake(0,shoulder)];
    [path addLineToPoint:CGPointMake(l-9,shoulder)];
    [path addQuadCurveToPoint:CGPointMake(l,shoulder-8) controlPoint:CGPointMake(l,shoulder)];
    [path addLineToPoint:CGPointMake(l,topRadius)];
    [path addQuadCurveToPoint:CGPointMake(l+topRadius,0) controlPoint:CGPointMake(l,0)];
    [path closePath];
    return path;
}

static CGRect NANFrame(BOOL expanded) {''')
rep("    safe = CGRectInset(safe, 8.0, 4.0);",r'''    safe = CGRectInset(safe, 8.0, 4.0);
    BOOL docked = NANIsDocked();
    // A detached portrait card must also clear the camera/sensor area even
    // when the aperture window reports no safe-area inset.
    if (!landscape && !docked) {
        CGFloat bottom = CGRectGetMaxY(safe);
        safe.origin.y = MAX(safe.origin.y, CGRectGetMinY(bounds)+62.0);
        safe.size.height = MAX(0.0, bottom-safe.origin.y);
    }''')
rep("    width = MIN(width, maxWidth); height = MIN(height, maxHeight);",r'''    width = MIN(width, maxWidth); height = MIN(height, maxHeight);
    if (docked) {
        CGFloat reserve = NANDockReserve();
        CGFloat y = CGRectGetMinY(bounds)+8.0;
        CGFloat totalHeight = height+reserve;
        if (width < 190.0 || y+totalHeight > CGRectGetMaxY(safe)) return CGRectZero;
        // Center exactly on the physical aperture; horizontal offset applies
        // only when detached, where there is no sensor occlusion.
        return CGRectIntegral(CGRectMake(CGRectGetMidX(bounds)-width/2.0,y,width,totalHeight));
    }''')
rep("@property(nonatomic,strong) UIView *backgroundTintView;","@property(nonatomic,strong) UIView *backgroundTintView;\n@property(nonatomic,strong) UIView *apertureCap;\n@property(nonatomic,strong) CAShapeLayer *apertureMask;")
rep("    [self addSubview:_backgroundTintView];","    [self addSubview:_backgroundTintView];\n    _apertureCap = [UIView new];\n    _apertureCap.backgroundColor = UIColor.blackColor;\n    _apertureCap.userInteractionEnabled = NO;\n    _apertureCap.hidden = YES;\n    [self addSubview:_apertureCap];\n    _apertureMask = [CAShapeLayer layer];")
# Preserve established content layout using its original height; translate only
# actual content below the reserve, not the blur/tint layers.
a=s.index("- (void)layoutSubviews {\n    [super layoutSubviews];\n    self.backgroundEffectView.frame = self.bounds;")
b=s.index("\n}\n",a)+2
layout=s[a:b]
layout=layout.replace("    CGFloat scale = NANFloat",r'''    CGFloat reserve = NANIsDocked() ? NANDockReserve() : 0.0;
    CGFloat contentHeight = MAX(0.0, self.bounds.size.height - reserve);
    BOOL docked = reserve > 0.0 && self.bounds.size.width >= 190.0 && contentHeight >= 50.0;
    if (!docked) { reserve = 0.0; contentHeight = self.bounds.size.height; }
    self.apertureCap.hidden = !docked;
    if (docked) {
        self.layer.cornerRadius = 0;
        self.apertureCap.frame = CGRectMake(0,0,self.bounds.size.width,reserve);
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.apertureMask.frame = self.bounds;
        self.apertureMask.path = NANDockPath(self.bounds,reserve).CGPath;
        self.layer.mask = self.apertureMask;
        [CATransaction commit];
    } else {
        self.layer.mask = nil;
        self.layer.cornerRadius = MAX(18.0, MIN(self.bounds.size.height/2.0, NANExpanded ? 30.0 : 28.0));
    }
    CGFloat scale = NANFloat''',1)
idx=layout.index("    CGFloat scale = NANFloat")
layout=layout[:idx]+layout[idx:].replace("self.bounds.size.height","contentHeight")
layout=layout[:-2]+r'''
    if (docked) {
        for (UIView *v in @[self.iconView,self.appLabel,self.timeLabel,self.titleLabel,self.bodyLabel,self.openButton,self.dismissButton])
            v.frame = CGRectOffset(v.frame,0,reserve);
    }
}'''
s=s[:a]+layout+s[b:]
# A previous position setting can change while animating. Existing generation
# guards remain; on the next layout the mask follows the current frame.
rep("1.0.6 Visual Studio loaded","1.0.7 Island Integration loaded")
p.write_text(s)
print("Prepared Notify Island 1.0.7 Island Integration.")
