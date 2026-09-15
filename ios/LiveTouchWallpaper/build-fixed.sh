#!/bin/bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos directory}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="LiveTouch-0.1.5-roothide-launch-fix.tipa"
rm -rf "$ROOT/build" "$ROOT/Payload"
mkdir -p "$ROOT/build"

# The TrollStore app and its root helper must NOT use the roothide package
# scheme, because that adds a launch-time dependency on
# @loader_path/.jbroot/usr/lib/libroothide.dylib. TrollStore does not create
# the .jbroot symlink inside an app bundle. They discover the active jbroot
# directly at runtime instead. Only the SpringBoard engine is RootHide-built.
make -C "$ROOT/App" clean all FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=
make -C "$ROOT/RootHelper" clean all FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=
make -C "$ROOT/Engine" clean all FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide

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
d['CFBundleShortVersionString']='0.1.5'
d['CFBundleVersion']='6'
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
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'RootHide jbroot scan'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'RootHide tweak directory:'
strings "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'Engine installed for RootHide.'
strings "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" | grep -Fq 'RootHide jbroot scan'
if command -v otool >/dev/null 2>&1; then
  if otool -L "$ROOT/Payload/LiveTouch.app/LiveTouch" | grep -Fq 'libroothide.dylib'; then
    echo 'ERROR: main app still links libroothide.dylib'; exit 3
  fi
  if otool -L "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" | grep -Fq 'libroothide.dylib'; then
    echo 'ERROR: root helper still links libroothide.dylib'; exit 4
  fi
fi

cd "$ROOT"
zip -qry "build/$OUT" Payload
rm -rf Payload
printf 'Built %s\n' "$ROOT/build/$OUT"
