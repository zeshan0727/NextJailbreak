from pathlib import Path
import plistlib
base=Path('.')
rt=base/'runtime/NotificationGlow.xm'
s=rt.read_text()
def one(a,b):
 global s
 assert s.count(a)==1,a
 s=s.replace(a,b,1)
one('static void UVNGReloadPreferences(void) {','''static BOOL UVNGFloatingEnabled;
static CGFloat UVNGFloatingSize, UVNGFloatingSensitivity, UVNGFloatingBounce, UVNGFloatingGlow;
static CGFloat UVNGFloatingSpeed, UVNGFloatingSmoothness, UVNGFloatingRotation;
static NSInteger UVNGFloatingMotionMode;
static BOOL UVNGFloatingAllApps;
static NSSet<NSString *> *UVNGFloatingSelectedApps;
static BOOL UVNGFloatingAppSelected(NSString *identifier){return identifier.length&&(UVNGFloatingAllApps||[UVNGFloatingSelectedApps containsObject:identifier.lowercaseString]);}
static void UVNGReloadPreferences(void) {''')
one('    UVNGIconSize = UVNGFloat(','''    UVNGFloatingEnabled = UVNGBool(@"NotificationGlowFloatingEnabled", NO);
    UVNGFloatingMotionMode = (NSInteger)UVNGFloat(@"NotificationGlowFloatingMotionMode",0,0,1);
    UVNGFloatingAllApps = UVNGBool(@"NotificationGlowFloatingAllApps", NO);
    id chosen = UVNGCopyPreference(@"NotificationGlowFloatingSelectedApps");
    NSMutableSet *selected=[NSMutableSet new];
    if([chosen isKindOfClass:NSArray.class])for(id item in chosen)if([item isKindOfClass:NSString.class])[selected addObject:[item lowercaseString]];
    UVNGFloatingSelectedApps=[selected copy];
    UVNGFloatingSize = UVNGFloat(@"NotificationGlowFloatingSize", 52, 28, 84);
    UVNGFloatingSensitivity = UVNGFloat(@"NotificationGlowFloatingSensitivity", 1.0, .2, 2.0);
    UVNGFloatingBounce = UVNGFloat(@"NotificationGlowFloatingBounce", .72, .05, .98);
    UVNGFloatingGlow = UVNGFloat(@"NotificationGlowFloatingGlow", .65, 0, 1);
    UVNGFloatingSpeed = UVNGFloat(@"NotificationGlowFloatingSpeed", 1.0, .25, 2.0);
    UVNGFloatingSmoothness = UVNGFloat(@"NotificationGlowFloatingSmoothness", .65, 0, 1);
    UVNGFloatingRotation = UVNGFloat(@"NotificationGlowFloatingRotation", .75, 0, 1.5);
    UVNGIconSize = UVNGFloat(''')
# Source is kept in the same translation unit so the existing helper functions are reused.
one('static void UVNGNotificationObserved(id controller) {','''#include "NGFloating.inc"
static BOOL NGFDispatcherHooked=NO;
static void UVNGNotificationObserved(id controller) {
    if(UVNGFloatingEnabled&&!NGFDispatcherHooked){
        id request=NGFControllerRequest(controller);
        if(request)[[NGFFloatEngine shared] record:request];
    }''')
