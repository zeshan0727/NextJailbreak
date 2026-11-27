#!/usr/bin/env python3
"""1.0.12: true full-width rectangular island enclosure."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.12 missing anchor: "+a[:130])
    s=s.replace(a,b,1)
# No stem, neck, shoulder or separate card: the outer perimeter has the
# same width across the entire height, except for its four rounded corners.
a=s.index("    if (NANShapeStyle()==4) {",s.index("static UIBezierPath *NANDockPath"))
b=s.index("    if (NANShapeStyle()==1) {",a)
s=s[:a]+r'''    if (NANShapeStyle()==4) {
        CGFloat radius=MIN(NANFloat(@"NotificationIslandCornerRadius",32,16,40),MIN(w*.5,h*.5));
        return [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:radius];
    }
'''+s[b:]
# In black appearance the entire outer silhouette is one uniform black surface.
# Other palettes retain only the black hardware region inside the same silhouette.
rep('        if (NANShapeStyle()==4) {\n            CGFloat coverW=MIN(166.0,self.bounds.size.width-8.0);',r'''        if (NANShapeStyle()==4) {
            self.apertureCap.hidden=(NANInteger(@"NotificationIslandAppearanceMode",0,0,3)==0);
            CGFloat coverW=MIN(166.0,self.bounds.size.width-8.0);''')
# The full-cover style remains center-aligned in both compact and expanded
# modes. Do not shrink the reserved sensor area or put text behind hardware.
rep('    if (NANShapeStyle()==4 && docked) width=MAX(width,210.0);','    if (NANShapeStyle()==4 && docked) width=MAX(width,230.0);')
rep('1.0.11 Full Cover loaded','1.0.12 Full Cover Plus loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.12 Full Cover Plus.")
