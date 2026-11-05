#!/usr/bin/env python3
"""Publish a separate 8 Ball Pool Temp seven-day IPA entry, OTA manifest, and NS Transfer listing.
Preserves the previous 8 Ball Pool entry and its original download.
"""
import hashlib
import html
import json
import os
import pathlib
import plistlib
import urllib.parse
from datetime import datetime, timezone

BUNDLE = "com.nextsolution.8ballpoolmult36"
NAME = "8 Ball Pool Temp"
VERSION = "56.31.0"
BUILD = "5330"
FILENAME = "8-ball-pool-temp-7-days-56.31.0-5330.ipa"
R2_BASE = "https://files.nextsolution.cc/apps/ipa/com-nextsolution-8ballpoolmult36/offline-temp-20261105"
URL = R2_BASE + "/" + FILENAME
EXPIRES = "2026-11-12T15:54:41Z"
TEMP_ID = "com-nextsolution-8ballpoolmult36-offline-temp"
ORIGINAL_ID = "com-nextsolution-8ballpoolmult36"
MANIFEST_PATH = pathlib.Path("install/com-nextsolution-8ballpoolmult36-offline-temp.plist")

def main():
    original = pathlib.Path(os.environ["RUNNER_TEMP"]) / FILENAME
    assert original.is_file(), "Signed 8 Ball Pool IPA missing"
    digest = hashlib.sha256(original.read_bytes()).hexdigest()
    size = original.stat().st_size

    apps_file = pathlib.Path("install/apps.json")
    data = json.loads(apps_file.read_text())
    matches = [a for a in data["apps"] if a.get("id") == ORIGINAL_ID and a.get("bundleId") == BUNDLE]
    assert len(matches) == 1, "Existing 8 Ball Pool record missing"
    regular = matches[0]
    assert regular["version"] == VERSION and str(regular["build"]) == BUILD, "Original version changed"
    icon = regular["icon"]
    temp = {
        "id": TEMP_ID,
        "name": NAME,
        "version": VERSION,
        "build": BUILD,
        "platform": "iPad (iPhone compatibility app)",
        "minimumOS": regular["minimumOS"],
        "bundleId": BUNDLE,
        "icon": icon,
        "manifest": "/" + str(MANIFEST_PATH),
        "available": True,
        "status": "7-day offline Ad Hoc test; registered iPad only; expires 12 November 2026",
        "downloadURL": URL,
        "sha256": digest,
        "sizeBytes": size,
        "storage": "Cloudflare R2",
        "signedByNextSigner": True,
        "offlineProfileExpiresAt": EXPIRES,
    }
    data["apps"] = [temp] + [a for a in data["apps"] if a.get("id") != TEMP_ID]
    assert regular in data["apps"], "Original 8 Ball Pool record must be preserved"
    data["updated"] = datetime.now(timezone.utc).date().isoformat()
    apps_file.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")

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
    MANIFEST_PATH.write_bytes(plistlib.dumps(manifest, sort_keys=False))

    transfer_file = pathlib.Path("transfer/index.json")
    transfer = json.loads(transfer_file.read_text())
    transfer_item = {
        "id": "8ballpool-temp-offline-56.31.0",
        "name": NAME + " 56.31.0 - offline-signed iPad IPA",
        "fileName": FILENAME,
        "type": "ipa",
        "platform": "iPadOS 26 (iPhone compatibility mode)",
        "version": VERSION + " (" + BUILD + ")",
        "url": URL,
        "sha256": digest,
        "sizeBytes": size,
        "notes": "Signed with seven-day offline Ad Hoc profile for one registered iPad. Expires " + EXPIRES
                 + ". Bundle ID: " + BUNDLE + ". Does not run on unregistered devices.",
    }
    transfer["files"] = [transfer_item] + [
        x for x in transfer.get("files", []) if x.get("id") != transfer_item["id"]
    ]
    transfer["updatedAt"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    transfer_file.write_text(json.dumps(transfer, indent=2, ensure_ascii=False) + "\n")

    manifest_uri = R2_BASE + "/manifest.plist"
    ota_url = "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_uri, safe="")
    page = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>8 Ball Pool Temp - iPad Install</title>
<style>
body{margin:0;background:#f6f7f9;color:#101828;font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;display:grid;place-items:center;min-height:100vh}
main{width:min(410px,calc(100% - 48px));padding:28px;background:#fff;border:1px solid #e4e7ec;border-radius:20px;box-shadow:0 12px 35px #10182816;text-align:center}
h1{margin:0 0 10px;font-size:24px}p{line-height:1.6;color:#667085}
a.button{display:block;padding:16px;background:#182230;color:white;border-radius:12px;text-decoration:none;font-weight:700;margin-top:22px}
small{display:block;color:#667085;margin-top:18px;line-height:1.6}
</style></head><body><main><h1>8 Ball Pool Temp</h1>
<p>Version 56.31.0 (5330) | Seven-day offline Ad Hoc test</p>
<a class="button" href="__INSTALL_URL__">Install on registered iPad</a>
<small>Profile expires 12 November 2026 at 18:54 Qatar time.<br>
The temporary version uses the original bundle ID and replaces any installed copy of that app.</small>
</main></body></html>""".replace("__INSTALL_URL__", html.escape(ota_url, quote=True))
    (pathlib.Path(os.environ["RUNNER_TEMP"]) / "8ball-temp-install.html").write_text(page)
    print("PASS: Created separate 8 Ball Pool Temp listing, NS Transfer entry, OTA manifest, and installer")
    print("SHA256:", digest, "size:", size, "offline expiry:", EXPIRES)

if __name__ == "__main__":
    main()
