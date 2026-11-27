#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
static CFStringRef const NIDomain = CFSTR("com.nextsolution.unlockvibrate");
static CFStringRef const NIChanged = CFSTR("com.nextsolution.unlockvibrate/preferences.changed");
@interface NISettingsController : PSListController
@end
@implementation NISettingsController
- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return [specifier propertyForKey:@"default"];
    CFPreferencesAppSynchronize(NIDomain);
    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, NIDomain));
    return value ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, NIDomain);
    CFPreferencesAppSynchronize(NIDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), NIChanged, NULL, NULL, true);
}
- (void)testDynamicIslandSuite:(PSSpecifier *)specifier {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.nextsolution.unlockvibrate/test-dynamic-island-suite"), NULL, NULL, true);
}
@end

@interface NISettingsPageController : NISettingsController
@end
@implementation NISettingsPageController
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *page = [[self specifier] propertyForKey:@"NIPage"];
        NSSet *allowed = [NSSet setWithArray:@[@"Appearance",@"Behavior",@"Privacy",@"Landscape",@"Advanced"]];
        if (![allowed containsObject:page]) return @[];
        _specifiers = [self loadSpecifiersFromPlistName:page target:self];
    }
    return _specifiers;
}
@end
