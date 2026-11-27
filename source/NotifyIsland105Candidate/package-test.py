#!/usr/bin/env python3
"""Assemble and validate a test package using the verified category layout."""
import hashlib, os, pathlib, plistlib, re, shutil, subprocess, sys
from pathlib import Path
repo, build, temp = map(Path, sys.argv[1:4])
project=repo/"source/NotifyIsland105Candidate"
def run(*args): return subprocess.check_output([str(x) for x in args],text=True).strip()
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def check(condition, msg):
    if not condition: raise SystemExit(msg)
category=repo/"debfiles/NextAura_notification_island_1.0.4_RootHide.deb"
runtime=repo/"debfiles/NextAura_Runtime_island_1.0.0_RootHide.deb"
check(sha(category)=="ca14eb350d923e5635e7687e7ba84bece489d9133d0692b18eb4855db97183e9","Category SHA mismatch")
check(sha(runtime)=="3dfe161ea13b295c84d8ccce5f1ff0e91a40379c1f8e73d5b6256c530a0a6949","Runtime SHA mismatch")
stage=temp/"notify-stage"; old=temp/"notify-old-runtime"
for d in [stage,old]:
    shutil.rmtree(d,ignore_errors=True)
    d.mkdir(parents=True)
run("dpkg-deb","-R",category,stage)
run("dpkg-deb","-R",runtime,old)
libs=stage/"Library/MobileSubstrate/DynamicLibraries"
oldlibs=old/"Library/MobileSubstrate/DynamicLibraries"
expected={"NextAuraNotificationIsland.dylib","NextAuraNotificationIsland.plist"}
runtime_files={str(p.relative_to(old)) for p in old.rglob("*") if (p.is_file() or p.is_symlink()) and "DEBIAN" not in p.relative_to(old).parts}
print("Old runtime payload:",sorted(runtime_files),flush=True)
check(runtime_files=={"Library/MobileSubstrate/DynamicLibraries/"+n for n in expected},"Unexpected runtime payload; refusing self-contained replacement")
libs.mkdir(parents=True,exist_ok=True)
shutil.copy2(build/"NextAuraNotificationIsland.dylib",libs/"NextAuraNotificationIsland.dylib")
shutil.copy2(oldlibs/"NextAuraNotificationIsland.plist",libs/"NextAuraNotificationIsland.plist")
flt=plistlib.load(open(libs/"NextAuraNotificationIsland.plist","rb"))
check(flt["Filter"]["Bundles"]==["com.apple.springboard"],"Unexpected injection filter")
bundle=stage/"Library/PreferenceBundles/NotifyIslandPrefs.bundle"
bundle.mkdir(parents=True)
for p in (project/"prefs/Resources").glob("*.plist"): shutil.copy2(p,bundle/p.name)
shutil.copy2(build/"NotifyIslandPrefs",bundle/"NotifyIslandPrefs")
icon="NextAura-notification-island.png"
shutil.copy2(repo/"icons/nextaura/notification-island.png",bundle/icon)
loader=stage/"Library/PreferenceLoader/Preferences/NextAura-notification-island.plist"
entry=plistlib.load(open(loader,"rb"))["entry"]
entry.update(bundle="NotifyIslandPrefs",detail="NISettingsController",label="Notify Island",icon=icon,isController=True)
entry.pop("plist",None)
plistlib.dump({"entry":entry},open(loader,"wb"))
control=stage/"DEBIAN/control"
fields={
    "Package":"com.nextsolution.nextaura.notification-island",
    "Name":"Notify Island",
    "Version":"1.0.8",
    "Architecture":"iphoneos-arm64e",
    "Description":"Notify Island 1.0.8 Adaptive Actions device-test build. Compact visual controls, double tap dismissal, guarded native notification actions; device validation required.",
    "Maintainer":"Next Jailbreak",
    "Author":"Next Jailbreak",
    "Section":"Tweaks",
    "Depends":"firmware (>= 16.0), preferenceloader, mobilesubstrate",
    "Conflicts":"com.nextsolution.unlockvibrate, com.nextsolution.nextaura.runtime.island",
    "Replaces":"com.nextsolution.nextaura.runtime.island",
    "Provides":"com.nextsolution.nextaura.runtime.island (= 1.0.4)",
    "Priority":"optional",
    "Homepage":"https://nextjailbreak.com/",
    "Icon":"https://nextjailbreak.com/icons/nextaura/notification-island.png",
}
control.write_text("".join(f"{k}: {v}\n" for k,v in fields.items()))
for p in (libs/"NextAuraNotificationIsland.dylib",bundle/"NotifyIslandPrefs"):
    p.chmod(0o755)
    check({"arm64","arm64e"}<=set(run("lipo","-archs",p).split()),"Missing architecture: "+p.name)
    run("ldid","-S",p)
    check(bool(run("ldid","-e",p)) or p.stat().st_size>0,"Signing check failed")
