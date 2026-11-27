#!/usr/bin/env python3
"""Visual Studio positioning and presentation animation on top of validated 1.0.5."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(old,new):
    global s
    if old not in s: raise SystemExit("1.0.6 anchor missing: "+old[:120])
    s=s.replace(old,new,1)
rep("static BOOL NANTestMode = NO;", """static BOOL NANTestMode = NO;
static BOOL NANAnimating = NO;
static BOOL NANClosing = NO;
static NSUInteger NANAnimationGeneration = 0;
static CGRect NANAnimationWindowBounds;
static CGRect NANAnimationTargetFrame;""")
rep('    CGFloat y = landscape ? CGRectGetMinY(safe) + 4.0 : CGRectGetMinY(bounds) + requestedY;',
r'''    // The new Studio stores one normalized vertical coordinate. Preserve
    // the old position until the user explicitly chooses a new position.
    id position = NANPreference(@"NotificationIslandVerticalPosition");
    CGFloat span = MAX(0.0, maxHeight - height);
    CGFloat y;
    if ([position isKindOfClass:NSNumber.class] && isfinite([position doubleValue])) {
        CGFloat fraction = MIN(MAX([position doubleValue], 0.0), 1.0);
        y = CGRectGetMinY(safe) + span * fraction;
    } else {
        y = landscape ? CGRectGetMinY(safe) + 4.0 : CGRectGetMinY(bounds) + requestedY;
    }''')
rep("static void NANRemoveIsland(void);","static void NANRemoveIsland(void);\nstatic void NANAnimateDismiss(void);")
rep("    CGRect frame = NANFrame(expanded);\n    if (CGRectIsEmpty(frame)) return;","    if (NANAnimating) return;\n    CGRect frame = NANFrame(expanded);\n    if (CGRectIsEmpty(frame)) return;")
rep("    // Closing the overlay must not hide, clear, or defer the stock list item.\n    NANRemoveIsland();","    // Closing the overlay must not hide, clear, or defer the stock list item.\n    NANAnimateDismiss();")
rep("static void NANRemoveIslandOnMain(void) {\n", """static void NANRemoveIslandOnMain(void) {
    ++NANAnimationGeneration;
    NANAnimating = NO;
    NANClosing = NO;
    [NANIslandView.layer removeAllAnimations];
""")
anchor="static void NANStartTimers(void) {"
anim=r'''// The aperture is a physical cutout. On the target 14 Pro Max the
// portrait capsule is approximately 126 x 37 pt at the top center.
// Use a local transform rather than modifying Apple's own aperture view.
static CGAffineTransform NANIslandOriginTransform(CGRect target) {
    UIWindow *window = NANSystemWindow;
    CGRect bounds = window.bounds;
    BOOL landscape = CGRectGetWidth(bounds) > CGRectGetHeight(bounds);
    if (landscape || UIAccessibilityIsReduceMotionEnabled())
        return CGAffineTransformIdentity;
    CGFloat anchorX = CGRectGetMidX(bounds);
    CGFloat anchorY = CGRectGetMinY(bounds) + MAX(29.0, MIN(38.0, window.safeAreaInsets.top * 0.60));
    CGFloat sx = MIN(1.0, 126.0 / MAX(CGRectGetWidth(target), 1.0));
    CGFloat sy = MIN(1.0, 37.0 / MAX(CGRectGetHeight(target), 1.0));
    return CGAffineTransformMake(sx, 0, 0, sy,
        anchorX - CGRectGetMidX(target), anchorY - CGRectGetMidY(target));
}

static void NANAnimateShow(NANNotificationCard *card) {
    if (!NANBool(@"NotificationIslandAnimationEnabled", YES)) return;
    CGRect target = card.frame;
    NSUInteger generation = ++NANAnimationGeneration;
    NANAnimating = YES;
    NANClosing = NO;
    NANAnimationWindowBounds = NANSystemWindow.bounds;
    NANAnimationTargetFrame = target;
    card.userInteractionEnabled = NO;
    card.transform = NANIslandOriginTransform(target);
    card.alpha = 0.0;
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    NSTimeInterval duration = reduce ? 0.18 : 0.36;
    [UIView animateWithDuration:duration delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
        card.transform = CGAffineTransformIdentity;
        card.alpha = 1.0;
    } completion:^(__unused BOOL finished) {
        if (generation != NANAnimationGeneration || NANIslandView != card || NANClosing) return;
        NANAnimating = NO;
        card.transform = CGAffineTransformIdentity;
        card.alpha = 1.0;
        card.userInteractionEnabled = YES;
        [card setExpanded:NANExpanded animated:NO];
    }];
}

static void NANAnimateDismiss(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ NANAnimateDismiss(); });
        return;
    }
    if (NANClosing) return;
    NANNotificationCard *card = (NANNotificationCard *)NANIslandView;
    if (!card || !NANBool(@"NotificationIslandAnimationEnabled", YES)) {
        NANRemoveIslandOnMain();
        return;
    }
    [NANHideTimer invalidate]; NANHideTimer = nil;
    CGRect target = NANFrame(NANExpanded);
    if (CGRectIsEmpty(target)) { NANRemoveIslandOnMain(); return; }
    NSUInteger generation = ++NANAnimationGeneration;
    NANClosing = YES;
    NANAnimating = YES;
    NANAnimationWindowBounds = NANSystemWindow.bounds;
    NANAnimationTargetFrame = target;
    card.userInteractionEnabled = NO;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0.16 : 0.28 delay:0 options:UIViewAnimationOptionCurveEaseInOut | UIViewAnimationOptionBeginFromCurrentState animations:^{
        card.transform = NANIslandOriginTransform(target);
        card.alpha = 0.0;
    } completion:^(__unused BOOL finished) {
        if (generation == NANAnimationGeneration && NANIslandView == card) NANRemoveIslandOnMain();
    }];
}

'''
rep(anchor,anim+anchor)
# Every timeout retracts; app launch/disable remain immediate.
s=s.replace('block:^(__unused NSTimer *timer) { NANRemoveIsland(); }','block:^(__unused NSTimer *timer) { NANAnimateDismiss(); }')
s=s.replace('block:^(__unused NSTimer *timer) { NANTestMode = NO; NANRemoveIsland(); }','block:^(__unused NSTimer *timer) { NANAnimateDismiss(); }')
rep("    NANStartTimers();\n    return YES;","    NANAnimateShow(card);\n    NANStartTimers();\n    return YES;")
rep('        if (!CGRectEqualToRect(target, NANIslandView.frame)) {',
r'''        if (NANAnimating) {
            // Don't fight UIKit's in-flight transform. On rotation or safe-area
            // changes, cancel the old generation and snap safely to the new frame.
            if (CGRectEqualToRect(NANAnimationWindowBounds, self.bounds) &&
                CGRectEqualToRect(NANAnimationTargetFrame, target)) return;
            if (NANClosing) { NANRemoveIslandOnMain(); return; }
            ++NANAnimationGeneration;
            NANAnimating = NO;
            [NANIslandView.layer removeAllAnimations];
            NANIslandView.transform = CGAffineTransformIdentity;
            NANIslandView.alpha = 1.0;
            NANIslandView.userInteractionEnabled = YES;
        }
        if (!CGRectEqualToRect(target, NANIslandView.frame)) {''')
rep("scheduledTimerWithTimeInterval:60.0 repeats:NO block:^(__unused NSTimer *timer) { NANAnimateDismiss(); }","scheduledTimerWithTimeInterval:NANDismissInterval() repeats:NO block:^(__unused NSTimer *timer) { NANAnimateDismiss(); }")
rep("1.0.5 candidate loaded","1.0.6 Visual Studio loaded")
p.write_text(s)
print("Prepared Notify Island 1.0.6 Visual Studio runtime.")
