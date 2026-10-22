#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"
command -v xcodebuild >/dev/null || { echo "Xcode is required. Use the included GitHub Actions workflow if you do not have a Mac." >&2; exit 1; }
LDID="${LDID:-$(command -v ldid || true)}"
[ -n "$LDID" ] && [ -x "$LDID" ] || { echo "Install ldid with: brew install ldid (or set LDID to its absolute executable path)." >&2; exit 1; }
python3 Scripts/generate_project.py
test -s NovaBrowser/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png || { echo "Run Scripts/generate_icon.py first (requires Pillow)." >&2; exit 1; }
mkdir -p build dist
xcodebuild -version | tee build/toolchain.txt
xcrun swift --version | tee -a build/toolchain.txt
xcodebuild -project NovaBrowser.xcodeproj -scheme NovaBrowser -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos -derivedDataPath build/device \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' clean build 2>&1 | tee build/device-build.log

APP_SOURCE="$PROJECT_ROOT/build/device/Build/Products/Release-iphoneos/NovaBrowser.app"
STAGE="$PROJECT_ROOT/build/tipa-stage"
test -x "$APP_SOURCE/NovaBrowser"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
ditto "$APP_SOURCE" "$STAGE/Payload/NovaBrowser.app"
APP="$STAGE/Payload/NovaBrowser.app"
rm -rf "$APP/_CodeSignature" "$APP/embedded.mobileprovision"

# ldid produces a fake/ad-hoc signature containing entitlements, not an Apple
# distribution signature. TrollStore applies its installation signature later.
"$LDID" -S"$PROJECT_ROOT/entitlements.plist" "$APP/NovaBrowser"
"$LDID" -e "$APP/NovaBrowser" > build/applied-entitlements.plist
python3 - "$APP" <<'PY'
from pathlib import Path
import plistlib, sys
app = Path(sys.argv[1])
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.example.novabrowser', info
assert info['MinimumOSVersion'] == '16.0', info
assert (app / info['CFBundleExecutable']).is_file()
ent = plistlib.loads(Path('build/applied-entitlements.plist').read_bytes())
assert ent['com.apple.private.security.no-sandbox'] is True
assert ent['platform-application'] is True
assert not ent.get('dynamic-codesigning', False), 'Blocked A12+ entitlement'
assert not (app / 'embedded.mobileprovision').exists()
print('Bundle identifier, minimum iOS, executable and applied entitlements verified.')
PY
xcrun lipo -verify_arch arm64 "$APP/NovaBrowser"
rm -f "$PROJECT_ROOT/dist/NovaBrowser.tipa"
(cd "$STAGE" && COPYFILE_DISABLE=1 /usr/bin/zip -qry "$PROJECT_ROOT/dist/NovaBrowser.tipa" Payload)
unzip -t dist/NovaBrowser.tipa > build/archive-verification.txt
shasum -a 256 dist/NovaBrowser.tipa > dist/NovaBrowser.tipa.sha256
echo "Built $PROJECT_ROOT/dist/NovaBrowser.tipa"