s=s.replace('if (!UVNGIconAllStyles) UVNGAddIcon(', 'if ((!UVNGFloatingEnabled || !UVNGFloatingAppSelected(identifier) || locked || preview) && !UVNGIconAllStyles) UVNGAddIcon(')
one('if (UVNGIconAllStyles || requestedStyle == 15) UVNGAddIcon(', 'if ((!UVNGFloatingEnabled || !UVNGFloatingAppSelected(identifier) || locked || preview) && (UVNGIconAllStyles || requestedStyle == 15)) UVNGAddIcon(')
one('static void UVNGDarwinCallback(','''%group NGFPost
%hook NCNotificationDispatcher
- (void)postNotificationWithRequest:(id)request {
    %orig;
    if(UVNGFloatingEnabled)NGFOnMain(^{NGFNativeDispatcher=self;[[NGFFloatEngine shared] record:request];});
}
%end
%end
%group NGFAccepted
%hook NCNotificationDispatcher
- (void)_didPostNotificationRequest:(id)request {
    %orig;
    if(UVNGFloatingEnabled)NGFOnMain(^{NGFNativeDispatcher=self;[[NGFFloatEngine shared] record:request];});
}
%end
%end
%group NGFRemoved
%hook NCNotificationDispatcher
- (void)_didRemoveNotificationRequest:(id)request {
    %orig;
    if(UVNGFloatingEnabled)NGFOnMain(^{[[NGFFloatEngine shared] removeRequest:request];});
}
%end
%end
%group NGFClearFrom
%hook NCNotificationDispatcher
- (void)destination:(id)destination requestsClearingNotificationRequests:(id)requests fromDestinations:(id)destinations {
    %orig;
    if(UVNGFloatingEnabled)NGFOnMain(^{[[NGFFloatEngine shared] removeKeys:requests];});
}
%end
%end
%group NGFClear
%hook NCNotificationDispatcher
- (void)destination:(id)destination requestsClearingNotificationRequests:(id)requests {
    %orig;
    NGFOnMain(^{[[NGFFloatEngine shared] removeKeys:requests];});
}
%end
%end
%group NGFWithdraw
%hook NCNotificationDispatcher
- (void)withdrawNotificationWithRequest:(id)request {
    %orig;
    NGFOnMain(^{[[NGFFloatEngine shared] removeRequest:request];});
}
%end
%end
static void UVNGDarwinCallback(''')
one('        UVNGReloadPreferences();\n        if(!UVNGEnabled)', '        UVNGReloadPreferences();\n        [[NGFFloatEngine shared] reload];\n        if(!UVNGEnabled)')
one('    } else if(CFEqual(eventName,UVNGStop)){','''    } else if(CFEqual(eventName,UVNGTestFloating)){
        UVNGReloadPreferences();[[NGFFloatEngine shared] preview];
    } else if(CFEqual(eventName,UVNGStopFloating)){
        [[NGFFloatEngine shared] stopPreview];
    } else if(CFEqual(eventName,UVNGStop)){
        [[NGFFloatEngine shared] clear];''')
one('        %init(UVNGHooks);','''        %init(UVNGHooks);
        Class dispatchClass=NSClassFromString(@"NCNotificationDispatcher");
        if(NGFVoidMethod(dispatchClass,@selector(_didPostNotificationRequest:),3)){
            %init(NGFAccepted); NGFDispatcherHooked=YES;
        }else if(NGFVoidMethod(dispatchClass,@selector(postNotificationWithRequest:),3)){
            %init(NGFPost); NGFDispatcherHooked=YES;
        }
        if(NGFVoidMethod(dispatchClass,@selector(destination:requestsClearingNotificationRequests:),4)){
            %init(NGFClear);
        }
        if(NGFVoidMethod(dispatchClass,@selector(_didRemoveNotificationRequest:),3)){
            %init(NGFRemoved);
        }
        if(NGFVoidMethod(dispatchClass,@selector(destination:requestsClearingNotificationRequests:fromDestinations:),5)){
            %init(NGFClearFrom);
        }
        if(NGFVoidMethod(dispatchClass,@selector(withdrawNotificationWithRequest:),3)){
            %init(NGFWithdraw);
        }
        NSLog(@"[NotifyGlow 1.0.9] Floating engine ready; dispatcher hook=%d",NGFDispatcherHooked);''')
one('            (__bridge NSString *)UVNGStop\n','            (__bridge NSString *)UVNGStop,\n            (__bridge NSString *)UVNGTestFloating,\n            (__bridge NSString *)UVNGStopFloating\n')
s=s.replace('NotifyGlow 1.0.6','NotifyGlow 1.0.9')
rt.write_text(s)
make=base/'runtime/Makefile'
make.write_text(make.read_text().replace('AudioToolbox CoreFoundation','AudioToolbox CoreMotion CoreFoundation'))
prefs=base/'category/prefs'
f=prefs/'Icon.plist'
d=plistlib.loads(f.read_bytes());items=d['items']
def pref(cell,label,key,default,**extra):
 return dict(cell=cell,label=label,key='NotificationGlowFloating'+key,default=default,defaults='com.nextsolution.unlockvibrate',PostNotification='com.nextsolution.unlockvibrate/preferences.changed',get='readPreferenceValue:',set='setPreferenceValue:specifier:',**extra)
