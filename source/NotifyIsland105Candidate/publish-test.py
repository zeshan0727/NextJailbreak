#!/usr/bin/env python3
import datetime, hashlib, json, shutil, sys
from pathlib import Path
repo, deb=map(Path,sys.argv[1:3])
dest=repo/"transfer/files/NotifyIsland/1.0.12"/deb.name
dest.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(deb,dest)
index=repo/"transfer/index.json"
data=json.loads(index.read_text())
id="notify-island-1.0.12-full-cover-plus-roothide"
data["files"]=[x for x in data.get("files",[]) if x.get("id")!=id]
data["files"].insert(0,dict(id=id,name="Notify Island 1.0.12 — Full Cover Plus",fileName=dest.name,type="deb",platform="RootHide / iOS 16+",version="1.0.12",url="https://nextjailbreak.com/"+dest.relative_to(repo).as_posix(),sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),sizeBytes=dest.stat().st_size,notes="Device-test build; corrected Full Cover shape uses a single full-width rounded rectangle without a narrow top or shoulders, automatically selects Island position and includes matching preview. Retains dedicated keyboard composer, prior styles, rounding and shuffle. Compile/static checks only; verify on iOS 16.0. Rollback: reinstall 1.0.9 Inline Actions or 1.0.10 if available."))
data["updatedAt"]=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00","Z")
index.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
