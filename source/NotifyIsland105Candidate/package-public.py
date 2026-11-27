#!/usr/bin/env python3
"""Repackage the user-approved 1.0.16 RootHide runtime without recompiling it."""
import hashlib, pathlib, plistlib, shutil, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw
approved, prefs, brand, old_icon, output = map(Path, sys.argv[1:6])
output.mkdir(parents=True, exist_ok=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(*args): return subprocess.check_output([str(x) for x in args], text=True).strip()
def check(ok,msg):
    if not ok: raise SystemExit(msg)
check(sha(approved)=="36dcdcaee57ab9600fbf5ac08591204fbbdb7361c415537bb68adb8df9b5ee82","Approved package checksum mismatch")
stage=output/"stage"; verify=output/"verify"
for path in [stage,verify]:
    shutil.rmtree(path,ignore_errors=True)
    path.mkdir()
run("dpkg-deb","-R",approved,stage)
lib=Path("Library/MobileSubstrate/DynamicLibraries/NextAuraNotificationIsland.dylib")
bundle=Path("Library/PreferenceBundles/NotifyIslandPrefs.bundle")
runtime_hash=sha(stage/lib)
# Only user-facing Preferences binary and its icon change.
check({"arm64","arm64e"}<=set(run("lipo","-archs",prefs).split()),"Preferences slices missing")
check("BY NEXT JAILBREAK" in run("strings","-a",prefs),"Brand marker missing")
check("Version 1.0.17 - RootHide" in run("strings","-a",prefs),"Release marker missing")
check("/System/Library/PrivateFrameworks/Preferences.framework/Preferences" in run("otool","-L",prefs),"Preferences linkage mismatch")
shutil.copy2(prefs,stage/bundle/"NotifyIslandPrefs")
(stage/bundle/"NotifyIslandPrefs").chmod(0o755)
run("ldid","-S",stage/bundle/"NotifyIslandPrefs")
# Retain product identity; add the site's genuine logo as a small publisher badge.
im=Image.open(old_icon).convert("RGBA").resize((256,256),Image.Resampling.LANCZOS)
logo=Image.open(brand).convert("RGBA").resize((84,84),Image.Resampling.LANCZOS)
mask=Image.new("L",(84,84),0); ImageDraw.Draw(mask).ellipse((0,0,83,83),fill=255)
logo.putalpha(mask)
draw=ImageDraw.Draw(im); draw.ellipse((164,164,256,256),fill=(9,15,23,255),outline=(76,220,207,255),width=3)
im.alpha_composite(logo,(168,168))
im.save(output/"notify-island.png",optimize=True)
im.resize((64,64),Image.Resampling.LANCZOS).save(stage/bundle/"NextAura-notification-island.png",optimize=True)
control=stage/"DEBIAN/control"
fields={}
for line in control.read_text().splitlines():
    if ": " in line and not line.startswith(" "):
        k,v=line.split(": ",1); fields[k]=v
check(fields["Package"]=="com.nextsolution.nextaura.notification-island","Package identifier mismatch")
check(fields["Architecture"]=="iphoneos-arm64e","Architecture mismatch")
check(fields["Version"]=="1.0.16","Unexpected base version")
fields.update({"Name":"Notify Island","Version":"1.0.17","Maintainer":"Next Jailbreak","Author":"Next Jailbreak","Homepage":"https://nextjailbreak.com/","Description":"Custom Dynamic Island notifications with five shapes, independent Compact and Expanded controls, live replies for supported app actions, adjustable appearance and randomized previews. By Next Jailbreak.","Icon":"https://nextjailbreak.com/icons/notify-island.png","Depiction":"https://nextjailbreak.com/depictions/notify-island.html","Sileodepiction":"https://nextjailbreak.com/depictions/notify-island.json","Tag":"role::cydia"})
fields["Installed-Size"]=str(sum((p.stat().st_size+1023)//1024 for p in stage.rglob("*") if p.is_file() and "DEBIAN" not in p.relative_to(stage).parts))
control.write_text("".join(f"{k}: {v}\n" for k,v in fields.items()))
# Refresh any old md5sums after branding changes.
if (stage/"DEBIAN/md5sums").exists():
    (stage/"DEBIAN/md5sums").write_text("".join(f"{hashlib.md5(p.read_bytes()).hexdigest()}  {p.relative_to(stage).as_posix()}\n" for p in sorted(stage.rglob("*")) if p.is_file() and not p.is_symlink() and "DEBIAN" not in p.relative_to(stage).parts))
deb=output/"NotifyIsland_1.0.17_RootHide.deb"
run("dpkg-deb","--root-owner-group","-Zxz","-b",stage,deb)
run("dpkg-deb","-R",deb,verify)
check(sha(verify/lib)==runtime_hash,"Approved runtime bytes changed")
check(plistlib.load(open(verify/lib.with_suffix(".plist"),"rb"))["Filter"]["Bundles"]==["com.apple.springboard"],"Injection filter mismatch")
for k in ("Package","Version","Architecture","Depends","Conflicts","Replaces","Provides","Maintainer","Author","Depiction","Sileodepiction"):
    check(run("dpkg-deb","-f",deb,k)==fields[k],"Package field mismatch "+k)
check(sha(verify/bundle/"NotifyIslandPrefs")==sha(stage/bundle/"NotifyIslandPrefs"),"Preferences mismatch")
check("test" not in fields["Description"].lower(),"Test description")
print("Validated public release",deb,sha(deb),"unchanged approved runtime",runtime_hash)
(output/"SHA256SUMS.txt").write_text(sha(deb)+"  "+deb.name+"\n")
shutil.rmtree(stage); shutil.rmtree(verify)
