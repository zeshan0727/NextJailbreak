#!/usr/bin/env python3
"""Apply the candidate stability changes after the archived 4.5.1 preparation."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def replace(old,new):
    global s
    if old not in s:
        raise SystemExit("Missing source anchor: "+old[:100])
    s=s.replace(old,new,1)
def between(a,b,new):
    global s
    i=s.index(a); j=s.index(b,i+len(a))
    s=s[:i]+new+s[j:]
replace("static BOOL NANTestMode = NO;", """static BOOL NANTestMode = NO;
static NSMutableDictionary<NSString *, id> *NANPreferenceCache;
static NSHashTable<UIView *> *NANSuppressedViews;
static char NANBannerSavedStateKey;""")
between("static id NANPreference(NSString *key) {","\nstatic BOOL NANBool",r'''static id NANPreference(NSString *key) {
    if (!NANPreferenceCache) {
        NANPreferenceCache = [NSMutableDictionary new];
        CFPreferencesAppSynchronize((__bridge CFStringRef)NANPrefsDomain);
    }
    id value = NANPreferenceCache[key];
    if (!value) {
        value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)NANPrefsDomain));
        NANPreferenceCache[key] = value ?: NSNull.null;
    }
    return value == NSNull.null ? nil : value;
}
''')
between("static BOOL NANIsUILocked(void) {","\nstatic NSString *NANApplicationName",r'''// Read authentication state, not the presence of the Cover Sheet.
// Unknown or unavailable state must keep message content private.
static BOOL NANIsUILocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance");
    id manager = (cls && [cls respondsToSelector:shared]) ? ((id(*)(id,SEL))objc_msgSend)(cls, shared) : nil;
    if (!manager) return YES;
    SEL authSelector = NSSelectorFromString(@"isAuthenticated");
    id auth = NANSafeValue(manager, @"_userAuthController");
    if (!auth) auth = NANSafeValue(manager, @"userAuthController");
    if (auth && [auth respondsToSelector:authSelector]) {
        return !((BOOL(*)(id,SEL))objc_msgSend)(auth, authSelector);
    }
    SEL locked = NSSelectorFromString(@"isUILocked");
    return [manager respondsToSelector:locked] ? ((BOOL(*)(id,SEL))objc_msgSend)(manager, locked) : YES;
}
''')
between("static CGRect NANFrame(BOOL expanded) {","\nstatic void NANRemoveIsland(void);",r'''static CGRect NANFrame(BOOL expanded) {
    UIWindow *window = NANSystemWindow;
    if (!window) return CGRectZero;
    CGRect bounds = window.bounds;
    if (CGRectIsEmpty(bounds)) return CGRectZero;
    UIInterfaceOrientation orientation = window.windowScene.interfaceOrientation;
    BOOL landscape = CGRectGetWidth(bounds) > CGRectGetHeight(bounds);
    // Never place a portrait card in a known landscape coordinate system.
    if (UIInterfaceOrientationIsLandscape(orientation) && !landscape) return CGRectZero;
    if (landscape && !NANBool(@"NotificationIslandLandscapeEnabled", YES)) return CGRectZero;
    CGRect safe = UIEdgeInsetsInsetRect(bounds, window.safeAreaInsets);
    safe = CGRectInset(safe, 8.0, 4.0);
    CGFloat maxWidth = CGRectGetWidth(safe), maxHeight = CGRectGetHeight(safe);
    if (maxWidth < 190.0 || maxHeight < (expanded ? 125.0 : 58.0)) return CGRectZero;
    CGFloat width = NANFloat(expanded ? @"NotificationIslandExpandedWidth" : @"NotificationIslandCompactWidth",
                             expanded ? 405.0 : 330.0, 190.0, 600.0);
    CGFloat height = NANFloat(expanded ? @"NotificationIslandExpandedHeight" : @"NotificationIslandCompactHeight",
                              expanded ? 150.0 : 68.0, expanded ? 125.0 : 58.0, expanded ? 240.0 : 110.0);
    width = MIN(width, maxWidth); height = MIN(height, maxHeight);
    CGFloat requestedY = NANFloat(expanded ? @"NotificationIslandExpandedY" : @"NotificationIslandCompactY",
                                  48.0, -10.0, 220.0);
    CGFloat y = landscape ? CGRectGetMinY(safe) + 4.0 : CGRectGetMinY(bounds) + requestedY;
    y = MAX(CGRectGetMinY(safe), MIN(y, CGRectGetMaxY(safe) - height));
    CGFloat offset = NANFloat(@"NotificationIslandHorizontalOffset", 0.0, -140.0, 140.0);
    CGFloat x = CGRectGetMidX(safe) - width/2.0 + (landscape ? 0.0 : offset);
    x = MAX(CGRectGetMinX(safe), MIN(x, CGRectGetMaxX(safe)-width));
    return CGRectIntegral(CGRectMake(x,y,width,height));
}

// Shared short-look views may also back notification history. Suppress only
// an explicitly identified transient banner, never a list or Cover Sheet card.
static BOOL NANIsTransientBanner(UIViewController *controller) {
    BOOL banner = NO;
    UIViewController *vc = controller;
    for (NSUInteger depth=0; vc && depth<18; depth++, vc=vc.parentViewController) {
        NSString *name = NSStringFromClass(vc.class);
        if ([name containsString:@"NotificationList"] || [name containsString:@"NotificationCenter"] ||
            [name containsString:@"CoverSheet"]) return NO;
        if ([name hasPrefix:@"NCNotificationBanner"] || [name hasPrefix:@"SBBanner"] ||
            [name hasPrefix:@"SBNotificationBanner"]) banner = YES;
    }
    UIView *view = controller.isViewLoaded ? controller.view : nil;
    for (NSUInteger depth=0; view && depth<32; depth++, view=view.superview) {
        NSString *name = NSStringFromClass(view.class);
        if ([name containsString:@"NotificationList"] || [name containsString:@"NotificationCenter"] ||
            [name containsString:@"CoverSheet"]) return NO;
        if ([name hasPrefix:@"NCNotificationBanner"] || [name hasPrefix:@"SBBanner"] ||
            [name hasPrefix:@"SBNotificationBanner"]) banner = YES;
    }
    return banner;
}
static void NANRestoreBanner(UIView *view) {
    if (!view) return;
    NSArray *state = objc_getAssociatedObject(view, &NANBannerSavedStateKey);
    if (!state) return;
    view.alpha = [state[0] doubleValue];
    view.userInteractionEnabled = [state[1] boolValue];
    objc_setAssociatedObject(view, &NANBannerSavedStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [NANSuppressedViews removeObject:view];
}
static void NANRestoreAllBanners(void) {
    for (UIView *view in NANSuppressedViews.allObjects) NANRestoreBanner(view);
}
static void NANSuppressBanner(UIViewController *controller) {
    if (!controller.isViewLoaded || !NANIsTransientBanner(controller)) return;
    UIView *view = controller.view;
    if (!objc_getAssociatedObject(view, &NANBannerSavedStateKey)) {
        objc_setAssociatedObject(view, &NANBannerSavedStateKey, @[@(view.alpha), @(view.userInteractionEnabled)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [NANSuppressedViews addObject:view];
    }
    view.alpha = 0.0;
    view.userInteractionEnabled = NO;
}
''')
replace("static void NANPresentModel(NSDictionary *model, UIViewController *shortLook);","static BOOL NANPresentModel(NSDictionary *model, UIViewController *shortLook);")
replace("CGFloat timeWidth = NANExpanded ? 126.0 : 106.0;","CGFloat timeWidth = MIN(NANExpanded ? 126.0 : 106.0, self.bounds.size.width * 0.28);")
replace("CGFloat appWidth = MAX(42.0, timeX - headerGap - textX);","CGFloat appWidth = MAX(0.0, timeX - headerGap - textX);")
replace("MAX(28, buttonY - 62)","MAX(0, buttonY - 62)")
replace("BOOL locked = NANIsUILocked();","BOOL locked = NANIsUILocked();\n    self.openButton.enabled = !locked || NANTestMode;")
replace("    NANExpanded = expanded;\n    CGRect frame = NANFrame(expanded);","    CGRect frame = NANFrame(expanded);\n    if (CGRectIsEmpty(frame)) return;\n    NANExpanded = expanded;")
replace("    if (self.fingerprint.length) NANMarkDismissed(self.fingerprint);\n    if (self.bundleID.length)","    if (NANIsUILocked()) return;\n    if (self.bundleID.length)")
between("- (void)dismissTapped {","\n@end",r'''- (void)dismissTapped {
    // Closing the overlay must not hide, clear, or defer the stock list item.
    NANRemoveIsland();
}
''')
replace("    NANExpanded = NO;\n}","    NANExpanded = NO;\n    NANTestMode = NO;\n}")
replace("scheduledTimerWithTimeInterval:0.8 repeats:YES","scheduledTimerWithTimeInterval:0.25 repeats:YES")
between("static void NANPresentModel(NSDictionary *model, UIViewController *shortLook) {","\nstatic NSDictionary *NANModelForRequest",r'''static BOOL NANPresentModel(NSDictionary *model, UIViewController *shortLook) {
    // UIKit lifecycle callbacks and the preview handler run on the main queue.
    if (!NSThread.isMainThread || !NANBool(@"NotificationIslandEnabled", YES) ||
        !model || !NANSystemWindow || CGRectIsEmpty(NANFrame(NO))) return NO;
    NSString *fingerprint = NANFingerprint(model);
    BOOL test = [model[@"test"] boolValue];
    if (!test && !fingerprint.length) return NO;
    if (!test && [NANSeenFingerprints containsObject:fingerprint]) {
        // A repeated callback is safe to suppress only while its island exists.
        return NANIslandView && [NANFingerprint(NANCurrentModel) isEqualToString:fingerprint];
    }
    NANRemoveIslandOnMain();
    NANTestMode = test;
    NANCurrentModel = model;
    NANCurrentShortLook = shortLook;
    NANNotificationCard *card = [[NANNotificationCard alloc] initWithFrame:CGRectZero];
    [NANSystemWindow addSubview:card];
    NANIslandView = card;
    [card applyModel:model];
    [card setExpanded:NO animated:NO];
    if (CGRectIsEmpty(card.frame)) { NANRemoveIslandOnMain(); return NO; }
    [NANSystemWindow bringSubviewToFront:card];
    if (!test) {
        [NANSeenFingerprints addObject:fingerprint];
        while (NANSeenFingerprints.count > 256) [NANSeenFingerprints removeObjectAtIndex:0];
    }
    NANStartTimers();
    return YES;
}
''')
between("    NSDate *timestamp = NANSafeValue(request, @\"timestamp\");","\n    return @{",r'''    NSDate *timestamp = NANSafeValue(request, @"timestamp");
    if (![timestamp isKindOfClass:NSDate.class]) timestamp = NANSafeValue(request, @"date");
    BOOL hasDate = [timestamp isKindOfClass:NSDate.class];
    if (!hasDate) timestamp = NSDate.date;
    if (!identifier.length && !hasDate) return nil;
    if (!identifier.length) identifier = [NSString stringWithFormat:@"%.0f", timestamp.timeIntervalSince1970 * 1000.0];
    NSString *fingerprint = hasDate ? [NSString stringWithFormat:@"%@|%@|%.0f", bundleID ?: @"", identifier, timestamp.timeIntervalSince1970 * 1000.0] : [NSString stringWithFormat:@"%@|%@", bundleID ?: @"", identifier];
''')
replace('        @"fingerprint": fingerprint\n    };','        @"fingerprint": fingerprint,\n        @"deliveryDate": hasDate ? timestamp : NSNull.null\n    };')
replace('        if (!NANBool(@"NotificationIslandEnabled", YES)) { NANRemoveIsland(); return; }','        NANPreferenceCache = nil;\n        if (!NANBool(@"NotificationIslandEnabled", YES)) { NANRestoreAllBanners(); NANRemoveIsland(); return; }\n        if (!NANBool(@"NotificationIslandReplaceStockBanner", YES)) NANRestoreAllBanners();')
replace("        NANTestMode = YES;\n","")
replace('            @"fingerprint": identifier\n        };','            @"fingerprint": identifier,\n            @"test": @YES\n        };')
replace("        NANPresentModel(sample, nil);","        if (!NANPresentModel(sample, nil)) return;")
between("%hook SBSystemApertureWindow","\n__attribute__((constructor))",r'''static void NANMaybePresent(UIViewController *controller) {
    if (!NANBool(@"NotificationIslandEnabled", YES)) return;
    NSDictionary *model = NANModelForRequest(NANSafeValue(controller, @"notificationRequest"));
    if (!model) return;
    BOOL banner = NANIsTransientBanner(controller);
    // List cells may be recycled while scrolling. Only consider fresh arrivals.
    if (!banner) {
        id date = model[@"deliveryDate"];
        if (![date isKindOfClass:NSDate.class] || fabs([date timeIntervalSinceNow]) > 3.0) return;
    }
    if (NANPresentModel(model, controller) && banner && NANBool(@"NotificationIslandReplaceStockBanner", YES)) {
        NANSuppressBanner(controller);
    }
}

static void NANPrivacyStateChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([NANIslandView isKindOfClass:NANNotificationCard.class]) [(NANNotificationCard *)NANIslandView applyPrivacy];
    });
}

%hook SBSystemApertureWindow
- (void)didMoveToScreen:(UIScreen *)screen {
    %orig;
    if (screen == UIScreen.mainScreen) NANSystemWindow = self;
}
- (void)layoutSubviews {
    %orig;
    if (self.screen != UIScreen.mainScreen) return;
    NANSystemWindow = self;
    if (NANIslandView.superview == self) {
        CGRect target = NANFrame(NANExpanded);
        if (CGRectIsEmpty(target)) { NANRestoreAllBanners(); NANRemoveIslandOnMain(); return; }
        if (!CGRectEqualToRect(target, NANIslandView.frame)) {
            NANIslandView.frame = target;
            NANIslandView.layer.cornerRadius = MAX(18.0, MIN(target.size.height/2.0, NANExpanded ? 30.0 : 28.0));
            [NANIslandView setNeedsLayout];
        }
        [self bringSubviewToFront:NANIslandView];
    }
}
%end

%hook NCNotificationShortLookViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (self.isViewLoaded) NANRestoreBanner(self.view);
    NANMaybePresent(self);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NANMaybePresent(self);
}
- (void)viewDidLayoutSubviews {
    %orig;
    if (!self.isViewLoaded) return;
    if (!NANIsTransientBanner(self) || !NANBool(@"NotificationIslandEnabled", YES) ||
        !NANBool(@"NotificationIslandReplaceStockBanner", YES)) NANRestoreBanner(self.view);
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (self.isViewLoaded) NANRestoreBanner(self.view);
}
%end
''')
replace("#import <objc/runtime.h>","#import <objc/runtime.h>\n#import <math.h>")
replace("        NANSeenFingerprints = [NSMutableOrderedSet orderedSet];","        NANSeenFingerprints = [NSMutableOrderedSet orderedSet];\n        NANSuppressedViews = [NSHashTable weakObjectsHashTable];\n        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NANPrivacyStateChanged, CFSTR(\"com.apple.springboard.lockstate\"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);")
replace('NSLog(@"[NextAura] Notification Island 4.5.1 loaded; stable centered action-button titles");','NSLog(@"[Notify Island] 1.0.5 candidate loaded");')
# Do not persist delivery identifiers; the session set is sufficient.
between("static NSDictionary *NANDismissedFingerprints(void) {","\nstatic CGRect NANFrame", "")
replace('static NSString * const NANDismissedKey = @"NotificationIslandDismissedFingerprints";\n','')
p.write_text(s)
print("Prepared Notify Island 1.0.5 candidate.")
