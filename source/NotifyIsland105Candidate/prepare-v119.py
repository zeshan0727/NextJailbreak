#!/usr/bin/env python3
"""1.0.19: keep replaced native transient banners suppressed through early island dismissal."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.19 missing anchor: "+a[:140])
    s=s.replace(a,b,1)

rep('static NSHashTable<UIView *> *NANSuppressedViews;',r'''static NSHashTable<UIView *> *NANSuppressedViews;
static NSHashTable<UIViewController *> *NANSuppressedControllers;
// Session-only bounded identities, recorded only after successful replacement
// of a verified transient banner. No notification text is retained here.
static NSMutableOrderedSet<NSString *> *NANReplacedBannerFingerprints;''')
a=s.index('static void NANRestoreBanner(UIView *view) {')
b=s.index('\nstatic void NANRemoveIsland(void);',a)
s=s[:a]+r'''static void NANRestoreBanner(UIView *view) {
    if (!view) return;
    NSArray *state=objc_getAssociatedObject(view,&NANBannerSavedStateKey);
    if (!state) return;
    // Clear the association first: restoring can cause UIKit layout callbacks.
    objc_setAssociatedObject(view,&NANBannerSavedStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NANSuppressedViews removeObject:view];
    [UIView performWithoutAnimation:^{
        view.hidden=[state[2] boolValue];
        view.alpha=[state[0] doubleValue];
        view.userInteractionEnabled=[state[1] boolValue];
    }];
}
static void NANRestoreAllBanners(void) {
    [NANReplacedBannerFingerprints removeAllObjects];
    [NANSuppressedControllers removeAllObjects];
    for (UIView *view in NANSuppressedViews.allObjects) NANRestoreBanner(view);
}
static BOOL NANBannerReplacementEnabled(void) {
    return NANBool(@"NotificationIslandEnabled",YES) &&
        NANBool(@"NotificationIslandReplaceStockBanner",YES);
}
static void NANSuppressBanner(UIViewController *controller,NSString *fingerprint) {
    if (!controller.isViewLoaded || !fingerprint.length ||
        !NANBannerReplacementEnabled() || !NANIsTransientBanner(controller)) return;
    UIView *view=controller.view;
    NSArray *state=objc_getAssociatedObject(view,&NANBannerSavedStateKey);
    if (state && ![state[3] isEqualToString:fingerprint]) {
        NANRestoreBanner(view);
        state=nil;
    }
    if (!state) {
        objc_setAssociatedObject(view,&NANBannerSavedStateKey,
            @[@(view.alpha),@(view.userInteractionEnabled),@(view.hidden),[fingerprint copy]],
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [NANSuppressedViews addObject:view];
    }
    [NANSuppressedControllers addObject:controller];
    [NANReplacedBannerFingerprints addObject:fingerprint];
    while (NANReplacedBannerFingerprints.count>256)
        [NANReplacedBannerFingerprints removeObjectAtIndex:0];
    // Native presentation animations can restore alpha. Hidden is independent
    // of that animation. Only the identified transient short-look is changed.
    [UIView performWithoutAnimation:^{
        if (!view.hidden) view.hidden=YES;
        if (view.alpha!=0.0) view.alpha=0.0;
        if (view.userInteractionEnabled) view.userInteractionEnabled=NO;
    }];
}
static void NANReassertSuppressedBanners(void);
'''+s[b:]

# Do not tie suppression to NANIslandView or NANCurrentModel's lifetime.
# Reapply just before the overlay starts retracting and when it is removed.
rep('    ++NANAnimationGeneration;\n    NANAnimating = NO;\n    NANClosing = NO;\n    [NANIslandView.layer removeAllAnimations];',r'''    NANReassertSuppressedBanners();
    ++NANAnimationGeneration;
    NANAnimating = NO;
    NANClosing = NO;
    [NANIslandView.layer removeAllAnimations];''')
rep('    if (NANClosing) return;\n    NANNotificationCard *card = (NANNotificationCard *)NANIslandView;',r'''    if (NANClosing) return;
    NANReassertSuppressedBanners();
    NANNotificationCard *card = (NANNotificationCard *)NANIslandView;''')

# On each short-look lifecycle callback validate the actual notification
# identity and the view hierarchy before retaining or restoring suppression.
rep('static void NANMaybePresent(UIViewController *controller) {',r'''static BOOL NANMaintainBannerSuppression(UIViewController *controller,NSString *fingerprint) {
    if (!controller.isViewLoaded) return NO;
    UIView *view=controller.view;
    NSArray *state=objc_getAssociatedObject(view,&NANBannerSavedStateKey);
    if (!NANBannerReplacementEnabled() || !NANIsTransientBanner(controller) || !fingerprint.length) {
        NANRestoreBanner(view);
        [NANSuppressedControllers removeObject:controller];
        return NO;
    }
    if (state && ![state[3] isEqualToString:fingerprint]) {
        NANRestoreBanner(view);
        [NANSuppressedControllers removeObject:controller];
        state=nil;
    }
    if (state || [NANReplacedBannerFingerprints containsObject:fingerprint]) {
        NANSuppressBanner(controller,fingerprint);
        return YES;
    }
    return NO;
}
static void NANReassertSuppressedBanners(void) {
    for (UIViewController *controller in NANSuppressedControllers.allObjects) {
        if (!controller.isViewLoaded) {
            [NANSuppressedControllers removeObject:controller];
            continue;
        }
        NSDictionary *model=NANModelForRequest(NANSafeValue(controller,@"notificationRequest"));
        NANMaintainBannerSuppression(controller,NANFingerprint(model));
    }
}
static void NANMaybePresent(UIViewController *controller) {''')
rep('    if (!NANBool(@"NotificationIslandEnabled", YES)) return;\n    NSDictionary *model = NANModelForRequest(NANSafeValue(controller, @"notificationRequest"));\n    if (!model) return;\n    BOOL banner = NANIsTransientBanner(controller);',r'''    NSDictionary *model = NANModelForRequest(NANSafeValue(controller, @"notificationRequest"));
    NSString *fingerprint=NANFingerprint(model);
    if (NANMaintainBannerSuppression(controller,fingerprint)) return;
    if (!NANBool(@"NotificationIslandEnabled", YES) || !model) return;
    BOOL banner = NANIsTransientBanner(controller);''')
rep('        NANSuppressBanner(controller);','        NANSuppressBanner(controller,fingerprint);')
rep('    if (self.isViewLoaded) NANRestoreBanner(self.view);\n    NANMaybePresent(self);','    NANMaybePresent(self);')
rep('    if (!self.isViewLoaded) return;\n    if (!NANIsTransientBanner(self) || !NANBool(@"NotificationIslandEnabled", YES) ||\n        !NANBool(@"NotificationIslandReplaceStockBanner", YES)) NANRestoreBanner(self.view);',r'''    if (!self.isViewLoaded) return;
    // Avoid model work on ordinary notification list layout. Only already
    // suppressed controllers can require reassertion or recycling cleanup.
    if (objc_getAssociatedObject(self.view,&NANBannerSavedStateKey) ||
        [NANSuppressedControllers containsObject:self]) {
        NSDictionary *model=NANModelForRequest(NANSafeValue(self,@"notificationRequest"));
        NANMaintainBannerSuppression(self,NANFingerprint(model));
    }''')
rep('    if (self.isViewLoaded) NANRestoreBanner(self.view);\n}\n%end',r'''    if (self.isViewLoaded) NANRestoreBanner(self.view);
    [NANSuppressedControllers removeObject:self];
}
%end''')
rep('        NANSuppressedViews = [NSHashTable weakObjectsHashTable];',r'''        NANSuppressedViews = [NSHashTable weakObjectsHashTable];
        NANSuppressedControllers=[NSHashTable weakObjectsHashTable];
        NANReplacedBannerFingerprints=[NSMutableOrderedSet orderedSet];''')
rep('1.0.18 Compact Swipe loaded','1.0.19 Banner Lifecycle loaded')
p.write_text(s)
print("Prepared Notify Island 1.0.19 Banner Lifecycle.")
