#!/usr/bin/env python3
import datetime, hashlib, json, shutil, sys
from pathlib import Path
repo, deb=map(Path,sys.argv[1:3])
dest=repo/"transfer/files/NotifyIsland/1.0.13"/deb.name
dest.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(deb,dest)
index=repo/"transfer/index.json"
data=json.loads(index.read_text())
id="notify-island-1.0.13-reply-visibility-roothide"
data["files"]=[x for x in data.get("files",[]) if x.get("id")!=id]
data["files"].insert(0,dict(id=id,name="Notify Island 1.0.13 — Reply Visibility",fileName=dest.name,type="deb",platform="RootHide / iOS 16+",version="1.0.13",url="https://nextjailbreak.com/"+dest.relative_to(repo).as_posix(),sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),sizeBytes=dest.stat().st_size,notes="Device-test build; app icon aligns with app name and time in compact/expanded headers; explicit high-contrast reply text and live draft mirror of the actual input buffer. Preserves keyboard and original-request Send action, Full Cover shape, settings and shuffle. Compile/static checks only; verify on iOS 16.0. Rollback: reinstall 1.0.12 Full Cover Plus."))
data["updatedAt"]=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
index.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
