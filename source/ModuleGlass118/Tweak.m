#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>

extern void MSHookMessageEx(Class _class, SEL message, IMP hook, IMP *old);

static NSString * const MGBackgroundDirectory = @"/var/mobile/Library/Preferences/NextSolutionTweaks/CCBackgrounds";
static NSString * const MGLogDirectory = @"/var/mobile/Library/Logs/NextSolution";
static NSString * const MGLogPath = @"/var/mobile/Library/Logs/NextSolution/module-glass.log";
static NSString * const MGPreviousLogPath = @"/var/mobile/Library/Logs/NextSolution/module-glass.previous.log";
static CFStringRef const MGPrefsDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const MGLicensePrefsDomain = CFSTR("com.nextsolution.moduleglass");
static BOOL MGLicenseActiveCached = NO;
static NSInteger const MGImageTag = 0x4D470106;
static NSInteger const MGVolumeIconOverlayTag = 0x4D475649;
static NSInteger const MGVolumePercentageOverlayTag = 0x4D475650;
static NSInteger const MGSliderShellTag = 0x4D475353;

static NSHashTable *MGControllers;
static NSHashTable<UIImageView *> *MGOwnedOverlays;
static char MGOverlayOwnerKey;
static char MGCompactRectKey;
static char MGRecoveryPendingKey;
static char MGRecoveryCandidateRectKey;
static char MGRecoveryCandidateTimeKey;
static BOOL MGRecoverySweepActive = NO;
static NSUInteger MGRecoverySweepGeneration = 0;

// A view owned by this tweak must never follow a native reparenting operation.
@interface MGOwnedImageView : UIImageView
@property(nonatomic, weak) UIView *mgExpectedHost;
@end
@implementation MGOwnedImageView
- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview && self.mgExpectedHost && self.superview != self.mgExpectedHost) self.hidden=YES;
}
@end

static void MGRegisterOverlay(UIImageView *image, id owner, UIView *host) {
    if (!image) return;
    [MGOwnedOverlays addObject:image];
    if (owner) {
        NSHashTable *owners=[NSHashTable weakObjectsHashTable];
        [owners addObject:owner];
        objc_setAssociatedObject(image,&MGOverlayOwnerKey,owners,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if ([image isKindOfClass:MGOwnedImageView.class]) ((MGOwnedImageView *)image).mgExpectedHost=host;
}
static void MGDetachOverlay(UIImageView *image) {
    if (!image) return;
    image.hidden=YES;
    [image.layer removeAllAnimations];
    [image removeFromSuperview];
}
static void MGDetachAllOwnedOverlays(void) {
    for (UIImageView *image in MGOwnedOverlays.allObjects) MGDetachOverlay(image);
}
static void MGHideControllerOverlays(id owner) {
    for (UIImageView *image in MGOwnedOverlays.allObjects) {
        NSHashTable *owners=objc_getAssociatedObject(image,&MGOverlayOwnerKey);
        if ([owners containsObject:owner]) image.hidden=YES;
    }
}
// While any Control Center module is transitioning, all Module Glass renderers
// are quarantined. Some Apple modules expand through a parent controller while
// their customized child controller continues receiving layout/value callbacks.
// A process-wide gate prevents those child callbacks from mutating the live
// hierarchy until Apple's transition has completed.
static BOOL MGGlobalTransitionQuarantine = NO;
static NSUInteger MGGlobalTransitionGeneration = 0;
static char MGLastDiagnosticKey;
static char MGVolumeOriginalAlphaKey;
static char MGVolumeOriginalIconAlphaKey;
static char MGVolumeIconOverlayKey;
static char MGVolumeOriginalPercentageAlphaKey;
static char MGVolumePercentageColorKey;
static char MGVolumeOriginalPercentageTextColorKey;
static char MGVolumeOriginalPercentageAttributedKey;
static char MGBrightnessOriginalLayerOpacityKey;
static char MGBlurOriginalAlphaKey;
static char MGVolumeFillMaskKey;
static char MGVolumeFillImageKey;
static char MGConnectivityOriginalBackgroundColorKey;
static char MGConnectivityOriginalLayerBackgroundColorKey;
static char MGCompactSizeKey;
static char MGCompactScreenSizeKey;
static char MGApplyInProgressKey;
static char MGLayoutPendingKey;
static BOOL MGDeferredImageReload = NO;
static BOOL MGCompactEligible(id controller, UIView *root, BOOL requireStable);
static void MGMarkRecovery(id controller);
static void MGStartRecoverySweep(void);
static void MGStartQuarantine(NSString *source);
static void MGRefreshAll(NSString *source, BOOL forceReloadImages);

static void (*MGOrigLabelSetText)(UILabel *, SEL, NSString *);
static void (*MGOrigLabelSetAttributedText)(UILabel *, SEL, NSAttributedString *);
static void (*MGOrigLabelSetTextColor)(UILabel *, SEL, UIColor *);

static void (*MGOrigModuleViewDidLoad)(id, SEL);
static void (*MGOrigModuleLayout)(id, SEL);
static void (*MGOrigContentViewDidLoad)(id, SEL);
static void (*MGOrigContentLayout)(id, SEL);
static void (*MGOrigSliderSetValue)(id, SEL, CGFloat);
static void (*MGOrigModuleWillTransition)(id, SEL, CGSize, id);
static void (*MGOrigContentWillTransition)(id, SEL, CGSize, id);

static void MGApplyController(id controller, NSString *source);
static void MGPostLayoutRecovery(id controller, NSString *source);

#pragma mark - Logging / preferences

static void MGRotateLogIfNeeded(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDictionary *attrs = [fm attributesOfItemAtPath:MGLogPath error:nil];
    if ([attrs fileSize] < 1024 * 1024) return;
    [fm removeItemAtPath:MGPreviousLogPath error:nil];
    [fm moveItemAtPath:MGLogPath toPath:MGPreviousLogPath error:nil];
}

static void MGLog(NSString *format, ...) {
    if (!format) return;
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:MGLogDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    MGRotateLogIfNeeded();
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", NSDate.date, body ?: @""];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (![fm fileExistsAtPath:MGLogPath]) [data writeToFile:MGLogPath atomically:YES];
    else {
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:MGLogPath];
        [fh seekToEndOfFile];
        [fh writeData:data];
        [fh closeFile];
    }
}

static id MGPreference(NSString *key) {
    if (!key.length) return nil;
    CFPreferencesAppSynchronize(MGPrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, MGPrefsDomain);
    return value ? CFBridgingRelease(value) : nil;
}

static BOOL MGLicenseValueIsActive(CFPropertyListRef value) {
    if (!value) return NO;
    if (CFGetTypeID(value) == CFBooleanGetTypeID()) return CFBooleanGetValue((CFBooleanRef)value);
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        int numeric = 0;
        return CFNumberGetValue((CFNumberRef)value, kCFNumberIntType, &numeric) && numeric != 0;
    }
    return NO;
}

static void MGLoadLicenseState(void) {
    CFPreferencesAppSynchronize(MGLicensePrefsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(CFSTR("licenseActive"), MGLicensePrefsDomain);
    if (!value) value = CFPreferencesCopyAppValue(CFSTR("licenseActivated"), MGLicensePrefsDomain);
    MGLicenseActiveCached = MGLicenseValueIsActive(value);
    if (value) CFRelease(value);
}

static BOOL MGIsLicenseGatedPreference(NSString *key) {
    return [key isEqualToString:@"CCModuleBackgroundsEnabled"] ||
           [key isEqualToString:@"CCModuleRemoveBlur"] ||
           [key isEqualToString:@"CCModuleControlGlowEnabled"] ||
           [key isEqualToString:@"CCModuleVolumeIconColorEnabled"];
}

static BOOL MGBoolPreference(NSString *key, BOOL fallback) {
    if (MGIsLicenseGatedPreference(key) && !MGLicenseActiveCached) return NO;
    id value = MGPreference(key);
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static CGFloat MGFloatPreference(NSString *key, CGFloat fallback) {
    id value = MGPreference(key);
    if (![value respondsToSelector:@selector(doubleValue)]) return fallback;
    CGFloat result = (CGFloat)[value doubleValue];
    return isfinite(result) ? result : fallback;
}

static BOOL MGVerboseDiagnosticsEnabled(void) {
    NSDictionary *control = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.nextsolution.nextlog.plist"];
    if (![control[@"enabled"] boolValue]) return NO;
    NSString *active = [[control[@"activeTweak"] description] lowercaseString];
    return [active containsString:@"moduleglass"] || [active containsString:@"module glass"] ||
           [active containsString:@"cc-module-backgrounds"] || [active containsString:@"ccbackground"];
}

#pragma mark - Identifier mapping

static NSString *MGNormalize(NSString *input) {
    if (!input.length) return @"";
    NSMutableString *result = [NSMutableString string];
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    NSString *lower = input.lowercaseString;
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([allowed characterIsMember:c]) [result appendFormat:@"%C", c];
    }
    return result;
}

static void MGAddIdentifierValue(id value, NSMutableArray<NSString *> *out, NSInteger depth) {
    if (!value || depth > 2) return;
    if ([value isKindOfClass:NSString.class]) {
        if ([(NSString *)value length]) [out addObject:value];
        return;
    }
    [out addObject:NSStringFromClass([value class]) ?: @""];
    for (NSString *key in @[@"bundleIdentifier", @"displayName", @"moduleIdentifier", @"identifier"]) {
        @try {
            id nested = [value valueForKey:key];
            if (nested && nested != value) MGAddIdentifierValue(nested, out, depth + 1);
        } @catch (__unused NSException *e) {}
    }
}

static NSArray<NSString *> *MGCandidatesForController(id controller) {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    if (!controller) return result;
    [result addObject:NSStringFromClass([controller class]) ?: @""];

    for (NSString *key in @[@"moduleIdentifier", @"_moduleIdentifier", @"identifier", @"_identifier",
                            @"module", @"_module", @"contentModule", @"_contentModule",
                            @"moduleInstance", @"_moduleInstance", @"parentViewController"]) {
        @try {
            id value = [controller valueForKey:key];
            if (value && value != controller) MGAddIdentifierValue(value, result, 0);
        } @catch (__unused NSException *e) {}
    }
    return result;
}

static BOOL MGContainsAny(NSString *blob, NSArray<NSString *> *needles) {
    for (NSString *needle in needles) if ([blob containsString:needle]) return YES;
    return NO;
}

static NSString *MGSlotForController(id controller, NSArray<NSString *> **outCandidates) {
    NSArray<NSString *> *candidates = MGCandidatesForController(controller);
    if (outCandidates) *outCandidates = candidates;
    NSString *blob = MGNormalize([candidates componentsJoinedByString:@"|"]);

    if (MGContainsAny(blob, @[@"comapplemediaremotecontrolcenteraudio", @"mediacontrolsaudiomodule", @"audiomodule", @"volume"])) return @"volume";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterdisplaymodule", @"ccuidisplaymodule", @"displaymodule", @"brightness"])) return @"brightness";
    if (MGContainsAny(blob, @[@"comapplemediaremotecontrolcenternowplaying", @"mediacontrolsmodule", @"nowplaying", @"mrui"])) return @"media";
    if (MGContainsAny(blob, @[@"comapplereplaykitcontrolcenterscreencapture", @"rpcontrolcentermodule", @"screencapture", @"screenrecord", @"recordingmodule"])) return @"screenrecording";
    if (MGContainsAny(blob, @[@"comapplemediaremotecontrolcenterairplaymirroring", @"mpavairplaymirroringmodule", @"screenmirror", @"airplaymirror"])) return @"screenmirroring";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterconnectivitymodule", @"ccuiconnectivitymodule", @"airplane"])) return @"connectivity";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterorientationlockmodule", @"ccuiorientationlockmodule", @"rotationlock"])) return @"orientation";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterlowpowermodule", @"ccuilowpowermodule", @"batterysaver"])) return @"lowpower";
    if (MGContainsAny(blob, @[@"comapplefocusuimodule", @"fccccontrolcentermodule", @"donotdisturb"])) return @"focus";
    if (MGContainsAny(blob, @[@"comapplecontrolcenterflashlightmodule", @"ccuiflashlightmodule", @"torch"])) return @"flashlight";
    if (MGContainsAny(blob, @[@"comapplemobiletimercontrolcentertimer", @"mtcctimermodule", @"clockmodule"])) return @"timer";
    if ([blob containsString:@"calculator"]) return @"calculator";
    if (MGContainsAny(blob, @[@"comapplecontrolcentercameramodule", @"ccuicameramodule"])) return @"camera";
    if (MGContainsAny(blob, @[@"comappleaccessibilitycontrolcenterhearingdevices", @"hacccontentmodule", @"hearing"])) return @"hearing";
    if (MGContainsAny(blob, @[@"quicknote", @"notes"])) return @"notes";
    if (MGContainsAny(blob, @[@"homecontrol", @"homekit", @"homemodule"])) return @"home";
    return @"other";
}

