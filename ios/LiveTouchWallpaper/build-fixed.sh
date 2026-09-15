#!/bin/bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos directory}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="LiveTouch-0.1.3-test.tipa"
rm -rf "$ROOT/build" "$ROOT/Payload"
mkdir -p "$ROOT/build"

make -C "$ROOT/App" clean all FINALPACKAGE=1
make -C "$ROOT/RootHelper" clean all FINALPACKAGE=1
make -C "$ROOT/Engine" clean all FINALPACKAGE=1

APP_EXE=$(find "$ROOT/App/.theos" -type f -path '*/LiveTouch.app/LiveTouch' -print0 | xargs -0 ls -S 2>/dev/null | head -1 || true)
HELPER=$(find "$ROOT/RootHelper/.theos" -type f -name 'LiveTouchRootHelper' -print0 | xargs -0 ls -S 2>/dev/null | head -1 || true)
ENGINE=$(find "$ROOT/Engine/.theos" -type f -name 'LiveTouchEngine.dylib' -print0 | xargs -0 ls -S 2>/dev/null | head -1 || true)
if [[ -z "$APP_EXE" || -z "$HELPER" || -z "$ENGINE" ]]; then echo "Build product missing"; exit 2; fi

mkdir -p "$ROOT/Payload/LiveTouch.app"
cp "$APP_EXE" "$ROOT/Payload/LiveTouch.app/LiveTouch"
cp "$ROOT/App/Resources/Info.plist" "$ROOT/Payload/LiveTouch.app/Info.plist"
cp "$HELPER" "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper"
cp "$ENGINE" "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib"
cp "$ROOT/Engine/LiveTouchEngine.plist" "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.plist"
chmod 0755 "$ROOT/Payload/LiveTouch.app/LiveTouch" "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib"

python3 - "$ROOT/Payload/LiveTouch.app/Info.plist" <<'PY'
import plistlib,sys
p=sys.argv[1]
with open(p,'rb') as f: d=plistlib.load(f)
d['CFBundleShortVersionString']='0.1.3'
d['CFBundleVersion']='4'
d['TSRootBinaries']=['LiveTouchRootHelper']
with open(p,'wb') as f: plistlib.dump(d,f,fmt=plistlib.FMT_XML,sort_keys=False)
PY

if command -v ldid >/dev/null 2>&1; then
  ldid -S "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" || true
  ldid -S "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib" || true
  ldid -S"$ROOT/App/entitlements.plist" "$ROOT/Payload/LiveTouch.app/LiveTouch"
fi

test -f "$ROOT/Payload/LiveTouch.app/Info.plist"
test -x "$ROOT/Payload/LiveTouch.app/LiveTouch"
test -x "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper"
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq -- '--root-helper'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'Detected %s tweak directory:'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq '/private/preboot'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'Refusing to write to the read-only rootful /Library path.'

cd "$ROOT"
zip -qry "build/$OUT" Payload
rm -rf Payload
printf 'Built %s\n' "$ROOT/build/$OUT"
