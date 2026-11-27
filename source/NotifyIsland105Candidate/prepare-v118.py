#!/usr/bin/env python3
"""1.0.18: compact-only downward swipe dismissal."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.18 missing anchor: "+a[:140])
    s=s.replace(a,b,1)
rep('@property(nonatomic,strong) UITapGestureRecognizer *doubleTap;',r'''@property(nonatomic,strong) UITapGestureRecognizer *doubleTap;
@property(nonatomic,strong) UISwipeGestureRecognizer *compactSwipeDown;''')
rep('    [self addGestureRecognizer:_doubleTap];',r'''    [self addGestureRecognizer:_doubleTap];
    _compactSwipeDown=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(compactSwipeDismiss:)];
    _compactSwipeDown.direction=UISwipeGestureRecognizerDirectionDown;
    _compactSwipeDown.numberOfTouchesRequired=1;
    _compactSwipeDown.delegate=self;
    _compactSwipeDown.cancelsTouchesInView=YES;
    [self addGestureRecognizer:_compactSwipeDown];''')
rep('    if (recognizer != self.doubleTap) return YES;',r'''    if (recognizer==self.compactSwipeDown) {
        if (NANExpanded || NANAnimating || NANClosing || self.replyAction || NANIslandView!=self) return NO;
        for (UIView *v=touch.view; v && v!=self; v=v.superview) {
            if ([v isKindOfClass:UIControl.class] || v==self.nativeActionScroll) return NO;
        }
        return YES;
    }
    if (recognizer != self.doubleTap) return YES;''')
rep('- (void)doubleTapDismiss:(UITapGestureRecognizer *)recognizer {',r'''- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer==self.compactSwipeDown)
        return !NANExpanded && !NANAnimating && !NANClosing && !self.replyAction && NANIslandView==self;
    return YES;
}
- (void)compactSwipeDismiss:(UISwipeGestureRecognizer *)recognizer {
    if (recognizer.state!=UIGestureRecognizerStateRecognized || NANExpanded || NANAnimating ||
        NANClosing || self.replyAction || NANIslandView!=self) return;
    // Dismiss only our presentation. Do not clear the stock notification.
    [self dismissTapped];
}
- (void)doubleTapDismiss:(UITapGestureRecognizer *)recognizer {''')
rep('1.0.16 Composer Studio loaded','1.0.18 Compact Swipe loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.18 Compact Swipe.")
