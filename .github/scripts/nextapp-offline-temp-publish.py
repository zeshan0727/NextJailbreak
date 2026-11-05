#!/usr/bin/env python3
"""Publish Next App Library Temp as a separate OTA listing and NS Transfer entry.
The existing live installation entry and bundle identifier are not changed.
"""
import hashlib
import json
import os
import pathlib
import plistlib
from datetime import datetime, timezone

BUNDLE = "com.nextsolution.njapps"
NAME = "Next App Library Temp"
VERSION = "1.0.3"
BUILD = "4"
FILENAME = "next-app-library-temp-1.0.3-4.ipa"
URL = f"https://files.nextsolution.cc/apps/ipa/com-nextsolution-njapps/offline-temp-20261105/{FILENAME}"
EXPIRES = "2026-11-12T15:54:41Z"
TRANSFER_PATH = pathlib.Path("transfer/files/NextAppLibrary/offline-temp-1.0.3") / FILENAME

def main():
    original = pathlib.Path(os.environ["RUNNER_TEMP"]) / FILENAME
    assert original.is_file(), "Signed IPA missing"
    digest = hashlib.sha256(original.read_bytes()).hexdigest()
    sz = original.stat().st_size
    apps_file = pathlib.Path("install/apps.json")
    appdata = json.loads(apps_file.read_text())
    existing = [a for a in appdata["apps"] if a["bundleId"] == BUNDLE and a.get("id") == "com-nextsolution-njapps"]
    assert len(existing) == 1, "Existing Next App Library entry missing; abort without altering catalog"
    normal = existing[0]
    icon = normal["icon"]
    item = {
        "id": "com-nextsolution-njapps-offline-temp",
        "name": NAME,
        "version": VERSION,
        "build": BUILD,
        "platform": "iPad (iPhone compatibility app)",
        "minimumOS": "iOS/iPadOS 16.0+",
        "bundleId": BUNDLE,
        "icon": icon,
        "manifest": "/install/com-nextsolution-njapps-offline-temp.plist",
        "available": True,
        "status": "7-day offline iPad test; expires 12 November 2026",
        "downloadURL": URL,
        "sha256": digest,
        "sizeBytes": sz,
        "storage": "Cloudflare R2",
        "signedByNextSigner": True,
        "offlineProfileExpiresAt": EXPIRES,
    }
    appdata["apps"] = [item] + [a for a in appdata["apps"] if a.get("id") != item["id"]]
    appdata["updated"] = datetime.now(timezone.utc).date().isoformat()
    apps_file.write_text(json.dumps(appdata, indent=2, ensure_ascii=False) + "\n")
    absolute_icon = "https://nextjailbreak.com" + icon if icon.startswith("/") else icon
    manifest = {"items": [{
        "assets": [
            {"kind": "software-package", "url": URL},
            {"kind": "display-image", "needs-shine": False, "url": absolute_icon},
            {"kind": "full-size-image", "needs-shine": False, "url": absolute_icon},
        ],
        "metadata": {
            "bundle-identifier": BUNDLE,
            "bundle-version": BUILD,
            "kind": "software",
            "title": NAME,
        },
    }]}
    pathlib.Path("install/com-nextsolution-njapps-offline-temp.plist").write_bytes(
        plistlib.dumps(manifest, sort_keys=False))
    TRANSFER_PATH.parent.mkdir(parents=True, exist_ok=True)
    TRANSFER_PATH.write_bytes(original.read_bytes())
    transfer_file = pathlib.Path("transfer/index.json")
    transfer = json.loads(transfer_file.read_text())
    transfer_item = {
        "id": "next-app-library-temp-offline-1.0.3",
        "name": "Next App Library Temp 1.0.3 - offline signed IPA",
        "fileName": FILENAME,
        "type": "ipa",
        "platform": "iPadOS 26 (iPhone compatibility mode)",
        "version": "1.0.3 (4)",
        "url": "https://nextjailbreak.com/" + str(TRANSFER_PATH),
        "sha256": digest,
        "sizeBytes": sz,
        "notes": "Seven-day offline Ad Hoc profile for one iPad. Expires " + EXPIRES +
                 ". Preserved bundle ID: " + BUNDLE + ". Same bundle ID replaces a previous installation.",
    }
    transfer["files"] = [transfer_item] + [x for x in transfer.get("files", []) if x.get("id") != transfer_item["id"]]
    transfer["updatedAt"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    transfer_file.write_text(json.dumps(transfer, indent=2, ensure_ascii=False) + "\n")
    assert normal in appdata["apps"], "Must preserve existing app listing"
    print("PASS: Prepared separate OTA listing and NS Transfer entry")
    print("Install: https://nextjailbreak.com/install/")
    print("App bundle:", BUNDLE, "| Name:", NAME, "| SHA256:", digest)

if __name__ == "__main__":
    main()
