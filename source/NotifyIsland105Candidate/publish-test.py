#!/usr/bin/env python3
import datetime, hashlib, json, shutil, sys
from pathlib import Path
repo, deb=map(Path,sys.argv[1:3])
dest=repo/"transfer/files/NotifyIsland/1.0.20"/deb.name
dest.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(deb,dest)
index=repo/"transfer/index.json"
data=json.loads(index.read_text())
id="notify-island-1.0.20-motion-bubbles-roothide"
data["files"]=[x for x in data.get("files",[]) if x.get("id")!=id]
data["files"].insert(0,dict(id=id,name="Notify Island 1.0.20 — Motion Bubbles",fileName=dest.name,type="deb",platform="RootHide / iOS 16+",version="1.0.20",url="https://nextjailbreak.com/"+dest.relative_to(repo).as_posix(),sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),sizeBytes=dest.stat().st_size,notes="Device-test build: motion-driven per-app pending notification bubbles with counts, tap to reopen, and nonblocking Open. Session-only memory, lock-screen privacy, passthrough touch window and optional feature toggle. Preserves 1.0.19 banner fix, gestures and branding. Rollback: 1.0.19."))
data["updatedAt"]=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
index.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
