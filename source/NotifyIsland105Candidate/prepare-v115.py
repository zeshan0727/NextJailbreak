#!/usr/bin/env python3
"""1.0.15: compact slider scales content only, never notification metadata."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.15 missing anchor: "+a[:140])
    s=s.replace(a,b,1)
rep('    CGFloat compactHeaderHeight=MAX(18.0,ceil(13.0*scale*1.22));','    CGFloat compactHeaderHeight=18.0;')
rep('self.appLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];','self.appLabel.font = [UIFont systemFontOfSize:13 * (NANExpanded ? expandedScale : 1.0) weight:UIFontWeightSemibold];')
rep('self.timeLabel.font = [UIFont systemFontOfSize:10.5 * scale weight:UIFontWeightMedium];','self.timeLabel.font = [UIFont systemFontOfSize:10.5 * (NANExpanded ? expandedScale : 1.0) weight:UIFontWeightMedium];')
# Keep the hidden compact title at default size, too. Only the visible
# content/body label consumes the compact content scale.
rep('self.titleLabel.font = [UIFont systemFontOfSize:13 * scale weight:UIFontWeightSemibold];','self.titleLabel.font = [UIFont systemFontOfSize:13 * (NANExpanded ? expandedScale : 1.0) weight:UIFontWeightSemibold];')
rep('1.0.14 Live Draft loaded','1.0.15 Content Text loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.15 Content Text.")