def slider(label,key,default,lo,hi):
 return pref('PSSliderCell',label,key,default,min=lo,max=hi,showValue=True)
idx=next(i for i,x in enumerate(items) if x.get('label')=='Position')
items[idx:idx]=[
 dict(cell='PSGroupCell',label='FLOATING ICONS',footerText='Sensor only: icons move in response to device motion and settle when stationary. Continuous drift is optional. Select the apps that may float. Preview uses demo icons.'),
 pref('PSSwitchCell','Floating mode','Enabled',False),
 pref('PSLinkListCell','Motion mode','MotionMode',0,validTitles=['Sensor only','Continuous drift'],validValues=[0,1],detail='PSListItemsController'),
 pref('PSSwitchCell','All apps','AllApps',False),
 dict(cell='PSButtonCell',label='Select floating apps',action='selectFloatingApps:'),

 slider('Floating icon size (pt)','Size',52,28,84),
 slider('Movement sensitivity','Sensitivity',1,.2,2),
 slider('Bouncing intensity','Bounce',.72,.05,.98),
 slider('Floating glow intensity','Glow',.65,0,1),
 slider('Floating speed','Speed',1,.25,2),
 slider('Motion smoothness','Smoothness',.65,0,1),
 slider('Icon rotation speed','Rotation',.75,0,1.5),
 dict(cell='PSButtonCell',label='Test full-screen floating icons',action='test:',event='com.nextsolution.notifyglow/test-floating'),
 dict(cell='PSButtonCell',label='Stop floating preview',action='test:',event='com.nextsolution.notifyglow/stop-floating'),
]
f.write_bytes(plistlib.dumps(d))
controller=prefs/'NGController.m'
c=controller.read_text()
c=c.replace('@interface NGController :', '#include "NGAppPicker.inc"\n@interface NGController :',1)
c=c.replace('- (void)openPage:(PSSpecifier *)s {','- (void)selectFloatingApps:(PSSpecifier *)s {NGFloatingAppsController *picker=[[NGFloatingAppsController alloc]initWithStyle:UITableViewStyleInsetGrouped];[self.navigationController pushViewController:picker animated:YES];}\n- (void)openPage:(PSSpecifier *)s {',1)
assert 'selectFloatingApps:' in c
controller.write_text(c)
# PSSliderCell on iOS 16 ignores the label in the visual cell. Give each
# slider its own native section header, including existing controls on every page.
for page in prefs.glob('*.plist'):
 data=plistlib.loads(page.read_bytes())
 if not isinstance(data,dict) or not isinstance(data.get('items'),list): continue
 labeled=[]
 for item in data['items']:
  if item.get('cell')=='PSSliderCell':
   label=item.get('label') or item.get('key','Adjustment')
   if label.startswith('NotificationGlow'):
    import re
    label=re.sub(r'(?<=[a-z])(?=[A-Z])',' ',label[len('NotificationGlow'):])
   labeled.append(dict(cell='PSGroupCell',label=label))
  labeled.append(item)
 data['items']=labeled
 page.write_bytes(plistlib.dumps(data))
 for i,item in enumerate(labeled):
  if item.get('cell')=='PSSliderCell': assert i>0 and labeled[i-1].get('cell')=='PSGroupCell' and labeled[i-1].get('label'),page.name
for f in [prefs/'Info.plist',prefs/'Root.plist',prefs/'NGController.m',base/'runtime/control',base/'category/control']:
 s=f.read_text().replace('1.0.6','1.0.9')
 if f.name=='control':s=s.replace('1.0.2','1.0.5').replace('1.0.5 animation engine','1.0.9 floating icon animation engine')
 f.write_text(s)
# Original validator sees the new event strings and keys from included source.
v=base/'validate.py'
t=v.read_text().replace("runtime=(base/'runtime/NotificationGlow.xm').read_text();","runtime=(base/'runtime/NotificationGlow.xm').read_text()+(base/'runtime/NGFloating.inc').read_text();").replace('runtime.glow (>= 1.0.2)','runtime.glow (>= 1.0.5)')
v.write_text(t)
assert 'CoreMotion' in make.read_text()
assert 'CAFrameRateRangeMake' in (base/'runtime/NGFloating.inc').read_text()
assert 'canBecomeKeyWindow' in (base/'runtime/NGFloating.inc').read_text()
print('Floating patch applied; existing Glow source and settings retained.')
