#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared.h"
@interface NSUPrefsController : PSListController
@property(nonatomic,strong) NSArray *rows;
@property(nonatomic,strong) NSURLSessionDataTask *testTask;
@end
@implementation NSUPrefsController
- (void)notice:(NSString *)title text:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (PSSpecifier *)group:(NSString *)name footer:(NSString *)footer {
    PSSpecifier *p=[PSSpecifier groupSpecifierWithName:name]; if(footer)[p setProperty:footer forKey:@"footerText"]; return p;
}
- (PSSpecifier *)toggle:(NSString *)title key:(NSString *)key {
    PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:title target:self set:@selector(write:specifier:) get:@selector(read:) detail:nil cell:PSSwitchCell edit:nil];
    [p setProperty:key forKey:@"key"];return p;
}
- (PSSpecifier *)button:(NSString *)title action:(SEL)action {
    PSSpecifier *p=[PSSpecifier preferenceSpecifierNamed:title target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil]; p->action=action;return p;
}
- (NSArray *)specifiers {
    if(self.rows)return self.rows;
    NSMutableArray *a=[NSMutableArray arrayWithArray:@[
        [self group:@"Next Summary · 0.1.1" footer:@"Selected message previews are sent to OpenAI when enabled. API use may incur charges."],
        [self toggle:@"Enable AI summaries" key:@"enabled"],
        [self group:@"API connection" footer:@"Your API key is stored in a private mobile preferences file, not in Keychain."],
        [self button:@"Set or replace API key" action:@selector(editKey)],
        [self button:@"Remove API key" action:@selector(removeKey)],
        [self button:@"Choose model" action:@selector(editModel)],
        [self button:@"Test API with sample text" action:@selector(testAPI)],
        [self group:@"Allowed apps" footer:@"All apps are off by default. Do not enable apps containing messages you do not wish to send to OpenAI."]]];
    NSArray *apps=@[@[@"Messenger",@"com.facebook.Messenger"],@[@"WhatsApp",@"net.whatsapp.WhatsApp"],@[@"Messages",@"com.apple.MobileSMS"],@[@"Telegram",@"ph.telegra.Telegraph"],@[@"Mail",@"com.apple.mobilemail"],@[@"Signal",@"org.whispersystems.signal"]];
    for(NSArray *app in apps)[a addObject:[self toggle:app[0] key:[@"app:" stringByAppendingString:app[1]]]];
    [a addObject:[self group:@"Testing" footer:@"Select Messenger, enable, receive a notification. API failure leaves original text visible. Remove tweak and respring if a UI conflict occurs."]];
    self.rows=a; return a;
}
- (id)read:(PSSpecifier *)p {
    NSString *k=[p propertyForKey:@"key"]; NSDictionary *c=NSUConfig();
    if([k hasPrefix:@"app:"])return @([c[@"apps"] containsObject:[k substringFromIndex:4]]);
    return c[k]?:@NO;
}
- (void)write:(id)value specifier:(PSSpecifier *)p {
    NSString *k=[p propertyForKey:@"key"]; NSMutableDictionary *c=[NSUConfig() mutableCopy];
    if([k hasPrefix:@"app:"]){NSMutableArray *apps=[c[@"apps"] mutableCopy]?:[NSMutableArray array]; NSString *app=[k substringFromIndex:4]; [apps removeObject:app]; if([value boolValue])[apps addObject:app]; c[@"apps"]=apps;}
    else c[k]=@([value boolValue]);
    if(!NSUSave(c)) [self notice:@"Not saved" text:@"Could not write preferences."];
}
- (void)edit:(BOOL)secret {
    NSMutableDictionary *c=[NSUConfig() mutableCopy]; NSString *k=secret?@"key":@"model";
    UIAlertController *a=[UIAlertController alertControllerWithTitle:secret?@"OpenAI API key":@"Model" message:secret?@"Enter your own API key. Do not share it in chat.":@"Enter a Chat Completions-compatible model." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f){ f.secureTextEntry=secret; f.autocorrectionType=UITextAutocorrectionTypeNo; f.autocapitalizationType=UITextAutocapitalizationTypeNone; f.text=secret?@"":(c[k]?:@"gpt-4o-mini"); }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){NSString *v=[a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!v.length)return; c[k]=v; if(!NSUSave(c)) dispatch_async(dispatch_get_main_queue(),^{[self notice:@"Not saved" text:@"Could not write preferences."];});}]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)editKey { [self edit:YES]; }
- (void)editModel { [self edit:NO]; }
- (void)removeKey { NSMutableDictionary *c=[NSUConfig() mutableCopy]; [c removeObjectForKey:@"key"]; c[@"enabled"]=@NO; BOOL ok=NSUSave(c); [self reloadSpecifiers]; [self notice:ok?@"Key removed":@"Not saved" text:ok?@"AI summaries are disabled.":@"Could not write preferences."]; }
- (void)testAPI {
    if(self.testTask){[self notice:@"Test running" text:@"An API request is already active."];return;}
    NSDictionary *c=NSUConfig(); if(![c[@"key"] length]){[self notice:@"Missing API key" text:@"Set your API key first."];return;}
    __weak typeof(self) weakSelf=self;
    self.testTask=NSUSummarize(c,@"The delivery scheduled for Thursday has been postponed until Saturday at 4 PM.",^(NSString *s){typeof(self) strongSelf=weakSelf; strongSelf.testTask=nil; [strongSelf notice:s?@"API connected":@"API test failed" text:s?:@"Check the API key, model, billing and internet connection."];});
}
@end