check("/System/Library/PrivateFrameworks/Preferences.framework/Preferences" in run("otool","-L",bundle/"NotifyIslandPrefs"),"Settings framework install-name mismatch")
check("1.0.8 Adaptive Actions loaded" in run("strings","-a",libs/"NextAuraNotificationIsland.dylib"),"Runtime marker missing")
check("NIStudioHeader" in run("strings","-a",bundle/"NotifyIslandPrefs"),"Studio controller missing")
check("NotificationIslandVerticalPosition" in run("strings","-a",libs/"NextAuraNotificationIsland.dylib"),"Position key missing")
check("NotificationIslandAnimationEnabled" in run("strings","-a",libs/"NextAuraNotificationIsland.dylib"),"Animation key missing")
info=plistlib.load(open(bundle/"Info.plist","rb"))
check(info["CFBundleExecutable"]=="NotifyIslandPrefs" and info["NSPrincipalClass"]=="NISettingsController","Bundle metadata mismatch")
root=plistlib.load(open(bundle/"Root.plist","rb"))
check(not any(item.get("cell")=="PSLinkCell" for item in root["items"]),"Root still contains submenus")
keys=[item["key"] for item in root["items"] if "key" in item]
check(len(keys)==len(set(keys)) and "NotificationIslandEnabled" not in keys,"Duplicate or misplaced control")
prefstrings=run("strings","-a",bundle/"NotifyIslandPrefs")
for key in ["NotificationIslandBlurStrength","NotificationIslandBackgroundOpacity","NotificationIslandTextScale","NotificationIslandReplaceStockBanner","NotificationIslandLandscapeEnabled","NotificationIslandCompactWidth","NotificationIslandCompactHeight","NotificationIslandExpandedWidth","NotificationIslandExpandedHeight","NotificationIslandHorizontalOffset","NotificationIslandNativeActions"]:
    check(key in prefstrings,"Missing compact settings key: "+key)
for marker in ["doubleTapDismiss:","nativeActionTapped:","presentLongLookAnimated:completion:","_askDelegateToExecuteAction:withParameters:animated:"]:
    check(marker in run("strings","-a",libs/"NextAuraNotificationIsland.dylib"),"Missing action marker: "+marker)
check("masterChanged:" in run("strings","-a",bundle/"NotifyIslandPrefs"),"Master switch missing")
for p in bundle.glob("*.plist"):
    data=plistlib.load(open(p,"rb"))
    for item in data.get("items",[]):
        if "key" in item: check(item.get("get")=="readPreferenceValue:" and item.get("set")=="setPreferenceValue:specifier:","Missing read/write selectors in "+p.name)
out=build/"NotifyIsland_1.0.8_AdaptiveActions_RootHide.deb"
run("dpkg-deb","--root-owner-group","-Zxz","-b",stage,out)
for k in ["Package","Version","Architecture","Depends","Conflicts","Replaces","Provides"]: check(run("dpkg-deb","-f",out,k)==fields[k],"Control mismatch: "+k)
verify=temp/"notify-verify"; shutil.rmtree(verify,ignore_errors=True)
run("dpkg-deb","-x",out,verify)
check(sha(verify/"Library/MobileSubstrate/DynamicLibraries/NextAuraNotificationIsland.dylib")==sha(libs/"NextAuraNotificationIsland.dylib"),"Runtime copy mismatch")
check(sha(verify/"Library/PreferenceBundles/NotifyIslandPrefs.bundle/NotifyIslandPrefs")==sha(bundle/"NotifyIslandPrefs"),"Settings copy mismatch")
check(not (verify/"Library/PreferenceBundles/AuraPrefs.bundle").exists(),"Shared Settings must not be included")
(build/"PACKAGE-CONTENTS.txt").write_text(run("dpkg-deb","-c",out)+"\n")
(build/"SHA256SUMS.txt").write_text(sha(out)+"  "+out.name+"\n")
print("Validated device-test DEB:",out,sha(out),flush=True)