#pragma mark - View selection

static BOOL MGSizeLooksExpanded(CGSize size) {
    CGFloat w=fabs(size.width), h=fabs(size.height);
    CGSize screen=UIScreen.mainScreen.bounds.size;
    CGFloat sw=MIN(screen.width,screen.height), sh=MAX(screen.width,screen.height);
    CGFloat rw=MIN(w,h), rh=MAX(w,h);
    if (w<=1 || h<=1) return YES;
    return (rw>=sw*0.72 && rh>=sh*0.38) || rw>=sw*0.90 || rh>=sh*0.68;
}

static BOOL MGIsExpanded(UIView *root) {
    return !root || MGSizeLooksExpanded(root.bounds.size);
}

static BOOL MGClassNameContains(UIView *view, NSArray<NSString *> *needles) {
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    for (NSString *needle in needles) if ([name containsString:needle]) return YES;
    return NO;
}

static UIView *MGFindNativeBackground(UIView *root) {
    if (!root) return nil;
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        if (MGClassNameContains(view, @[@"mtmaterialview", @"ccuimodulebackground", @"contentmodulebackground", @"modulebackground"])) return view;
    }
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        UIView *found = MGFindNativeBackground(view);
        if (found) return found;
    }
    return nil;
}

static UIView *MGFindSliderView(UIView *root) {
    if (!root) return nil;
    if (MGClassNameContains(root, @[@"continuousslider", @"slider"])) return root;
    for (UIView *view in root.subviews) {
        if (view.tag == MGImageTag) continue;
        UIView *found = MGFindSliderView(view);
        if (found) return found;
    }
    return nil;
}

// Image-first helpers validated on Volume and now shared by all mapped compact modules.
static BOOL MGVolumeForegroundView(UIView *view) {
    if (!view) return NO;
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return YES;
    NSString *name = NSStringFromClass(view.class).lowercaseString;
    return [name containsString:@"label"] || [name containsString:@"glyph"] ||
           [name containsString:@"icon"] || [name containsString:@"button"] ||
           [name containsString:@"text"] || [name containsString:@"percentage"];
}

static BOOL MGVolumeSubtreeHasForeground(UIView *view) {
    if (!view) return NO;
    if (MGVolumeForegroundView(view)) return YES;
    for (UIView *child in view.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeSubtreeHasForeground(child)) return YES;
    }
    return NO;
}

static void MGRestoreVolumeVisuals(UIView *root) {
    if (!root) return;
    NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGVolumeOriginalAlphaKey);
    if (savedAlpha) {
        root.alpha = savedAlpha.doubleValue;
        objc_setAssociatedObject(root, &MGVolumeOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews) MGRestoreVolumeVisuals(child);
}

static BOOL MGVolumeObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
    if (!view || !slider || view == imageView || view.tag == MGImageTag) return NO;
    if ([imageView isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || MGVolumeSubtreeHasForeground(view)) return NO;

    CGRect converted = [view convertRect:view.bounds toView:slider];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(slider.bounds) * CGRectGetHeight(slider.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.10) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString;
    BOOL namedVisual = [name containsString:@"material"] || [name containsString:@"effect"] ||
                       [name containsString:@"blur"] || [name containsString:@"fill"] ||
                       [name containsString:@"progress"] || [name containsString:@"background"] ||
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"];
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18;
    return namedVisual || plainLargeVisual;
}

static NSUInteger MGApplyVolumeImageMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGVolumeObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGVolumeOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGVolumeOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyVolumeImageMode(child, imageView, suppressedClasses);
    }
    return count;
}

static BOOL MGBrightnessObscuringVisual(UIView *view, UIView *slider, UIImageView *imageView) {
    if (!view || !slider || view == imageView || view.tag == MGImageTag || view.tag == MGSliderShellTag) return NO;
    if ([imageView isDescendantOfView:view]) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIButton.class]) return NO;

    CGRect converted = [view convertRect:view.bounds toView:slider];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(slider.bounds) * CGRectGetHeight(slider.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.08) return NO;

    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    BOOL namedForeground = [name containsString:@"label"] || [name containsString:@"glyph"] ||
                           [name containsString:@"icon"] || [name containsString:@"button"] ||
                           [name containsString:@"text"] || [name containsString:@"percentage"] ||
                           [name containsString:@"sun"];
    if (namedForeground) return NO;

    if ([view isKindOfClass:UIImageView.class] && ratio < 0.16) return NO;

    BOOL namedVisual = [name containsString:@"material"] || [name containsString:@"effect"] ||
                       [name containsString:@"blur"] || [name containsString:@"fill"] ||
                       [name containsString:@"progress"] || [name containsString:@"background"] ||
                       [name containsString:@"tint"] || [name containsString:@"valueindicator"];
    BOOL largeImageVisual = [view isKindOfClass:UIImageView.class] && ratio >= 0.16;
    BOOL plainLargeVisual = ([name isEqualToString:@"uiview"] || [name containsString:@"visualeffectsubview"]) && ratio >= 0.18 && !MGVolumeSubtreeHasForeground(view);
    return namedVisual || largeImageVisual || plainLargeVisual;
}

