#!/bin/bash
set -euo pipefail
: "${THEOS:?Set THEOS to your Theos directory}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
rm -rf "$ROOT/build" "$ROOT/Payload"
mkdir -p "$ROOT/build"

make -C "$ROOT/App" clean all FINALPACKAGE=1
make -C "$ROOT/RootHelper" clean all FINALPACKAGE=1
make -C "$ROOT/Engine" clean all FINALPACKAGE=1

APP=$(find "$ROOT/App/.theos" -type d -name 'LiveTouch.app' | head -1)
HELPER=$(find "$ROOT/RootHelper/.theos" -type f -name 'LiveTouchRootHelper' | head -1)
ENGINE=$(find "$ROOT/Engine/.theos" -type f -name 'LiveTouchEngine.dylib' | head -1)
if [[ -z "$APP" || -z "$HELPER" || -z "$ENGINE" ]]; then echo "Build product missing"; exit 2; fi

mkdir -p "$ROOT/Payload/LiveTouch.app"
# Theos also creates an intermediate .app under obj containing dSYM data but no
# installable Info.plist. Construct the distributable bundle explicitly.
cp "$APP/LiveTouch" "$ROOT/Payload/LiveTouch.app/LiveTouch"
cp "$ROOT/App/Resources/Info.plist" "$ROOT/Payload/LiveTouch.app/Info.plist"
cp "$HELPER" "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper"
cp "$ENGINE" "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib"
cp "$ROOT/Engine/LiveTouchEngine.plist" "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.plist"
chmod 0755 "$ROOT/Payload/LiveTouch.app/LiveTouch" "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib"

if command -v ldid >/dev/null 2>&1; then
  ldid -S "$ROOT/Payload/LiveTouch.app/LiveTouchRootHelper" || true
  ldid -S "$ROOT/Payload/LiveTouch.app/LiveTouchEngine.dylib" || true
  ldid -S"$ROOT/App/entitlements.plist" "$ROOT/Payload/LiveTouch.app/LiveTouch"
fi

test -f "$ROOT/Payload/LiveTouch.app/Info.plist"
test -x "$ROOT/Payload/LiveTouch.app/LiveTouch"

cd "$ROOT"
zip -qry "build/LiveTouch-0.1-test.tipa" Payload
rm -rf Payload
printf 'Built %s\n' "$ROOT/build/LiveTouch-0.1-test.tipa"
