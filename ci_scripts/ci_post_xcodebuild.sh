#!/bin/zsh
set -euo pipefail
[[ "$(printenv CI_XCODEBUILD_ACTION || true)" == "archive" ]] || exit 0
[[ "$(printenv CI_XCODEBUILD_EXIT_CODE || true)" == "0" ]] || exit 0
ARCHIVE="$(printenv CI_ARCHIVE_PATH || true)"
[[ -n "$ARCHIVE" ]] || { echo "Missing Xcode Cloud archive"; exit 1; }
APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
[[ -n "$APP" ]] || { echo "Missing archived application"; exit 1; }
python3 - "$APP" <<'PY'
import pathlib,plistlib,sys
app=pathlib.Path(sys.argv[1])
info=plistlib.loads((app/"Info.plist").read_bytes())
assert info.get("CFBundleIdentifier")=="com.nextsolution.nextledger"
assert info.get("CFBundleShortVersionString")=="1.3.84"
assert "iCloud.com.nextsolution.dailyledger" in info.get("NSUbiquitousContainers", {})
forbidden=(b"nextjailbreak",b"next jailbreak",b"next-jailbreak",
           b"nextsolution.cc",b"files.nextsolution",
           b"next solution",b"trollstore",b"roothide",b"cydia",b"sileo")
found=[]
for p in app.rglob("*"):
  if p.is_file() and not p.is_symlink():
    raw=p.read_bytes().lower()
    found += [(str(p.relative_to(app)),t.decode()) for t in forbidden if t in raw]
assert not found, f"Prohibited studio or jailbreak references: {found}"
print("PASS: Next Ledger archive branding and app identity")
PY