static NSUInteger MGApplyBrightnessImageMode(UIView *slider, UIImageView *imageView, NSMutableArray<NSString *> *suppressedClasses) {
    if (!slider || !imageView) return 0;
    NSUInteger count = 0;
    for (UIView *child in slider.subviews) {
        if (child.tag == MGImageTag) continue;
        if (MGBrightnessObscuringVisual(child, slider, imageView)) {
            if (!objc_getAssociatedObject(child, &MGVolumeOriginalAlphaKey)) {
                objc_setAssociatedObject(child, &MGVolumeOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            child.alpha = 0.0;
            [suppressedClasses addObject:NSStringFromClass(child.class) ?: @"UIView"];
            count++;
            continue;
        }
        count += MGApplyBrightnessImageMode(child, imageView, suppressedClasses);
    }
    return count;
}

static void MGRestoreBrightnessLayers(CALayer *layer) {
    if (!layer) return;
    NSNumber *saved = objc_getAssociatedObject(layer, &MGBrightnessOriginalLayerOpacityKey);
    if (saved) {
        layer.opacity = saved.floatValue;
        objc_setAssociatedObject(layer, &MGBrightnessOriginalLayerOpacityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (CALayer *child in layer.sublayers.copy) MGRestoreBrightnessLayers(child);
}

static BOOL MGLayerContainsLayer(CALayer *ancestor, CALayer *candidate) {
    CALayer *cursor = candidate;
    while (cursor) {
        if (cursor == ancestor) return YES;
        cursor = cursor.superlayer;
    }
    return NO;
}

static BOOL MGBrightnessObscuringLayer(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer) {
    if (!layer || !sliderLayer || layer == imageLayer || MGLayerContainsLayer(layer, imageLayer)) return NO;
    if ([layer.name isEqualToString:@"ModuleGlassSliderShell"]) return NO;
    CGRect converted = [layer convertRect:layer.bounds toLayer:sliderLayer];
    CGFloat sliderArea = MAX(1.0, CGRectGetWidth(sliderLayer.bounds) * CGRectGetHeight(sliderLayer.bounds));
    CGFloat area = MAX(0.0, CGRectGetWidth(converted) * CGRectGetHeight(converted));
    CGFloat ratio = area / sliderArea;
    if (ratio < 0.10) return NO;
    NSString *name = NSStringFromClass(layer.class).lowercaseString ?: @"";
    BOOL namedVisual = [name containsString:@"fill"] || [name containsString:@"progress"] ||
                       [name containsString:@"background"] || [name containsString:@"material"] ||
                       [name containsString:@"tint"] || [name containsString:@"backdrop"];
    BOOL leafSolid = layer.sublayers.count == 0 && layer.backgroundColor != NULL && ratio >= 0.16;
    BOOL leafImage = layer.sublayers.count == 0 && layer.contents != nil && ratio >= 0.18;
    return namedVisual || leafSolid || leafImage;
}

static NSUInteger MGApplyBrightnessLayerMode(CALayer *layer, CALayer *sliderLayer, CALayer *imageLayer, NSMutableArray<NSString *> *classes) {
    if (!layer || !sliderLayer || !imageLayer) return 0;
    NSUInteger count = 0;
    for (CALayer *child in layer.sublayers.copy) {
        if (child == imageLayer) continue;
        if (MGBrightnessObscuringLayer(child, sliderLayer, imageLayer)) {
            if (!objc_getAssociatedObject(child, &MGBrightnessOriginalLayerOpacityKey))
                objc_setAssociatedObject(child, &MGBrightnessOriginalLayerOpacityKey, @(child.opacity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            child.opacity = 0.0f;
            [classes addObject:[NSString stringWithFormat:@"layer:%@", NSStringFromClass(child.class) ?: @"CALayer"]];
            count++;
            continue;
        }
        count += MGApplyBrightnessLayerMode(child, sliderLayer, imageLayer, classes);
    }
    return count;
}

static UIColor *MGVolumeColorFromHex(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *hex = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    if ([hex hasPrefix:@"#"]) hex = [hex substringFromIndex:1];
    if (hex.length != 6 && hex.length != 8) return nil;
    unsigned int value = 0;
    if (![[NSScanner scannerWithString:hex] scanHexInt:&value]) return nil;
    CGFloat r, g, b, a = 1.0;
    if (hex.length == 8) {
        r = ((value >> 24) & 0xFF) / 255.0;
        g = ((value >> 16) & 0xFF) / 255.0;
        b = ((value >> 8) & 0xFF) / 255.0;
        a = (value & 0xFF) / 255.0;
    } else {
        r = ((value >> 16) & 0xFF) / 255.0;
        g = ((value >> 8) & 0xFF) / 255.0;
        b = (value & 0xFF) / 255.0;
    }
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

static void MGRestoreVolumeColorPresentation(UIView *root) {
    if (!root) return;
    for (UIView *child in [root.subviews copy]) {
        if (child.tag == MGVolumeIconOverlayTag || child.tag == MGVolumePercentageOverlayTag) {
            if (MGGlobalTransitionQuarantine) child.hidden = YES;
            else [child removeFromSuperview];
            continue;
        }
        MGRestoreVolumeColorPresentation(child);
    }
    if ([root isKindOfClass:UIImageView.class]) {
        NSNumber *savedAlpha = objc_getAssociatedObject(root, &MGVolumeOriginalIconAlphaKey);
        if (savedAlpha) {
            root.alpha = savedAlpha.doubleValue;
            objc_setAssociatedObject(root, &MGVolumeOriginalIconAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(root, &MGVolumeIconOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    if ([root isKindOfClass:UILabel.class]) {
        UILabel *label=(UILabel *)root;
        UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
        if (custom) {
            objc_setAssociatedObject(label, &MGVolumePercentageColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            id originalColor=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey);
            NSAttributedString *originalAttributed=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey);
            if (MGOrigLabelSetTextColor) {
                MGOrigLabelSetTextColor(label, @selector(setTextColor:), [originalColor isKindOfClass:UIColor.class] ? originalColor : nil);
            } else {
                label.textColor=[originalColor isKindOfClass:UIColor.class] ? originalColor : nil;
            }
            if (originalAttributed) {
                if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, @selector(setAttributedText:), originalAttributed);
                else label.attributedText=originalAttributed;
            }
            objc_setAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *savedAlpha=objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAlphaKey);
        if (savedAlpha) {
            label.alpha=savedAlpha.doubleValue;
            objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

static NSInteger MGVolumeIconScore(UIImageView *imageView, UIView *slider) {
    if (!imageView || !slider || imageView.tag == MGImageTag || imageView.tag == MGVolumeIconOverlayTag || !imageView.image || imageView.hidden) return -1;
    CGRect rect = [imageView convertRect:imageView.bounds toView:slider];
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (w < 8.0 || h < 8.0 || w > 64.0 || h > 64.0) return -1;
    CGFloat area = w * h;
    NSInteger score = 1200 - (NSInteger)fabs(area - 576.0);
    CGFloat cy = CGRectGetMidY(rect);
    if (cy > CGRectGetHeight(slider.bounds) * 0.55) score += 1800;
    if (fabs(CGRectGetMidX(rect) - CGRectGetMidX(slider.bounds)) < CGRectGetWidth(slider.bounds) * 0.35) score += 900;
    NSString *names = @"";
    UIView *cursor = imageView;
    for (NSInteger i = 0; i < 5 && cursor; i++, cursor = cursor.superview) {
        names = [names stringByAppendingFormat:@" %@", NSStringFromClass(cursor.class).lowercaseString ?: @""];
    }
    for (NSString *needle in @[@"glyph", @"speaker", @"volume", @"audio", @"icon"]) {
        if ([names containsString:needle]) score += 3500;
    }
    return score;
}

static void MGCollectVolumeIconCandidates(UIView *root, UIView *slider, NSMutableArray<UIImageView *> *out) {
    if (!root) return;
    if ([root isKindOfClass:UIImageView.class] && root.tag != MGImageTag && root.tag != MGVolumeIconOverlayTag) {
        UIImageView *iv=(UIImageView *)root;
        if (MGVolumeIconScore(iv, slider) >= 0) [out addObject:iv];
    }
    for (UIView *child in root.subviews) MGCollectVolumeIconCandidates(child, slider, out);
}

static UIImageView *MGFindVolumeIcon(UIView *slider) {
    if (!slider) return nil;
    NSMutableArray<UIImageView *> *candidates=[NSMutableArray array];
    MGCollectVolumeIconCandidates(slider, slider, candidates);
    UIImageView *best=nil;
    NSInteger bestScore=-1;
    for (UIImageView *candidate in candidates) {
        NSInteger score=MGVolumeIconScore(candidate, slider);
        if (score > bestScore) { best=candidate; bestScore=score; }
    }
    return best;
}

static BOOL MGApplyVolumeIconTint(UIView *slider, UIColor *color, NSString **outClass, CGRect *outFrame) {
    if (!slider || !color) return NO;
    UIImageView *icon=MGFindVolumeIcon(slider);
    if (!icon || !icon.image || !icon.superview) return NO;

    NSNumber *storedAlpha=objc_getAssociatedObject(icon, &MGVolumeOriginalIconAlphaKey);
    CGFloat sourceAlpha=storedAlpha ? storedAlpha.doubleValue : icon.alpha;
    if (!storedAlpha) {
        objc_setAssociatedObject(icon, &MGVolumeOriginalIconAlphaKey, @(icon.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    UIImageView *overlay=[[MGOwnedImageView alloc] initWithFrame:CGRectZero];
    overlay.tag=MGVolumeIconOverlayTag;
    overlay.userInteractionEnabled=NO;
    overlay.backgroundColor=UIColor.clearColor;
    overlay.image=[icon.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    overlay.tintColor=color;
    overlay.contentMode=icon.contentMode;
    overlay.clipsToBounds=icon.clipsToBounds;
    overlay.bounds=icon.bounds;
    overlay.center=icon.center;
    overlay.transform=icon.transform;
    overlay.alpha=sourceAlpha;
    overlay.hidden=icon.hidden;
    overlay.layer.cornerRadius=icon.layer.cornerRadius;
    overlay.layer.masksToBounds=icon.layer.masksToBounds;
    MGRegisterOverlay(overlay,nil,icon.superview);
    [icon.superview insertSubview:overlay aboveSubview:icon];
    objc_setAssociatedObject(icon, &MGVolumeIconOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // Keep Apple's image/state alive but make only the native pixels transparent.
    icon.alpha=0.0;

    if (outClass) *outClass=[NSString stringWithFormat:@"%@+overlay", NSStringFromClass(icon.class) ?: @"UIImageView"];
    if (outFrame) *outFrame=[overlay convertRect:overlay.bounds toView:slider];
    return YES;
}

static NSInteger MGVolumePercentageScore(UILabel *label, UIView *slider) {
    if (!label || !slider || label.tag == MGVolumePercentageOverlayTag || label.hidden) return -1;
    NSString *text = label.text ?: @"";
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return -1;

    CGRect rect = [label convertRect:label.bounds toView:slider];
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (w < 8.0 || h < 8.0 || w > 120.0 || h > 70.0) return -1;

    NSInteger score = 0;
    if ([trimmed containsString:@"%"] ) score += 10000;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789% ."];
    if ([[trimmed stringByTrimmingCharactersInSet:allowed] length] == 0) score += 2500;

    NSString *names = @"";
    UIView *cursor = label;
    for (NSInteger i = 0; i < 5 && cursor; i++, cursor = cursor.superview) {
        names = [names stringByAppendingFormat:@" %@", NSStringFromClass(cursor.class).lowercaseString ?: @""];
    }
    for (NSString *needle in @[@"percentage", @"percent", @"value", @"volume", @"audio", @"slider"]) {
        if ([names containsString:needle]) score += 1200;
    }

    CGFloat midX = CGRectGetMidX(rect);
    if (fabs(midX - CGRectGetMidX(slider.bounds)) < CGRectGetWidth(slider.bounds) * 0.40) score += 700;
    return score;
}

static void MGCollectVolumePercentageCandidates(UIView *root, UIView *slider, NSMutableArray<UILabel *> *out) {
    if (!root) return;
    if ([root isKindOfClass:UILabel.class] && root.tag != MGVolumePercentageOverlayTag) {
        UILabel *label=(UILabel *)root;
        if (MGVolumePercentageScore(label, slider) >= 0) [out addObject:label];
    }
    for (UIView *child in root.subviews) MGCollectVolumePercentageCandidates(child, slider, out);
}

static UILabel *MGFindVolumePercentageLabel(UIView *slider) {
    if (!slider) return nil;
    NSMutableArray<UILabel *> *candidates=[NSMutableArray array];
    MGCollectVolumePercentageCandidates(slider, slider, candidates);
    UILabel *best=nil;
    NSInteger bestScore=-1;
    for (UILabel *candidate in candidates) {
        NSInteger score=MGVolumePercentageScore(candidate, slider);
        if (score > bestScore) { best=candidate; bestScore=score; }
    }
    return bestScore >= 2000 ? best : nil;
}

static NSAttributedString *MGAttributedStringWithColor(NSAttributedString *input, UIColor *color) {
    if (!input || !color || input.length == 0) return input;
    NSMutableAttributedString *result=[input mutableCopy];
    [result addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0, result.length)];
    return result;
}

static void MGLabelSetText(UILabel *label, SEL _cmd, NSString *text) {
    if (MGOrigLabelSetText) MGOrigLabelSetText(label, _cmd, text);
    if (MGGlobalTransitionQuarantine) return;
    UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
    if (custom && MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, @selector(setTextColor:), custom);
}

static void MGLabelSetAttributedText(UILabel *label, SEL _cmd, NSAttributedString *text) {
    if (MGGlobalTransitionQuarantine) {
        if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, _cmd, text);
        return;
    }
    UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
    if (!custom) {
        if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, _cmd, text);
        return;
    }
    if (text) objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey, [text copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSAttributedString *colored=MGAttributedStringWithColor(text, custom);
    if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, _cmd, colored);
}

static void MGLabelSetTextColor(UILabel *label, SEL _cmd, UIColor *color) {
    if (MGGlobalTransitionQuarantine) {
        if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, _cmd, color);
        return;
    }
    UIColor *custom=objc_getAssociatedObject(label, &MGVolumePercentageColorKey);
    if (!custom) {
        if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, _cmd, color);
        return;
    }
    objc_setAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey, color ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, _cmd, custom);
}

static BOOL MGApplyVolumePercentageTint(UIView *slider, UIColor *color, NSString **outClass, CGRect *outFrame, NSString **outText) {
    if (!slider || !color) return NO;
    UILabel *label=MGFindVolumePercentageLabel(slider);
    if (!label) return NO;

    if (!objc_getAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey)) {
        objc_setAssociatedObject(label, &MGVolumeOriginalPercentageTextColorKey, label.textColor ?: (id)NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (label.attributedText.length && !objc_getAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey)) {
        objc_setAssociatedObject(label, &MGVolumeOriginalPercentageAttributedKey, [label.attributedText copy], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(label, &MGVolumePercentageColorKey, color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (label.attributedText.length) {
        NSAttributedString *colored=MGAttributedStringWithColor(label.attributedText, color);
        if (MGOrigLabelSetAttributedText) MGOrigLabelSetAttributedText(label, @selector(setAttributedText:), colored);
        else label.attributedText=colored;
    }
    if (MGOrigLabelSetTextColor) MGOrigLabelSetTextColor(label, @selector(setTextColor:), color);
    else label.textColor=color;

    if (outClass) *outClass=[NSString stringWithFormat:@"%@+live-native", NSStringFromClass(label.class) ?: @"UILabel"];
    if (outFrame) *outFrame=[label convertRect:label.bounds toView:slider];
    if (outText) *outText=label.text ?: label.attributedText.string ?: @"";
    return YES;
}

static void MGRemoveTaggedImages(UIView *root, UIView *except) {
    if (!root) return;
    for (UIView *view in [root.subviews copy]) {
        if (view.tag == MGImageTag && view != except) {
            [view removeFromSuperview];
            continue;
        }
        MGRemoveTaggedImages(view, except);
    }
}

static UIImageView *MGImageViewInParent(UIView *parent) {
    for (UIView *view in parent.subviews) if (view.tag == MGImageTag && [view isKindOfClass:UIImageView.class]) return (UIImageView *)view;
    UIImageView *imageView = [[MGOwnedImageView alloc] initWithFrame:CGRectZero];
    imageView.tag = MGImageTag;
    imageView.userInteractionEnabled = NO;
    imageView.contentMode = UIViewContentModeScaleToFill;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
    return imageView;
}


static void MGRemoveSliderShells(UIView *root) {
    if (!root) return;
    for (UIView *view in root.subviews.copy) {
        if (view.tag == MGSliderShellTag) {
            [view removeFromSuperview];
            continue;
        }
        MGRemoveSliderShells(view);
    }
}

static void MGCopyCornerGeometry(UIImageView *imageView, UIView *source, UIView *fallback) {
    UIView *geometrySource = source ?: fallback;
    CALayer *layer = geometrySource.layer ?: fallback.layer;
    CGFloat radius = layer.cornerRadius;
    if (radius <= 0.0) radius = fallback.layer.cornerRadius;
    imageView.layer.cornerRadius = MAX(0.0, radius);
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = layer.cornerCurve ?: kCACornerCurveContinuous;
    imageView.layer.maskedCorners = layer.maskedCorners ?: kCALayerAllCorners;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
    imageView.layer.mask = nil;
    if ([layer.mask isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)layer.mask).path) {
        CAShapeLayer *sourceMask = (CAShapeLayer *)layer.mask;
        CGRect srcBounds = geometrySource.bounds;
        CGRect dstBounds = imageView.bounds;
        CGFloat sx = CGRectGetWidth(srcBounds) > 0.0 ? CGRectGetWidth(dstBounds) / CGRectGetWidth(srcBounds) : 1.0;
        CGFloat sy = CGRectGetHeight(srcBounds) > 0.0 ? CGRectGetHeight(dstBounds) / CGRectGetHeight(srcBounds) : 1.0;
        CGAffineTransform transform = CGAffineTransformMakeScale(sx, sy);
        CGPathRef scaledPath = CGPathCreateCopyByTransformingPath(sourceMask.path, &transform);
        CAShapeLayer *maskCopy = [CAShapeLayer layer];
        maskCopy.frame = imageView.bounds;
        maskCopy.path = scaledPath;
        maskCopy.fillRule = sourceMask.fillRule;
        imageView.layer.mask = maskCopy;
        if (scaledPath) CGPathRelease(scaledPath);
    } else if (layer.mask) {
        CGSize src = geometrySource.bounds.size;
        CGSize dst = imageView.bounds.size;
        if (fabs(src.width - dst.width) <= 2.0 && fabs(src.height - dst.height) <= 2.0) {
            CALayer *maskCopy = [layer.mask copy];
            maskCopy.frame = imageView.bounds;
            imageView.layer.mask = maskCopy;
        }
    }
}

static NSInteger MGShapeCandidateScore(UIView *candidate, UIView *root, CGRect targetRect) {
    if (!candidate || !root || candidate.tag == MGImageTag || candidate.hidden) return NSIntegerMin;
    CALayer *layer = candidate.layer;
    BOOL hasMask = layer.mask != nil || candidate.maskView != nil;
    BOOL hasRadius = layer.cornerRadius > 1.0;
    if (!hasMask && !hasRadius) return NSIntegerMin;

    CGRect rect = [candidate convertRect:candidate.bounds toView:root];
    CGFloat tw = CGRectGetWidth(targetRect), th = CGRectGetHeight(targetRect);
    CGFloat rw = CGRectGetWidth(rect), rh = CGRectGetHeight(rect);
    if (tw <= 1.0 || th <= 1.0 || rw <= 1.0 || rh <= 1.0) return NSIntegerMin;

    CGFloat widthDiff = fabs(rw - tw);
    CGFloat heightDiff = fabs(rh - th);
    CGFloat centerDiff = hypot(CGRectGetMidX(rect) - CGRectGetMidX(targetRect), CGRectGetMidY(rect) - CGRectGetMidY(targetRect));
    if (widthDiff > 10.0 || heightDiff > 10.0 || centerDiff > 10.0) return NSIntegerMin;

    NSInteger score = 10000;
    score -= (NSInteger)(widthDiff * 100.0 + heightDiff * 100.0 + centerDiff * 80.0);
    if (hasMask) score += 5000;
    if (hasRadius) score += 3000;
    NSString *name = NSStringFromClass(candidate.class).lowercaseString ?: @"";
    if ([name containsString:@"background"] || [name containsString:@"material"] || [name containsString:@"module"] || [name containsString:@"container"]) score += 800;
    return score;
}

static void MGFindMatchingShapeRecursive(UIView *node, UIView *root, CGRect targetRect, UIView **best, NSInteger *bestScore) {
    if (!node || !root) return;
    NSInteger score = MGShapeCandidateScore(node, root, targetRect);
    if (score > *bestScore) {
        *best = node;
        *bestScore = score;
    }
    for (UIView *child in node.subviews) {
        if (child.tag == MGImageTag) continue;
        MGFindMatchingShapeRecursive(child, root, targetRect, best, bestScore);
    }
}

static UIView *MGFindMatchingAppleShape(UIView *native, UIView *root) {
    if (!native || !root) return nil;
    CGRect targetRect = [native convertRect:native.bounds toView:root];
    UIView *best = nil;
    NSInteger bestScore = NSIntegerMin;
    MGFindMatchingShapeRecursive(root, root, targetRect, &best, &bestScore);
    return best;
}

static void MGApplyModuleShapeFallback(UIImageView *imageView, NSString *slot) {
    if (!imageView) return;
    if (imageView.layer.mask || imageView.layer.cornerRadius > 1.0) return;

    CGFloat w = CGRectGetWidth(imageView.bounds);
    CGFloat h = CGRectGetHeight(imageView.bounds);
    CGFloat d = MIN(w, h);
    if (d <= 1.0) return;

    // Brightness and Volume are the same slider family and must share the same
    // pill geometry. Standard compact modules keep Apple's rounded-module shape.
    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    CGFloat radius = sliderSlot ? (d * 0.5) : MIN(32.0, d * 0.285);
    imageView.layer.cornerRadius = radius;
    if (@available(iOS 13.0, *)) imageView.layer.cornerCurve = kCACornerCurveContinuous;
    imageView.clipsToBounds = YES;
    imageView.layer.masksToBounds = YES;
}

static CGFloat MGViewArea(UIView *view) {
    if (!view) return 0.0;
    return MAX(0.0, CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds));
}

static NSInteger MGCompactHostScore(UIView *view, UIView *root, UIView *native) {
    if (!view || !root) return NSIntegerMin;
    CGFloat rootArea = MAX(1.0, MGViewArea(root));
    CGFloat area = MGViewArea(view);
    if (area < 16.0) return NSIntegerMin;
    CGFloat ratio = area / rootArea;
    NSInteger score = 0;
    if (view.layer.mask) score += 7000;
    if (view.clipsToBounds || view.layer.masksToBounds) score += 3000;
    if (view.layer.cornerRadius > 1.0) score += 2400;
    if (ratio >= 0.72 && ratio <= 1.28) score += 2200;
    else if (ratio >= 0.45 && ratio <= 1.45) score += 900;
    else score -= 1200;
    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    if ([name containsString:@"module"] || [name containsString:@"container"]) score += 500;
    if ([name containsString:@"background"] || [name containsString:@"material"]) score += 650;
    if (view == native) score += 350;
    if (view == root) score -= 250;
    return score;
}

static UIView *MGFindCompactClipHost(UIView *native, UIView *root) {
    if (!native || !root) return native ?: root;
    UIView *best = native;
    NSInteger bestScore = MGCompactHostScore(native, root, native);
    UIView *cursor = native.superview;
    NSInteger depth = 0;
    while (cursor && depth++ < 8) {
        NSInteger score = MGCompactHostScore(cursor, root, native);
        if (score > bestScore) { best = cursor; bestScore = score; }
        if (cursor == root) break;
        cursor = cursor.superview;
    }
    return best ?: native;
}

// Select a background that actually belongs to the compact module shell.
// The old first-recursive-match rule could select an inner child button.
static NSInteger MGModuleBackgroundScore(UIView *candidate, UIView *root) {
    if (!candidate || !root || candidate == root || candidate.tag == MGImageTag || candidate.hidden) return NSIntegerMin;
    if (!MGClassNameContains(candidate, @[@"mtmaterialview", @"ccuimodulebackground",
                                          @"contentmodulebackground", @"modulebackground",
                                          @"material", @"background"])) return NSIntegerMin;

    CGRect rect = [candidate convertRect:candidate.bounds toView:root];
    CGFloat rootW = CGRectGetWidth(root.bounds), rootH = CGRectGetHeight(root.bounds);
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (rootW <= 1.0 || rootH <= 1.0 || w <= 1.0 || h <= 1.0) return NSIntegerMin;

    CGFloat rootArea = MAX(1.0, rootW * rootH);
    CGFloat areaRatio = (w * h) / rootArea;
    if (areaRatio < 0.45 || areaRatio > 1.35) return NSIntegerMin;

    CGFloat widthRatio = w / rootW;
    CGFloat heightRatio = h / rootH;
    CGFloat centerDistance = hypot(CGRectGetMidX(rect) - CGRectGetMidX(root.bounds),
                                   CGRectGetMidY(rect) - CGRectGetMidY(root.bounds));
    CGFloat centerLimit = MAX(rootW, rootH) * 0.22;
    if (centerDistance > centerLimit) return NSIntegerMin;

    NSInteger score = 0;
    score += (NSInteger)(areaRatio * 7000.0);
    score -= (NSInteger)(fabs(widthRatio - 1.0) * 3000.0);
    score -= (NSInteger)(fabs(heightRatio - 1.0) * 3000.0);
    score -= (NSInteger)(centerDistance * 35.0);
    if (candidate.layer.mask) score += 900;
    if (candidate.layer.cornerRadius > 1.0) score += 700;
    NSString *name = NSStringFromClass(candidate.class).lowercaseString ?: @"";
    if ([name containsString:@"module"]) score += 900;
    if ([name containsString:@"background"] || [name containsString:@"material"]) score += 500;
    return score;
}

static void MGFindModuleBackgroundRecursive(UIView *node, UIView *root, UIView **best, NSInteger *bestScore, NSInteger depth) {
    if (!node || !root || depth > 24) return;
    NSInteger score = MGModuleBackgroundScore(node, root);
    if (score > *bestScore) {
        *best = node;
        *bestScore = score;
    }
    for (UIView *child in node.subviews) {
        if (child.tag == MGImageTag) continue;
        MGFindModuleBackgroundRecursive(child, root, best, bestScore, depth + 1);
    }
}

static UIView *MGFindModuleSizedBackground(UIView *root) {
    if (!root) return nil;
    UIView *best = nil;
    NSInteger bestScore = NSIntegerMin;
    MGFindModuleBackgroundRecursive(root, root, &best, &bestScore, 0);
    return best;
}

static BOOL MGPrepareInsertion(UIView *root, NSString *slot, UIView **outParent, UIView **outAnchor, CGRect *outFrame, UIView **outCornerSource, NSString **outStrategy) {
    // Slider images must never use Apple's value-dependent fill/background frame.
    // Brightness and Volume now use the full continuous-slider bounds permanently;
    // only our inner image mask changes with the live value.
    BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    if (sliderSlot) {
        // Expansion-isolation mode: never place Module Glass views inside Apple's
        // CCUIContinuousSliderView hierarchy. Host the image beside the module's
        // native outer background and only read the slider value for our own mask.
        UIView *scope = MGFindSliderView(root) ?: root;
        UIView *native = MGFindModuleSizedBackground(root);
        if (native && native.superview) {
            UIView *parent = native.superview;
            if (outParent) *outParent = parent;
            if (outAnchor) *outAnchor = native;
            if (outFrame) *outFrame = [scope convertRect:scope.bounds toView:parent];
            if (outCornerSource) *outCornerSource = scope;
            if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-external-slider-host", slot];
            return YES;
        }
        if (outParent) *outParent = root;
        if (outAnchor) *outAnchor = nil;
        if (outFrame) *outFrame = [scope convertRect:scope.bounds toView:root];
        if (outCornerSource) *outCornerSource = scope;
        if (outStrategy) *outStrategy = [NSString stringWithFormat:@"%@-external-slider-root-fallback", slot];
        return YES;
    }

    // Standard modules use a module-sized shell. The image is directly above
    // Apple's shell background but below Apple's glyph/text/content.
    UIView *native = MGFindModuleSizedBackground(root);
    if (native && native.superview) {
        UIView *matchingShape = MGFindMatchingAppleShape(native, root);
        UIView *geometryHost = matchingShape ?: MGFindCompactClipHost(native, root);
        if (outParent) *outParent = native.superview;
        if (outAnchor) *outAnchor = native;
        if (outFrame) *outFrame = native.frame;
        if (outCornerSource) *outCornerSource = geometryHost ?: native;
        if (outStrategy) *outStrategy = matchingShape ? @"module-sized-native-sibling-apple-shape" : @"module-sized-native-sibling";
        return YES;
    }

    // Safe fallback: stretch to the compact controller bounds at the very back.
    if (outParent) *outParent = root;
    if (outAnchor) *outAnchor = nil;
    if (outFrame) *outFrame = root.bounds;
    if (outCornerSource) *outCornerSource = root;
    if (outStrategy) *outStrategy = @"module-bounds-index0";
    return YES;
}


#pragma mark - Glyph-safe blur removal / slider reveal

static BOOL MGSubtreeContainsForegroundControl(UIView *view, UIImageView *customImage) {
    if (!view) return NO;
    if (view == customImage || view.tag == MGImageTag) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return YES;
    for (UIView *child in view.subviews) if (MGSubtreeContainsForegroundControl(child, customImage)) return YES;
    return NO;
}

static BOOL MGIsModuleSizedBlurVisual(UIView *view, UIView *root, UIImageView *customImage) {
    if (!view || !root || view == root || view == customImage || view.tag == MGImageTag || view.hidden) return NO;
    if ([customImage isDescendantOfView:view] || view.gestureRecognizers.count > 0) return NO;
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIImageView.class] || [view isKindOfClass:UIButton.class]) return NO;
    NSString *name = NSStringFromClass(view.class).lowercaseString ?: @"";
    BOOL visualClass = [name containsString:@"material"] || [name containsString:@"visualeffect"] ||
                       [name containsString:@"backdrop"] || [name containsString:@"blur"] ||
                       [name containsString:@"background"];
    if (!visualClass) return NO;
    CGRect rect = [view convertRect:view.bounds toView:root];
    CGFloat rootW = CGRectGetWidth(root.bounds), rootH = CGRectGetHeight(root.bounds);
    CGFloat w = CGRectGetWidth(rect), h = CGRectGetHeight(rect);
    if (rootW <= 1.0 || rootH <= 1.0 || w <= 1.0 || h <= 1.0) return NO;
    CGFloat areaRatio = (w * h) / MAX(1.0, rootW * rootH);
    CGFloat widthRatio = w / rootW, heightRatio = h / rootH;
    CGFloat centerDistance = hypot(CGRectGetMidX(rect) - CGRectGetMidX(root.bounds), CGRectGetMidY(rect) - CGRectGetMidY(root.bounds));
    if (areaRatio < 0.70 || areaRatio > 1.40 || widthRatio < 0.72 || heightRatio < 0.72) return NO;
    if (centerDistance > MAX(rootW, rootH) * 0.20) return NO;
    return !MGSubtreeContainsForegroundControl(view, customImage);
}

static NSUInteger MGSetModuleBlurHiddenRecursive(UIView *node, UIView *root, UIImageView *customImage,
                                                   BOOL hidden, NSMutableArray<NSString *> *classes, NSInteger depth) {
    if (!node || !root || depth > 24) return 0;
    NSUInteger count = 0;
    for (UIView *child in node.subviews.copy) {
        if (child == customImage || child.tag == MGImageTag) continue;
        if (MGIsModuleSizedBlurVisual(child, root, customImage)) {
            NSNumber *saved = objc_getAssociatedObject(child, &MGBlurOriginalAlphaKey);
            if (hidden) {
                if (!saved) objc_setAssociatedObject(child, &MGBlurOriginalAlphaKey, @(child.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                child.alpha = 0.0;
                if (classes) [classes addObject:NSStringFromClass(child.class) ?: @"UIView"];
            } else if (saved) {
                child.alpha = saved.doubleValue;
                objc_setAssociatedObject(child, &MGBlurOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            count++;
            continue;
        }
        count += MGSetModuleBlurHiddenRecursive(child, root, customImage, hidden, classes, depth + 1);
    }
    return count;
}

static void MGRestoreModuleBlurVisuals(UIView *root) {
    if (!root) return;
    NSNumber *saved = objc_getAssociatedObject(root, &MGBlurOriginalAlphaKey);
    if (saved) {
        root.alpha = saved.doubleValue;
        objc_setAssociatedObject(root, &MGBlurOriginalAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews.copy) MGRestoreModuleBlurVisuals(child);
}

static CGFloat MGSliderNormalizedValue(UIView *slider) {
    if (!slider) return NAN;
    NSNumber *value = nil;
    for (NSString *key in @[@"value", @"_value", @"normalizedValue", @"_normalizedValue"]) {
        @try { id c=[slider valueForKey:key]; if ([c respondsToSelector:@selector(doubleValue)]) { value=c; break; } }
        @catch (__unused NSException *e) {}
    }
    if (!value) return NAN;
    CGFloat v=value.doubleValue, minV=0.0, maxV=1.0;
    @try { id c=[slider valueForKey:@"minimumValue"]; if ([c respondsToSelector:@selector(doubleValue)]) minV=[c doubleValue]; } @catch (__unused NSException *e) {}
    @try { id c=[slider valueForKey:@"maximumValue"]; if ([c respondsToSelector:@selector(doubleValue)]) maxV=[c doubleValue]; } @catch (__unused NSException *e) {}
    if (!isfinite(v)) return NAN;
    if (!isfinite(minV) || !isfinite(maxV) || fabs(maxV-minV)<0.0001) { minV=0.0; maxV=1.0; }
    return MIN(1.0, MAX(0.0, (v-minV)/(maxV-minV)));
}

static void MGClearSliderFillMask(UIImageView *imageView) {
    if (!imageView) return;
    CALayer *mask=objc_getAssociatedObject(imageView, &MGVolumeFillMaskKey);
    if (mask && imageView.layer.mask == mask) imageView.layer.mask=nil;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static CGFloat MGApplySliderFillMask(UIImageView *imageView, UIView *slider) {
    if (!imageView || !slider) return NAN;
    CGFloat value=MGSliderNormalizedValue(slider);
    if (!isfinite(value)) { MGClearSliderFillMask(imageView); return NAN; }
    CGFloat h=CGRectGetHeight(imageView.bounds), w=CGRectGetWidth(imageView.bounds);
    if (w<=1.0 || h<=1.0) return value;

    CGFloat revealH=h*value;
    CGRect fillRect=CGRectMake(0.0, h-revealH, w, revealH);
    CGFloat fillRadius=MIN(w, revealH)*0.5;
    CAShapeLayer *mask=[CAShapeLayer layer];
    mask.frame=imageView.bounds;
    if (revealH <= 0.5) {
        mask.path=[UIBezierPath bezierPath].CGPath;
    } else {
        mask.path=[UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:fillRadius].CGPath;
    }
    mask.fillColor=UIColor.blackColor.CGColor;
    imageView.layer.mask=mask;
    objc_setAssociatedObject(imageView, &MGVolumeFillMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(slider, &MGVolumeFillImageKey, imageView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return value;
}

static void MGSliderSetValue(id self, SEL _cmd, CGFloat value) {
    if (MGOrigSliderSetValue) MGOrigSliderSetValue(self, _cmd, value);
    // Never touch our image mask while Apple is animating an expansion/collapse.
    // Volume can keep receiving value updates from a child controller even when
    // the parent container owns the actual expansion transition.
    if (MGGlobalTransitionQuarantine) return;
    if (![self isKindOfClass:UIView.class]) return;
    UIImageView *imageView=objc_getAssociatedObject(self, &MGVolumeFillImageKey);
    if ([imageView isKindOfClass:MGOwnedImageView.class] && imageView.superview && imageView.window && !imageView.hidden && ((MGOwnedImageView *)imageView).mgExpectedHost==imageView.superview) MGApplySliderFillMask(imageView, (UIView *)self);
}


#pragma mark - Connectivity glyph-only active state

static BOOL MGConnectivityColorLooksBlue(UIColor *color, UITraitCollection *traits) {
    if (!color) return NO;
    if (@available(iOS 13.0, *)) color=[color resolvedColorWithTraitCollection:traits ?: UIScreen.mainScreen.traitCollection];
    CGFloat r=0,g=0,b=0,a=0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return NO;
    return a > 0.10 && b > 0.55 && b > r + 0.22 && b >= g;
}

static BOOL MGConnectivityToggleGeometry(UIView *view, UIView *root) {
    if (!view || !root || view==root) return NO;
    CGRect rect=[view convertRect:view.bounds toView:root];
    CGFloat w=CGRectGetWidth(rect), h=CGRectGetHeight(rect);
    if (w < 28.0 || h < 28.0 || w > 92.0 || h > 92.0) return NO;
    CGFloat aspect=w/MAX(1.0,h);
    if (aspect < 0.72 || aspect > 1.38) return NO;
    CGFloat rootArea=MAX(1.0, CGRectGetWidth(root.bounds)*CGRectGetHeight(root.bounds));
    CGFloat area=(w*h)/rootArea;
    return area > 0.01 && area < 0.28;
}

static NSUInteger MGClearConnectivityActiveBackgroundsRecursive(UIView *node, UIView *root, UIImageView *customImage,
                                                                  NSMutableArray<NSString *> *classes, NSInteger depth) {
    if (!node || !root || depth > 24) return 0;
    NSUInteger count=0;
    for (UIView *child in node.subviews.copy) {
        if (child==customImage || child.tag==MGImageTag) continue;
        if (MGConnectivityToggleGeometry(child, root)) {
            UIColor *viewColor=child.backgroundColor;
            UIColor *layerColor=child.layer.backgroundColor ? [UIColor colorWithCGColor:child.layer.backgroundColor] : nil;
            BOOL blueView=MGConnectivityColorLooksBlue(viewColor, root.traitCollection);
            BOOL blueLayer=MGConnectivityColorLooksBlue(layerColor, root.traitCollection);
            if (blueView || blueLayer) {
                if (blueView && !objc_getAssociatedObject(child, &MGConnectivityOriginalBackgroundColorKey)) {
                    objc_setAssociatedObject(child, &MGConnectivityOriginalBackgroundColorKey, viewColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    child.backgroundColor=UIColor.clearColor;
                }
                if (blueLayer && !objc_getAssociatedObject(child, &MGConnectivityOriginalLayerBackgroundColorKey)) {
                    objc_setAssociatedObject(child, &MGConnectivityOriginalLayerBackgroundColorKey, layerColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    child.layer.backgroundColor=UIColor.clearColor.CGColor;
                }
                if (classes) [classes addObject:NSStringFromClass(child.class) ?: @"UIView"];
                count++;
            }
        }
        count += MGClearConnectivityActiveBackgroundsRecursive(child, root, customImage, classes, depth+1);
    }
    return count;
}

static void MGRestoreConnectivityActiveBackgrounds(UIView *root) {
    if (!root) return;
    UIColor *savedView=objc_getAssociatedObject(root, &MGConnectivityOriginalBackgroundColorKey);
    if (savedView) {
        root.backgroundColor=savedView;
        objc_setAssociatedObject(root, &MGConnectivityOriginalBackgroundColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *savedLayer=objc_getAssociatedObject(root, &MGConnectivityOriginalLayerBackgroundColorKey);
    if (savedLayer) {
        root.layer.backgroundColor=savedLayer.CGColor;
        objc_setAssociatedObject(root, &MGConnectivityOriginalLayerBackgroundColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    for (UIView *child in root.subviews.copy) MGRestoreConnectivityActiveBackgrounds(child);
}

#pragma mark - Apply

static void MGDiagnosticOnce(id controller, NSString *signature, NSString *line) {
    if (!MGVerboseDiagnosticsEnabled()) return;
    NSString *previous = objc_getAssociatedObject(controller, &MGLastDiagnosticKey);
    if ([previous isEqualToString:signature]) return;
    objc_setAssociatedObject(controller, &MGLastDiagnosticKey, signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
    MGLog(@"%@", line);
}

static void MGSetTaggedImagesHiddenRecursive(UIView *root, BOOL hidden) {
    if (!root) return;
    for (UIView *view in root.subviews.copy) {
        if (view.tag == MGImageTag) {
            view.hidden = hidden;
            continue;
        }
        if (view.tag == MGVolumeIconOverlayTag || view.tag == MGVolumePercentageOverlayTag || view.tag == MGSliderShellTag) {
            view.hidden = hidden;
            continue;
        }
        MGSetTaggedImagesHiddenRecursive(view, hidden);
    }
}

static void MGSuspendControllerVisualsNonDestructive(id controller, NSString *source) {
    if (![controller isKindOfClass:UIViewController.class]) return;
    UIView *root=((UIViewController *)controller).viewIfLoaded;
    if (!root) return;

    // CRITICAL: never add/remove UIKit views while Apple's Control Center expansion
    // transition is being prepared or animated. Only restore native presentation
    // properties and hide our already-existing overlays in place.
    MGSetTaggedImagesHiddenRecursive(root, YES);
    UIView *slider = MGFindSliderView(root);
    if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MGRestoreVolumeColorPresentation(root);
    MGRestoreVolumeVisuals(root);
    MGRestoreBrightnessLayers(root.layer);
    MGRestoreModuleBlurVisuals(root);
    MGRestoreConnectivityActiveBackgrounds(root);

    if (MGVerboseDiagnosticsEnabled()) MGLog(@"transition-suspend-nondestructive source=%@ controller=%@ frame=%@",source?:@"<nil>",NSStringFromClass([controller class]),NSStringFromCGRect(root.frame));
}

static void MGQuarantineAllTrackedControllers(NSString *source) {
    NSArray *controllers = nil;
    @synchronized (MGControllers) { controllers = MGControllers.allObjects; }
    for (id controller in controllers) {
        if (!controller || ![controller respondsToSelector:@selector(view)]) continue;
        MGSuspendControllerVisualsNonDestructive(controller, source);
    }
    if (MGVerboseDiagnosticsEnabled()) MGLog(@"transition-global-quarantine source=%@ controllers=%lu generation=%lu", source?:@"<nil>", (unsigned long)controllers.count, (unsigned long)MGGlobalTransitionGeneration);
}

// Only loaded, attached module views participate in recovery. Never load a view
// as a side effect of a transition or a lock-screen notification.
static UIView *MGVisibleRoot(id controller) {
    if (![controller isKindOfClass:UIViewController.class]) return nil;
    UIView *root=((UIViewController *)controller).viewIfLoaded;
    if (!root.window || root.window.hidden || root.window.alpha < 0.01) return nil;
    for (UIView *v=root; v && v!=root.window; v=v.superview) {
        if (v.hidden || v.alpha < 0.01) return nil;
    }
    if (CGRectGetWidth(root.bounds)<=1 || CGRectGetHeight(root.bounds)<=1) return nil;
    return root;
}

static CGRect MGWindowRect(UIView *root) {
    if (!root.window) return CGRectNull;
    CGRect rect=[root convertRect:root.bounds toView:root.window];
    if (!isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
        !isfinite(rect.size.width) || !isfinite(rect.size.height) ||
        rect.size.width<=1 || rect.size.height<=1) return CGRectNull;
    return rect;
}
static BOOL MGRectNear(CGRect a, CGRect b, CGFloat positionTolerance, CGFloat sizeTolerance) {
    if (CGRectIsNull(a) || CGRectIsNull(b)) return NO;
    return fabs(a.size.width-b.size.width)<=sizeTolerance &&
           fabs(a.size.height-b.size.height)<=sizeTolerance &&
           fabs(CGRectGetMidX(a)-CGRectGetMidX(b))<=positionTolerance &&
           fabs(CGRectGetMidY(a)-CGRectGetMidY(b))<=positionTolerance;
}
static BOOL MGGeometryExpanded(id controller, UIView *root) {
    if (!root) return NO;
    if (MGIsExpanded(root)) return YES;
    CGRect rect=MGWindowRect(root);
    if (CGRectIsNull(rect) || MGSizeLooksExpanded(rect.size)) return YES;
    NSValue *baseline=objc_getAssociatedObject(controller,&MGCompactSizeKey);
    NSValue *screenBaseline=objc_getAssociatedObject(controller,&MGCompactScreenSizeKey);
    if (!baseline || !screenBaseline || !CGSizeEqualToSize(screenBaseline.CGSizeValue,UIScreen.mainScreen.bounds.size)) return NO;
    CGSize old=baseline.CGSizeValue, now=root.bounds.size;
    return (now.width>old.width*1.45 && now.width>old.width+28) ||
           (now.height>old.height*1.45 && now.height>old.height+28) ||
           (rect.size.width>old.width*1.45 && rect.size.width>old.width+28) ||
           (rect.size.height>old.height*1.45 && rect.size.height>old.height+28);
}

static BOOL MGNativeExpanded(id controller) {
    // Optional native state, queried only when it has the expected BOOL ABI.
    SEL sel=NSSelectorFromString(@"isExpanded");
    if (![controller respondsToSelector:sel]) return NO;
    NSMethodSignature *sig=[controller methodSignatureForSelector:sel];
    if (!sig || sig.numberOfArguments!=2 || sig.methodReturnLength!=sizeof(BOOL)) return NO;
    const char *t=sig.methodReturnType;
    if (!t || (t[0]!='B' && t[0]!='c')) return NO;
    return ((BOOL (*)(id,SEL))[controller methodForSelector:sel])(controller,sel);
}

static void MGMarkRecovery(id controller) {
    if (!controller) return;
    if (![objc_getAssociatedObject(controller,&MGRecoveryPendingKey) boolValue]) {
        objc_setAssociatedObject(controller,&MGRecoveryPendingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller,&MGRecoveryCandidateRectKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(controller,&MGRecoveryCandidateTimeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        MGHideControllerOverlays(controller);
    }
}
static BOOL MGCompactEligible(id controller, UIView *root, BOOL requireStable) {
    if (!root || MGGeometryExpanded(controller,root)) return NO;
    CGRect rect=MGWindowRect(root);
    if (CGRectIsNull(rect)) return NO;
    CGRect screen=root.window.bounds;
    CGRect visible=CGRectIntersection(rect,screen);
    if (CGRectIsNull(visible) || CGRectIsEmpty(visible)) return NO;
    NSValue *oldRect=objc_getAssociatedObject(controller,&MGCompactRectKey);
    NSValue *oldScreen=objc_getAssociatedObject(controller,&MGCompactScreenSizeKey);
    BOOL sameScreen=oldRect && oldScreen && CGSizeEqualToSize(oldScreen.CGSizeValue,UIScreen.mainScreen.bounds.size);
    BOOL pending=[objc_getAssociatedObject(controller,&MGRecoveryPendingKey) boolValue];
    // The native expanded flag can outlive dismissal. A verified return to the
    // compact rectangle is stronger evidence than that stale boolean.
    BOOL returned=sameScreen && MGRectNear(rect,oldRect.CGRectValue,MAX(22.0,MIN(oldRect.CGRectValue.size.width,oldRect.CGRectValue.size.height)*0.40),MAX(10.0,MIN(oldRect.CGRectValue.size.width,oldRect.CGRectValue.size.height)*0.18));
    if (MGNativeExpanded(controller) && !returned) return NO;
    if (pending && sameScreen && !returned) return NO;
    if (pending && requireStable) {
        NSValue *candidate=objc_getAssociatedObject(controller,&MGRecoveryCandidateRectKey);
        CFTimeInterval now=CACurrentMediaTime();
        if (!candidate || !MGRectNear(rect,candidate.CGRectValue,2,2)) {
            objc_setAssociatedObject(controller,&MGRecoveryCandidateRectKey,[NSValue valueWithCGRect:rect],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(controller,&MGRecoveryCandidateTimeKey,@(now),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return NO;
        }
        if (now-[objc_getAssociatedObject(controller,&MGRecoveryCandidateTimeKey) doubleValue]<0.22) return NO;
    }
    return YES;
}

static void MGApplyControllerNow(id controller, NSString *source) {
    if (MGGlobalTransitionQuarantine) return;
    UIView *root=MGVisibleRoot(controller);
    if (!root) return;
    if (!MGCompactEligible(controller,root,YES)) {
        MGMarkRecovery(controller);
        MGStartRecoverySweep();
        return;
    }
    objc_setAssociatedObject(controller,&MGRecoveryPendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&MGRecoveryCandidateRectKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&MGRecoveryCandidateTimeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&MGCompactRectKey,[NSValue valueWithCGRect:MGWindowRect(root)],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&MGCompactSizeKey,[NSValue valueWithCGSize:root.bounds.size],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(controller,&MGCompactScreenSizeKey,[NSValue valueWithCGSize:UIScreen.mainScreen.bounds.size],OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSArray<NSString *> *candidates = nil;
    NSString *slot = MGSlotForController(controller, &candidates);
    MGRestoreVolumeColorPresentation(root);
    MGRestoreVolumeVisuals(root);
    MGRestoreBrightnessLayers(root.layer);
    MGRestoreModuleBlurVisuals(root);
    MGRestoreConnectivityActiveBackgrounds(root);
    BOOL enabled = MGBoolPreference(@"CCModuleBackgroundsEnabled", YES);
    CGFloat opacity = MIN(1.0, MAX(0.0, MGFloatPreference(@"CCModuleBackgroundOpacity", 1.0)));
    BOOL removeBlur = MGBoolPreference(@"CCModuleRemoveBlur", NO);
    NSString *path = [MGBackgroundDirectory stringByAppendingPathComponent:[slot stringByAppendingString:@".jpg"]];
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:path];

    BOOL volumeIconApplied = NO;
    NSString *volumeIconClass = @"<none>";
    CGRect volumeIconFrame = CGRectZero;
    BOOL volumePercentageApplied = NO;
    NSString *volumePercentageClass = @"<none>";
    CGRect volumePercentageFrame = CGRectZero;
    NSString *volumePercentageText = @"";
    BOOL volumeIconColorEnabled = [slot isEqualToString:@"volume"] && MGBoolPreference(@"CCModuleVolumeIconColorEnabled", NO);
    NSString *volumeIconColorHex = [[MGPreference(@"CCModuleVolumeIconColor") description] copy] ?: @"";
    if (volumeIconColorEnabled) {
        UIView *volumeSlider = MGFindSliderView(root);
        UIColor *volumeColor = MGVolumeColorFromHex(volumeIconColorHex);
        if (volumeSlider && volumeColor) {
            volumeIconApplied = MGApplyVolumeIconTint(volumeSlider, volumeColor, &volumeIconClass, &volumeIconFrame);
            volumePercentageApplied = MGApplyVolumePercentageTint(volumeSlider, volumeColor, &volumePercentageClass, &volumePercentageFrame, &volumePercentageText);
        }
    }

    if (!enabled || !exists) {
        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
        if (sliderSlot) {
            UIView *slider = MGFindSliderView(root);
            if (slider) objc_setAssociatedObject(slider, &MGVolumeFillImageKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            MGRemoveSliderShells(root);
        }
        MGRemoveTaggedImages(root, nil);
        NSString *sig = [NSString stringWithFormat:@"inactive|%@|%d|%d|icon=%d|%@", slot, enabled, exists, volumeIconApplied, volumeIconColorHex];
        MGDiagnosticOnce(controller, sig, [NSString stringWithFormat:@"apply source=%@ controller=%@ slot=%@ enabled=%d exists=%d expanded=0 result=removed volumeIconColorEnabled=%d volumeIconApplied=%d volumeIconColor=%@ volumeIconClass=%@ volumeIconFrame=%@ volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@", source, NSStringFromClass([controller class]), slot, enabled, exists, volumeIconColorEnabled, volumeIconApplied, volumeIconColorHex, volumeIconClass, NSStringFromCGRect(volumeIconFrame), volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText]);
        return;
    }

    UIView *parent = nil, *anchor = nil, *cornerSource = nil;
    CGRect imageFrame = CGRectZero;
    NSString *strategy = nil;
    if (!MGPrepareInsertion(root, slot, &parent, &anchor, &imageFrame, &cornerSource, &strategy) || !parent) return;

    // Never use a host outside the actual compact tile. A stale expanded
    // native background or slider conversion can otherwise paint elsewhere.
    if (parent!=root && ![parent isDescendantOfView:root]) return;
    CGRect tileInParent=[root convertRect:root.bounds toView:parent];
    CGRect clipped=CGRectIntersection(imageFrame,tileInParent);
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped) ||
        !isfinite(clipped.size.width) || !isfinite(clipped.size.height) ||
        clipped.size.width<imageFrame.size.width*0.85 || clipped.size.height<imageFrame.size.height*0.85) {
        MGHideControllerOverlays(controller);
        return;
    }
    imageFrame=clipped;
    UIImageView *imageView = MGImageViewInParent(parent);
    MGRegisterOverlay(imageView,controller,parent);
    // Also remove any tracked previous view reparented outside this root.
    for (UIImageView *old in MGOwnedOverlays.allObjects) {
        if (old==imageView) continue;
        NSHashTable *owners=objc_getAssociatedObject(old,&MGOverlayOwnerKey);
        if ([owners containsObject:controller]) MGDetachOverlay(old);
    }
    MGRemoveTaggedImages(root, imageView);

    if (imageView.superview != parent) [imageView removeFromSuperview];
    if (!imageView.superview) {
        if (anchor && anchor.superview == parent) [parent insertSubview:imageView aboveSubview:anchor];
        else [parent insertSubview:imageView atIndex:0];
    } else if (anchor && anchor.superview == parent &&
               [parent.subviews indexOfObjectIdenticalTo:imageView] < [parent.subviews indexOfObjectIdenticalTo:anchor]) {
        [parent insertSubview:imageView aboveSubview:anchor];
    }

    NSString *loadedPath = objc_getAssociatedObject(imageView, @selector(setImage:));
    if (![loadedPath isEqualToString:path] || !imageView.image) {
        imageView.image = [UIImage imageWithContentsOfFile:path];
        objc_setAssociatedObject(imageView, @selector(setImage:), path, OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    imageView.transform=CGAffineTransformIdentity;
    imageView.autoresizingMask=UIViewAutoresizingNone;
    imageView.frame = imageFrame;
    imageView.alpha = opacity;
    imageView.hidden = imageView.image == nil;
    imageView.userInteractionEnabled = NO;
    MGCopyCornerGeometry(imageView, cornerSource, root);
    MGApplyModuleShapeFallback(imageView, slot);
    BOOL sliderImageSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
    if (!sliderImageSlot) MGClearSliderFillMask(imageView);

    NSUInteger imageFirstSuppressed = 0;
    NSArray<NSString *> *imageFirstSuppressedClasses = @[];
    CGFloat volumeFillValue = NAN;
    NSUInteger blurSuppressed = 0;
    NSArray<NSString *> *blurSuppressedClasses = @[];
    if (imageView.image) {
        BOOL sliderSlot = [slot isEqualToString:@"brightness"] || [slot isEqualToString:@"volume"];
        if (sliderSlot) {
            UIView *imageScope = MGFindSliderView(root) ?: root;
            // Do not mutate any Apple-owned slider view/layer in this build.
            // Our external image receives the live mask; Apple's hierarchy remains native.
            volumeFillValue = MGApplySliderFillMask(imageView, imageScope);
            strategy = [NSString stringWithFormat:@"%@-external-host-live-fill-no-apple-mutation", slot];
        } else {
            strategy = [NSString stringWithFormat:@"%@-glyph-safe-background-only", slot];
        }
        if (removeBlur) {
            NSMutableArray<NSString *> *classes=[NSMutableArray array];
            blurSuppressed = MGSetModuleBlurHiddenRecursive(root, root, imageView, YES, classes, 0);
            blurSuppressedClasses = classes.copy;
            strategy = [strategy stringByAppendingString:@"-crisp"];
        }
        if ([slot isEqualToString:@"connectivity"]) {
            // Expansion-isolation mode: never modify Apple's connectivity toggle
            // backgroundColor/layer.backgroundColor. This intentionally leaves native
            // active-state circles visible for the test so expansion can be isolated.
            strategy = [strategy stringByAppendingString:@"-connectivity-native-toggle-state"];
        }
    }

    // Blur removal only touches module-sized non-interactive material surfaces.
    BOOL glow = MGBoolPreference(@"CCModuleControlGlowEnabled", NO);
    CGFloat glowIntensity = MGFloatPreference(@"CCModuleControlGlowIntensity", 0.0);
    CGFloat glowWidth = MGFloatPreference(@"CCModuleControlGlowWidth", 0.0);

    NSString *sig = [NSString stringWithFormat:@"%@|%@|%d|%d|%.3f|%.0fx%.0f|%@", slot, strategy, enabled, exists, opacity, CGRectGetWidth(root.bounds), CGRectGetHeight(root.bounds), path];
    MGDiagnosticOnce(controller, sig,
                     [NSString stringWithFormat:@"apply source=%@ controller=%@ candidates=%@ slot=%@ path=%@ exists=%d enabled=%d imageLoaded=%d removeBlurPref=%d blurSuppressed=%lu blurClasses=%@ opacity=%.2f expanded=0 strategy=%@ root=%@ frame=%@ parent=%@ nativeBackground=%@ nativeFrame=%@ nativeRadius=%.2f imageFrame=%@ subviews=%lu imageView=%@ imageFirstSuppressed=%lu suppressedClasses=%@ volumeIconColorEnabled=%d volumeIconApplied=%d volumeIconColor=%@ volumeIconClass=%@ volumeIconFrame=%@ volumePercentageApplied=%d volumePercentageClass=%@ volumePercentageFrame=%@ volumePercentageText=%@ volumeFill=%.3f glowPref=%d glowIntensity=%.2f glowWidth=%.2f",
                      source, NSStringFromClass([controller class]), candidates, slot, path, exists, enabled, imageView.image != nil, removeBlur, (unsigned long)blurSuppressed, blurSuppressedClasses, opacity, strategy, NSStringFromClass(root.class), NSStringFromCGRect(root.frame), NSStringFromClass(parent.class), anchor ? NSStringFromClass(anchor.class) : @"<none>", anchor ? NSStringFromCGRect(anchor.frame) : @"<none>", cornerSource.layer.cornerRadius, NSStringFromCGRect(imageView.frame), (unsigned long)parent.subviews.count, imageView, (unsigned long)imageFirstSuppressed, imageFirstSuppressedClasses, volumeIconColorEnabled, volumeIconApplied, volumeIconColorHex, volumeIconClass, NSStringFromCGRect(volumeIconFrame), volumePercentageApplied, volumePercentageClass, NSStringFromCGRect(volumePercentageFrame), volumePercentageText, volumeFillValue, glow, glowIntensity, glowWidth]);
}

static void MGApplyController(id controller, NSString *source) {
    if (!controller || MGGlobalTransitionQuarantine ||
        [objc_getAssociatedObject(controller,&MGApplyInProgressKey) boolValue]) return;
    objc_setAssociatedObject(controller,&MGApplyInProgressKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { MGApplyControllerNow(controller,source); }
    @finally { objc_setAssociatedObject(controller,&MGApplyInProgressKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

static void MGTrackAndApply(id controller, NSString *source) {
    if (!controller) return;
    @synchronized (MGControllers) { [MGControllers addObject:controller]; }
    MGPostLayoutRecovery(controller, source);
}

static void MGRefreshAll(NSString *source, BOOL forceReloadImages) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MGGlobalTransitionQuarantine) {
            MGDeferredImageReload |= forceReloadImages;
            return;
        }
        BOOL reload=forceReloadImages || MGDeferredImageReload;
        MGDeferredImageReload=NO;
        NSArray *controllers = nil;
        @synchronized (MGControllers) { controllers = MGControllers.allObjects; }
        for (id controller in controllers) {
            if (MGGlobalTransitionQuarantine) { MGDeferredImageReload |= reload; break; }
            UIView *root=MGVisibleRoot(controller);
            if (!root) continue;
            if (!MGCompactEligible(controller,root,YES)) {
                MGMarkRecovery(controller);
                MGStartRecoverySweep();
                continue;
            }
            if (reload) MGRemoveTaggedImages(root,nil);
            objc_setAssociatedObject(controller, &MGLastDiagnosticKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
            MGApplyController(controller, source);
        }
        MGLog(@"refresh source=%@ controllers=%lu enabled=%d directoryExists=%d directory=%@", source, (unsigned long)controllers.count, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES), [NSFileManager.defaultManager fileExistsAtPath:MGBackgroundDirectory], MGBackgroundDirectory);
    });
}

#pragma mark - Hooks

static void MGModuleViewDidLoad(id self, SEL _cmd) {
    if (MGOrigModuleViewDidLoad) MGOrigModuleViewDidLoad(self, _cmd);
    MGTrackAndApply(self, @"CCUIModuleContainerViewController.viewDidLoad");
}
static void MGModuleLayout(id self, SEL _cmd) {
    if (MGOrigModuleLayout) MGOrigModuleLayout(self, _cmd);
    MGPostLayoutRecovery(self, @"CCUIModuleContainerViewController.layout");
}
static void MGContentViewDidLoad(id self, SEL _cmd) {
    if (MGOrigContentViewDidLoad) MGOrigContentViewDidLoad(self, _cmd);
    MGTrackAndApply(self, @"CCUIContentModuleContainerViewController.viewDidLoad");
}
static void MGContentLayout(id self, SEL _cmd) {
    if (MGOrigContentLayout) MGOrigContentLayout(self, _cmd);
    MGPostLayoutRecovery(self, @"CCUIContentModuleContainerViewController.layout");
}

// The global gate is bounded. A stale expanded controller must not keep every
// unrelated module blank. Recovery eligibility is checked separately per tile.
static void MGRecoverySweepTick(NSUInteger generation, NSUInteger attempt) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.25*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        if (!MGRecoverySweepActive || generation!=MGRecoverySweepGeneration) return;
        if (MGGlobalTransitionQuarantine) {
            MGRecoverySweepTick(generation,attempt);
            return;
        }
        NSArray *controllers=nil;
        @synchronized (MGControllers) { controllers=MGControllers.allObjects; }
        BOOL pending=NO, anyVisible=NO;
        for (id controller in controllers) {
            UIView *root=MGVisibleRoot(controller);
            if (root) anyVisible=YES;
            if (![objc_getAssociatedObject(controller,&MGRecoveryPendingKey) boolValue]) continue;
            if (!root) continue;
            if (MGCompactEligible(controller,root,YES)) MGApplyController(controller,@"independent-compact-recovery");
            if ([objc_getAssociatedObject(controller,&MGRecoveryPendingKey) boolValue]) pending=YES;
        }
        if (!anyVisible) {
            // CC dismissed. Its next layout will establish new compact baselines.
            for (id controller in controllers) {
                objc_setAssociatedObject(controller,&MGCompactSizeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(controller,&MGCompactRectKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(controller,&MGCompactScreenSizeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                objc_setAssociatedObject(controller,&MGRecoveryCandidateRectKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
        if (pending && attempt<48) MGRecoverySweepTick(generation,attempt+1);
        else MGRecoverySweepActive=NO;
    });
}
static void MGStartRecoverySweep(void) {
    if (MGRecoverySweepActive) return;
    MGRecoverySweepActive=YES;
    MGRecoverySweepTick(++MGRecoverySweepGeneration,0);
}
static void MGStartQuarantine(NSString *source) {
    BOOL wasQuarantined=MGGlobalTransitionQuarantine;
    MGGlobalTransitionQuarantine=YES;
    NSUInteger generation=++MGGlobalTransitionGeneration;
    NSArray *controllers=nil;
    @synchronized (MGControllers) { controllers=MGControllers.allObjects; }
    for (id controller in controllers) MGMarkRecovery(controller);
    if (!wasQuarantined) {
        // BEFORE calling Apple's original transition method: remove only
        // Module Glass-owned image views. No native view is moved or removed.
        // Detached images cannot travel with an expanded module's hierarchy.
        [UIView performWithoutAnimation:^{
            MGQuarantineAllTrackedControllers(source);
            MGDetachAllOwnedOverlays();
        }];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.85*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        if (generation!=MGGlobalTransitionGeneration) return;
        MGGlobalTransitionQuarantine=NO;
        MGStartRecoverySweep();
        MGRefreshAll(@"bounded-transition-recovery",NO);
    });
}

static void MGModuleWillTransition(id self,SEL c,CGSize size,id coordinator) {
    @synchronized (MGControllers) { [MGControllers addObject:self]; }
    MGStartQuarantine(@"module-size-transition");
    if(MGOrigModuleWillTransition) MGOrigModuleWillTransition(self,c,size,coordinator);
}
static void MGContentWillTransition(id self,SEL c,CGSize size,id coordinator) {
    @synchronized (MGControllers) { [MGControllers addObject:self]; }
    MGStartQuarantine(@"content-size-transition");
    if(MGOrigContentWillTransition) MGOrigContentWillTransition(self,c,size,coordinator);
}

static void MGPostLayoutRecovery(id controller, NSString *source) {
    if (!controller) return;
    @synchronized (MGControllers) { [MGControllers addObject:controller]; }
    if (MGGlobalTransitionQuarantine) return;
    UIView *root=MGVisibleRoot(controller);
    if (!root) return;
    if (!MGCompactEligible(controller,root,YES)) {
        MGMarkRecovery(controller);
        MGStartRecoverySweep();
        return;
    }
    // Never mutate a module synchronously inside Apple's layout call stack.
    if ([objc_getAssociatedObject(controller,&MGApplyInProgressKey) boolValue] ||
        [objc_getAssociatedObject(controller,&MGLayoutPendingKey) boolValue]) return;
    objc_setAssociatedObject(controller,&MGLayoutPendingKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak id weakController=controller;
    NSUInteger generation=MGGlobalTransitionGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        id strongController=weakController;
        if (!strongController) return;
        objc_setAssociatedObject(strongController,&MGLayoutPendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (generation!=MGGlobalTransitionGeneration || MGGlobalTransitionQuarantine) return;
        MGApplyController(strongController,source);
    });
}

static void MGLockComplete(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Invalidate queued work and let actual window visibility decide recovery.
        MGStartQuarantine(@"screen-lock");
    });
}

static IMP MGInstallLocalHook(Class cls,SEL sel,IMP hook) {
    if(!cls||!sel||!hook) return NULL;
    Method m=class_getInstanceMethod(cls,sel); if(!m) return NULL;
    IMP original=method_getImplementation(m); const char *types=method_getTypeEncoding(m);
    if(class_addMethod(cls,sel,hook,types)) return original;
    IMP old=NULL; MSHookMessageEx(cls,sel,hook,&old); return old?:original;
}
static void MGHookExpansionTransition(Class cls, IMP transitionHook, IMP *oldTransition) {
    if(!cls) return;
    *oldTransition=MGInstallLocalHook(cls,@selector(viewWillTransitionToSize:withTransitionCoordinator:),transitionHook);
}

static void MGHookController(Class cls, IMP loadHook, IMP layoutHook, IMP *oldLoad, IMP *oldLayout) {
    if (!cls) return;
    SEL loadSel = @selector(viewDidLoad);
    SEL layoutSel = @selector(viewDidLayoutSubviews);
    if (class_getInstanceMethod(cls, loadSel)) *oldLoad=MGInstallLocalHook(cls,loadSel,loadHook);
    if (class_getInstanceMethod(cls, layoutSel)) *oldLayout=MGInstallLocalHook(cls,layoutSel,layoutHook);
}

static void MGPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    MGLoadLicenseState();
    NSString *source = (__bridge NSString *)name ?: @"preferences.changed";
    MGRefreshAll(source, YES);
}

__attribute__((constructor)) static void MGInit(void) {
    @autoreleasepool {
        MGControllers = [NSHashTable weakObjectsHashTable];
        MGOwnedOverlays = [NSHashTable weakObjectsHashTable];
        MGLoadLicenseState();
        void *handle = dlopen("/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI", RTLD_LAZY);
        Class moduleClass = NSClassFromString(@"CCUIModuleContainerViewController");
        Class contentClass = NSClassFromString(@"CCUIContentModuleContainerViewController");
        Class sliderClass = NSClassFromString(@"CCUIContinuousSliderView");

        MGHookController(moduleClass, (IMP)MGModuleViewDidLoad, (IMP)MGModuleLayout, (IMP *)&MGOrigModuleViewDidLoad, (IMP *)&MGOrigModuleLayout);
        MGHookController(contentClass, (IMP)MGContentViewDidLoad, (IMP)MGContentLayout, (IMP *)&MGOrigContentViewDidLoad, (IMP *)&MGOrigContentLayout);
        MGHookExpansionTransition(moduleClass,(IMP)MGModuleWillTransition,(IMP *)&MGOrigModuleWillTransition);
        // Avoid double-hooking an inherited transition method. If the content controller is a
        // subclass of the module controller, the module hook already covers it.
        BOOL contentInheritsModule = moduleClass && contentClass && [contentClass isSubclassOfClass:moduleClass];
        if (!contentInheritsModule) MGHookExpansionTransition(contentClass,(IMP)MGContentWillTransition,(IMP *)&MGOrigContentWillTransition);
        if (sliderClass && class_getInstanceMethod(sliderClass, @selector(setValue:))) {
            MSHookMessageEx(sliderClass, @selector(setValue:), (IMP)MGSliderSetValue, (IMP *)&MGOrigSliderSetValue);
        }

        MSHookMessageEx(UILabel.class, @selector(setText:), (IMP)MGLabelSetText, (IMP *)&MGOrigLabelSetText);
        MSHookMessageEx(UILabel.class, @selector(setAttributedText:), (IMP)MGLabelSetAttributedText, (IMP *)&MGOrigLabelSetAttributedText);
        MSHookMessageEx(UILabel.class, @selector(setTextColor:), (IMP)MGLabelSetTextColor, (IMP *)&MGOrigLabelSetTextColor);

        CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(darwin, NULL, MGLockComplete, CFSTR("com.apple.springboard.lockcomplete"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.unlockvibrate/preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.moduleglass/license.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("preferences.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(darwin, NULL, MGPrefsChanged, CFSTR("com.nextsolution.nextlog/control.changed"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        [NSFileManager.defaultManager createDirectoryAtPath:MGBackgroundDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        MGLog(@"ModuleGlassRuntime 1.1.21 Owned Overlay Recovery loaded SpringBoard=%@ prefsEnabled=%d licenseActive=%d", NSBundle.mainBundle.bundleIdentifier, MGBoolPreference(@"CCModuleBackgroundsEnabled", YES), MGLicenseActiveCached);
        MGLog(@"Glyph-safe stretch runtime with shared Brightness/Volume slider pattern process=%@ pid=%d dlopen=%p moduleClass=%@ contentClass=%@ sliderClass=%@", NSProcessInfo.processInfo.processName, getpid(), handle, moduleClass, contentClass, sliderClass);
        MGLog(@"diagnostic-control active=%d prefsDomain=%@ backgroundDirectory=%@ log=%@", MGVerboseDiagnosticsEnabled(), (__bridge NSString *)MGPrefsDomain, MGBackgroundDirectory, MGLogPath);
    }
}
