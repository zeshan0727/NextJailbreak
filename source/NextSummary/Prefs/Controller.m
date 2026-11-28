#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Shared.h"
@interface NSUPrefsController : PSListController
@property(nonatomic,strong) NSURLSessionDataTask *testTask;
@end
@implementation NSUPrefsController
- (void)notice:(NSString *)title text:(NSString *)text {
    UIAlertController *a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)p {
    NSString *k=[p propertyForKey:@"key"]; NSDictionary *c=NSUConfig();
    if([k hasPrefix:@"app:"])return @([c[@"apps"] containsObject:[k substringFromIndex:4]]);
    return c[k]?:@NO;
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)p {
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
