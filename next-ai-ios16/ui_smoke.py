"""Build and launch the real UIKit screens with inference omitted, for CI layout checks only.
The release build never includes this generated source or stub engine.
"""
from pathlib import Path
import subprocess as sp, json, platform, time, shutil
root=Path('next-ai-ios16');out=Path('ui-smoke');out.mkdir(exist_ok=True);app=out/'NextAI.app';app.mkdir(exist_ok=True)
s=(root/'main.mm').read_text().replace('#include "llama.h"','')
a=s.index(' try {');b=s.index(' dispatch_async(dispatch_get_main_queue(), ^{\n NextAIWorking=NO',a)
s=s[:a]+' failure=@"Inference is unavailable in the UI-only smoke build.";\n'+s[b:]
s=s.replace('self.window.rootViewController=tabs;', 'tabs.selectedIndex=[NSProcessInfo.processInfo.arguments containsObject:@"--create"]?1:([NSProcessInfo.processInfo.arguments containsObject:@"--settings"]?2:0);self.window.rootViewController=tabs;')
(out/'main.mm').write_text(s)
(out/'stub.mm').write_text('#include "photo-engine/NextPhoto.h"\nextern "C" int NextPhotoGenerate(const char*,const char*,const char*,int,int,int,int64_t,const char*,NextPhotoTiming*,NextPhotoProgress,void*,char*,int){return 1;}\n')
sdk=sp.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip();arch=platform.machine()
sp.run(['xcrun','clang++','-std=c++17','-fobjc-arc','-target',f'{arch}-apple-ios16.0-simulator','-isysroot',sdk,'-I',str(root),str(out/'main.mm'),str(root/'PhotoController.mm'),str(root/'SettingsController.mm'),str(out/'stub.mm'),'-framework','UIKit','-framework','Foundation','-framework','Photos','-framework','UniformTypeIdentifiers','-o',str(app/'NextAI')],check=True)
shutil.copy(root/'Info.plist',app/'Info.plist')
sp.run(['/tmp/nextai-ui-assets/bin/python',str(root/'assets/make_icons.py'),str(app)],check=True)
sp.run(['codesign','--force','--sign','-',str(app)],check=True)
devices=json.loads(sp.check_output(['xcrun','simctl','list','devices','available','--json'],text=True))['devices']
phones=[d for group in devices.values() for d in group if 'iPhone' in d['name']]
assert phones,'No iPhone simulator available'
device=next((d for d in phones if 'Pro Max' in d['name']),phones[0]);udid=device['udid']
sp.run(['xcrun','simctl','boot',udid],check=device['state']!='Booted')
sp.run(['xcrun','simctl','bootstatus',udid,'-b'],check=True)
sp.run(['xcrun','simctl','install',udid,str(app)],check=True)
for name,args,style in [('chat-light',[],'light'),('chat-dark',[],'dark'),('create',['--create'],'dark'),('settings',['--settings'],'dark')]:
 sp.run(['xcrun','simctl','ui',udid,'appearance',style],check=True)
 sp.run(['xcrun','simctl','launch','--terminate-running-process',udid,'cc.nextsolution.nextai',*args],check=True)
 time.sleep(3)
 sp.run(['xcrun','simctl','io',udid,'screenshot',str(out/(name+'.png'))],check=True)
print('UI-only simulator screenshots captured; inference was not exercised.')
