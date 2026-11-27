#!/usr/bin/env python3
"""Promote the exact approved 1.0.18 package payload; change control metadata only."""
import hashlib, subprocess, shutil, sys
from pathlib import Path
approved, icon, output = map(Path,sys.argv[1:4])
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def run(*a): return subprocess.check_output([str(x) for x in a],text=True).strip()
def check(ok,msg):
    if not ok: raise SystemExit(msg)
check(sha(approved)=="b1ac910cb291a6596be1e8eb649b15821e650f85106ab8871761133083877f7f","Approved package SHA256 mismatch")
output.mkdir(parents=True,exist_ok=True)
stage=output/"stage"; verify=output/"verify"
for p in (stage,verify):
    shutil.rmtree(p,ignore_errors=True); p.mkdir()
run("dpkg-deb","-R",approved,stage)
def payload(root):
    result={}
    for p in root.rglob("*"):
        rel=p.relative_to(root)
        if rel.parts[0]=="DEBIAN": continue
        if p.is_symlink(): result[str(rel)]=("link",str(p.readlink()))
        elif p.is_file(): result[str(rel)]=("file",sha(p),p.stat().st_mode&0o777)
    return result
before=payload(stage)
control=stage/"DEBIAN/control"
fields=dict(line.split(": ",1) for line in control.read_text().splitlines() if ": " in line and not line.startswith(" "))
check(fields["Package"]=="com.nextsolution.nextaura.notification-island" and fields["Version"]=="1.0.18" and fields["Architecture"]=="iphoneos-arm64e","Wrong approved package")
fields.update({"Name":"Notify Island","Maintainer":"Next Jailbreak","Author":"Next Jailbreak","Description":"Custom Dynamic Island notifications with five shapes, separate Compact and Expanded controls, swipe-down dismissal in compact view, live replies for supported app actions and adjustable appearance. By Next Jailbreak.","Homepage":"https://nextjailbreak.com/","Icon":"https://nextjailbreak.com/icons/notify-island.png","Depiction":"https://nextjailbreak.com/depictions/notify-island.html","Sileodepiction":"https://nextjailbreak.com/depictions/notify-island.json","Tag":"role::cydia"})
fields["Installed-Size"]=str(sum((p.stat().st_size+1023)//1024 for p in stage.rglob("*") if p.is_file() and p.relative_to(stage).parts[0]!="DEBIAN"))
control.write_text("".join(f"{k}: {v}\n" for k,v in fields.items()))
deb=output/"NotifyIsland_1.0.18_RootHide.deb"
run("dpkg-deb","--root-owner-group","-Zxz","-b",stage,deb)
run("dpkg-deb","-R",deb,verify)
check(payload(verify)==before,"Approved payload changed")
for k in ("Package","Version","Architecture","Maintainer","Depends","Conflicts","Provides","Replaces","Depiction","Sileodepiction"):
    check(run("dpkg-deb","-f",deb,k)==fields[k],"Control mismatch "+k)
for p in (stage,verify): shutil.rmtree(p)
shutil.copy2(icon,output/"notify-island.png")
print("Approved payload unchanged; public package SHA256:",sha(deb))
