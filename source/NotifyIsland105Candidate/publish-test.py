#!/usr/bin/env python3
import datetime, hashlib, json, shutil, sys
from pathlib import Path
repo, deb=map(Path,sys.argv[1:3])
dest=repo/"transfer/files/NotifyIsland/1.0.7"/deb.name
dest.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(deb,dest)
index=repo/"transfer/index.json"
data=json.loads(index.read_text())
id="notify-island-1.0.7-island-integration-roothide"
data["files"]=[x for x in data.get("files",[]) if x.get("id")!=id]
data["files"].insert(0,dict(id=id,name="Notify Island 1.0.7 — Island Integration",fileName=dest.name,type="deb",platform="RootHide / iOS 16+",version="1.0.7",url="https://nextjailbreak.com/"+dest.relative_to(repo).as_posix(),sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),sizeBytes=dest.stat().st_size,notes="Device-test build; single-page Studio settings with master switch on top, aperture-aware docked card and protected text layout. Preserves 1.0.6 delivery and animation. Compile and static checks only; test on iOS 16.0 RootHide. Rollback: reinstall 1.0.6 Visual Studio."))
data["updatedAt"]=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
index.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
