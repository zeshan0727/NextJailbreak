#!/usr/bin/env python3
"""1.0.11: full-cover aperture silhouette, preserving the keyboard host."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.11 missing anchor: "+a[:130])
    s=s.replace(a,b,1)
rep('return NANInteger(@"NotificationIslandShapeStyle",1,0,3);','return NANInteger(@"NotificationIslandShapeStyle",1,0,4);')
rep('    if (NANShapeStyle()>=2) return NO;','    if (NANShapeStyle()==2 || NANShapeStyle()==3) return NO;')
# One continuous silhouette, no narrow protruding stem. Keep the full
# aperture within a wide top band and expand below the status bar.
rep('    if (NANShapeStyle()==1) {',r'''    if (NANShapeStyle()==4) {
        CGFloat c=w*.5;
        CGFloat half=MIN(c-1,100.0);
        CGFloat l=c-half,r=c+half;
        CGFloat radius=NANFloat(@"NotificationIslandCornerRadius",32,16,40);
        CGFloat top=MIN(radius,MIN(23.0,half*.35));
        CGFloat bottom=MIN(radius,MIN(w*.5,(h-reserve)*.45));
        CGFloat shoulder=MIN(h-bottom,MAX(top+8.0,reserve-3.0));
        CGFloat edge=MIN(h-bottom,shoulder+MIN(17.0,(w-2*half)*.3));
        UIBezierPath *p=[UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(l+top,0)];
        [p addLineToPoint:CGPointMake(r-top,0)];
        [p addCurveToPoint:CGPointMake(r,top) controlPoint1:CGPointMake(r,0) controlPoint2:CGPointMake(r,top*.40)];
        [p addCurveToPoint:CGPointMake(w,edge) controlPoint1:CGPointMake(r,shoulder) controlPoint2:CGPointMake(w,shoulder)];
        [p addLineToPoint:CGPointMake(w,h-bottom)];
        [p addCurveToPoint:CGPointMake(w-bottom,h) controlPoint1:CGPointMake(w,h-bottom*.35) controlPoint2:CGPointMake(w-bottom*.35,h)];
        [p addLineToPoint:CGPointMake(bottom,h)];
        [p addCurveToPoint:CGPointMake(0,h-bottom) controlPoint1:CGPointMake(bottom*.35,h) controlPoint2:CGPointMake(0,h-bottom*.35)];
        [p addLineToPoint:CGPointMake(0,edge)];
        [p addCurveToPoint:CGPointMake(l,top) controlPoint1:CGPointMake(0,shoulder) controlPoint2:CGPointMake(l,shoulder)];
        [p addCurveToPoint:CGPointMake(l+top,0) controlPoint1:CGPointMake(l,top*.40) controlPoint2:CGPointMake(l,0)];
        [p closePath]; return p;
    }
    if (NANShapeStyle()==1) {''')
# Keep the black sensor area, but avoid an opaque full-width bar on light/Glass.
rep('        self.apertureCap.frame = CGRectMake(0,0,self.bounds.size.width,reserve);',r'''        if (NANShapeStyle()==4) {
            CGFloat coverW=MIN(166.0,self.bounds.size.width-8.0);
            CGFloat coverH=MIN(40.0,reserve-6.0);
            self.apertureCap.frame=CGRectMake((self.bounds.size.width-coverW)*.5,1.0,coverW,coverH);
            self.apertureCap.layer.cornerRadius=coverH*.5;
            self.apertureCap.layer.cornerCurve=kCACornerCurveContinuous;
        } else {
            self.apertureCap.frame = CGRectMake(0,0,self.bounds.size.width,reserve);
            self.apertureCap.layer.cornerRadius=0;
        }''')
# Ensure the custom shape comfortably surrounds the physical aperture even
# with small saved widths; landscape and detached placement remain supported.
rep('    if (NANShapeStyle()==3) width=MIN(width,maxWidth-8.0);',r'''    if (NANShapeStyle()==3) width=MIN(width,maxWidth-8.0);
    if (NANShapeStyle()==4 && docked) width=MAX(width,210.0);''')
# Keep the rounded shape from fighting the transient window's layout pass.
rep('1.0.10 Island Studio loaded','1.0.11 Full Cover loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.11 Full Cover.")
