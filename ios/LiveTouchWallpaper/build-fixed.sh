#!/bin/bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos directory}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="LiveTouch-0.1.7-final-cleanup.tipa"
rm -rf "$ROOT/build" "$ROOT/Payload"
mkdir -p "$ROOT/build"

# Final cleanup-only build. Do not bundle or install the wallpaper engine again.
# The app only needs its embedded root-helper path plus the legacy helper fallback.
make -C "$ROOT/App" clean all FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=
make -C "$ROOT/RootHelper" clean all FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=

APP_EXE=$(find "$ROOT/App/.theos" -type f -path '*/LiveTouch.app/LiveTouch' -print0 | xargs -0 ls -S 2>/dev/null | head -1 || true)
HELPER=$(find "$ROOT/RootHelper/.theos" -type f -name 'LiveTouchRootHelper' -print0 | xargs -0 ls -S 2>/dev/null | head -1 || true)
if [[ -z "$APP_EXE" || -z "$HELPER" ]]; then echo "Build product missing"; exit 2; fi

mkdir -p "$ROOT/Payload/LiveTouch.app"
cp "$APP_EXE" "$ROOT/Payload/LiveTouch.app/LiveTouch"
cp "$ROOT/App/Resources/Info.plist" "$ROOT/Payload/LiveTouch.app/Info.plist"
cp "$HELPER" "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper"
chmod 0755 "$ROOT/Payload/LiveTouch.app/LiveTouch" "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper"

python3 - "$ROOT/Payload/LiveTouch.app/Info.plist" <<'PY'
import plistlib,sys
p=sys.argv[1]
with open(p,'rb') as f: d=plistlib.load(f)
d['CFBundleDisplayName']='LiveTouch Cleanup'
d['CFBundleName']='LiveTouch Cleanup'
d['CFBundleShortVersionString']='0.1.7'
d['CFBundleVersion']='8'
d['TSRootBinaries']=['LiveTouchRootHelper']
with open(p,'wb') as f: plistlib.dump(d,f,fmt=plistlib.FMT_XML,sort_keys=False)
PY

if command -v ldid >/dev/null 2>&1; then
  ldid -S "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" || true
  ldid -S"$ROOT/App/entitlements.plist" "$ROOT/Payload/LiveTouch.app/LiveTouch"
fi

test -f "$ROOT/Payload/LiveTouch.app/Info.plist"
test -x "$ROOT/Payload/LiveTouch.app/LiveTouch"
test -x "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper"
test ! -e "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib"
test ! -e "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.plist"
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq -- '--root-helper'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'Uninstall LiveTouch Files'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'LiveTouch uninstall cleanup complete.'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq '/usr/lib/TweakInject'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq '/Library/MobileSubstrate/DynamicLibraries'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq '/var/mobile/Library/LiveTouchWallpaper'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'com.nextjailbreak.livetouch.plist'
if command -v otool >/dev/null 2>&1; then
  if otool -L "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'libroothide.dylib'; then
    echo 'ERROR: main app links libroothide.dylib'; exit 3
  fi
fi

cd "$ROOT"
zip -qry "build/$OUT" Payload
rm -rf Payload
printf 'Built %s\n' "$ROOT/build/$OUT"
