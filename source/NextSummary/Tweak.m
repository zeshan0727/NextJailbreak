#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "Shared.h"
static __weak id List;
static NSMutableDictionary *Entries, *Attempted;
static NSHashTable *Previews;
static NSDictionary *Config, *Membership;
static NSUInteger Generation, InFlight;
static BOOL Scheduled;
static const char Mark;
static id Read(id obj, NSString *key) { @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; } }
static NSString *Str(id x) { return [x isKindOfClass:NSString.class]?x:@""; }
static NSString *Key(id r) {
    NSString *section=Str(Read(r,@"sectionIdentifier")), *uid=Str(Read(r,@"notificationIdentifier"));
    return section.length&&uid.length?[NSString stringWithFormat:@"%@|%@",section,uid]:nil;
}
static NSString *Body(id r) { return Str(Read(Read(r,@"content"),@"message")); }
static NSString *Input(id r) {
    NSString *subtitle=Str(Read(Read(r,@"content"),@"subtitle"));
    return subtitle.length ? [NSString stringWithFormat:@"%@\n%@",subtitle,Body(r)] : Body(r);
}
static BOOL Eligible(id r) {
    NSString *app=Str(Read(r,@"sectionIdentifier")), *body=Body(r);
    NSArray *apps=[Config[@"apps"] isKindOfClass:NSArray.class]?Config[@"apps"]:@[];
    if (![Config[@"enabled"] boolValue] || ![apps containsObject:app] || !Str(Config[@"key"]).length || body.length<20 || body.length>1800 || !Key(r)) return NO;
    id critical=Read(r,@"isCriticalAlert");
    if ([critical respondsToSelector:@selector(boolValue)] && [critical boolValue]) return NO;
    NSString *t=Input(r).lowercaseString;
    for(NSString *s in @[@"verification code",@"one-time",@"otp",@"passcode",@"security code",@"authentication code",@"password",@"رمز التحقق"]) if ([t containsString:s]) return NO;
    // Any explicitly selected notification source is eligible, regardless of app vendor.
    return app.length > 0;
}
static NSDictionary *Snapshot(void) {
    id sections=Read(Read(List,@"masterList"),@"notificationSections");
    if (![sections conformsToProtocol:@protocol(NSFastEnumeration)]) return nil;
    NSMutableDictionary *map=[NSMutableDictionary dictionary];
    for(id section in sections) {
        id requests=Read(section,@"allNotificationRequests");
        if (![requests conformsToProtocol:@protocol(NSFastEnumeration)]) return nil;
        for(id r in requests) { NSString *k=Key(r); if(k) map[k]=r; }
    }
    return map;
}
static BOOL IsListPreview(UIView *v) {
    Class cls=NSClassFromString(@"NCNotificationListCell");
    for(UIView *p=v;p;p=p.superview) if (cls && [p isKindOfClass:cls]) return YES;
    return NO;
}
static UILabel *Label(id controller) {
    id v=Read(controller,@"viewForPreview");
    id label=Read(Read(v,@"notificationContentView"),@"secondaryTextElement");
    return [label isKindOfClass:UILabel.class]?label:nil;
}
static void Restore(UILabel *l) {
    NSDictionary *m=objc_getAssociatedObject(l,&Mark);
    if(m && [l.text isEqualToString:m[@"replacement"]]) {
        id original=m[@"original"]; if ([original isKindOfClass:NSAttributedString.class]) l.attributedText=original; else l.text=original;
    }
    if(m) objc_setAssociatedObject(l,&Mark,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void Render(id controller) {
    UILabel *l=Label(controller); if(!l) return;
    id r=Read(controller,@"notificationRequest"); NSString *k=Key(r), *body=Body(r);
    NSDictionary *e=k?Entries[k]:nil; NSString *summary=e[@"summary"];
    UIView *view=Read(controller,@"viewForPreview");
    BOOL allowed=k && [view isKindOfClass:UIView.class] && IsListPreview(view) && !l.hidden && l.alpha>0.01 && view.window && Eligible(r) && summary.length && [e[@"input"] isEqualToString:Input(r)] && Membership[k]!=nil;
    NSDictionary *mark=objc_getAssociatedObject(l,&Mark);
    if (mark && allowed && [mark[@"key"] isEqualToString:k] && [mark[@"summary"] isEqualToString:summary] && [l.text isEqualToString:mark[@"replacement"]]) return;
    Restore(l);
    if(!allowed || !body.length || !l.text.length || [l.text rangeOfString:body].location==NSNotFound) return;
    NSString *newText=[l.text stringByReplacingOccurrencesOfString:body withString:[@"↪ AI · " stringByAppendingString:summary]];
    if ([newText isEqualToString:l.text]) return;
    id original=l.attributedText?:l.text;
    NSDictionary *attrs=l.attributedText.length?[l.attributedText attributesAtIndex:0 effectiveRange:NULL]:@{};
    NSMutableDictionary *style=[attrs mutableCopy];
    UIFont *font=l.font; UIFontDescriptor *descriptor=[font.fontDescriptor fontDescriptorWithSymbolicTraits:font.fontDescriptor.symbolicTraits|UIFontDescriptorTraitItalic];
    if (descriptor) style[NSFontAttributeName]=[UIFont fontWithDescriptor:descriptor size:font.pointSize];
    objc_setAssociatedObject(l,&Mark,@{@"key":k,@"summary":summary,@"replacement":newText,@"original":original},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    l.attributedText=[[NSAttributedString alloc] initWithString:newText attributes:style];
}
static void Refresh(void) { for(id p in Previews.allObjects) Render(p); }
static void Schedule(void);
static void Reconcile(void) {
    NSDictionary *current=Snapshot(); Membership=current;
    for(NSString *k in Entries.allKeys) {
        id r=current[k]; NSDictionary *e=Entries[k];
        if(!r || !Eligible(r) || ![Input(r) isEqualToString:e[@"input"]]) { [e[@"task"] cancel]; [Entries removeObjectForKey:k]; [Attempted removeObjectForKey:k]; }
    }
    if(!current) { [Attempted removeAllObjects]; Refresh(); return; }
    for(NSString *k in Attempted.allKeys) if(!current[k] || ![Attempted[k] isEqualToString:Input(current[k])]) [Attempted removeObjectForKey:k];
    for(NSString *k in current) {
        if(InFlight>=2 || Entries.count>=150) break;
        id r=current[k]; if (!Eligible(r) || Attempted[k]) continue;
        NSString *input=Input(r); Attempted[k]=input;
        NSMutableDictionary *entry=[@{@"input":input} mutableCopy]; Entries[k]=entry; NSUInteger gen=Generation; InFlight++;
        NSURLSessionDataTask *task=NSUSummarize(Config,input,^(NSString *summary){
            if(InFlight) InFlight--;
            [entry removeObjectForKey:@"task"];
            if (gen==Generation && Entries[k]==entry) {
                id live=Snapshot()[k];
                if (summary.length && live && Eligible(live) && [Input(live) isEqualToString:input]) entry[@"summary"]=summary;
                else [Entries removeObjectForKey:k];
            }
            Refresh(); Schedule();
        });
        if(task) entry[@"task"]=task;
    }
    Refresh();
}
static void Schedule(void) {
    if(!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ Schedule(); }); return; }
    if(Scheduled) return; Scheduled=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ Scheduled=NO; Reconcile(); });
}
static void Reload(void) {
    Generation++; for (NSDictionary *e in Entries.allValues) [e[@"task"] cancel];
    [Entries removeAllObjects]; [Attempted removeAllObjects]; Config=NSUConfig(); Refresh(); Schedule();
}
static void Changed(CFNotificationCenterRef c,void *o,CFStringRef n,const void *obj,CFDictionaryRef u) { dispatch_async(dispatch_get_main_queue(),^{Reload();}); }
static void (*OrigInsert)(id,SEL,id),(*OrigRemove)(id,SEL,id),(*OrigLayout)(id,SEL),(*OrigListLayout)(id,SEL);
static void Insert(id self,SEL cmd,id r) { OrigInsert(self,cmd,r); if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{List=self;Schedule();});return;} List=self; Schedule(); }
static void Remove(id self,SEL cmd,id r) { OrigRemove(self,cmd,r); if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{List=self;Schedule();});return;} List=self; NSString *k=Key(r); if(k){ [Entries[k][@"task"] cancel]; [Entries removeObjectForKey:k]; [Attempted removeObjectForKey:k]; } Membership=Snapshot(); Refresh(); Schedule(); }
static void ListLayout(id self,SEL cmd) { OrigListLayout(self,cmd); if(NSThread.isMainThread && List!=self){List=self;Schedule();} }
static void Layout(id self,SEL cmd) { OrigLayout(self,cmd); if(!NSThread.isMainThread) return; [Previews addObject:self]; Render(self); }
static BOOL Hook(Class c, SEL s, IMP imp, IMP *orig, unsigned args) {
    Method m=c?class_getInstanceMethod(c,s):NULL; if(!m || method_getNumberOfArguments(m)!=args) return NO;
    char type[8]={0}; method_getReturnType(m,type,sizeof(type)); if(type[0]!='v') return NO;
    if(args==3){method_getArgumentType(m,2,type,sizeof(type)); if(type[0]!='@') return NO;}
    MSHookMessageEx(c,s,imp,orig);return YES;
}
__attribute__((constructor)) static void Start(void) {
    @autoreleasepool {
        if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"])return;
        Entries=[NSMutableDictionary new]; Attempted=[NSMutableDictionary new]; Previews=[NSHashTable weakObjectsHashTable]; Config=NSUConfig();
        Class list=NSClassFromString(@"NCNotificationStructuredListViewController"), preview=NSClassFromString(@"NCNotificationShortLookViewController");
        if(!list || !preview) return;
        Hook(list,@selector(insertNotificationRequest:),(IMP)Insert,(IMP*)&OrigInsert,3);
        Hook(list,@selector(removeNotificationRequest:),(IMP)Remove,(IMP*)&OrigRemove,3);
        Hook(list,@selector(viewDidLayoutSubviews),(IMP)ListLayout,(IMP*)&OrigListLayout,2);
        Hook(preview,@selector(viewDidLayoutSubviews),(IMP)Layout,(IMP*)&OrigLayout,2);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,Changed,(__bridge CFStringRef)NSUChanged,NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
