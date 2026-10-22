#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
command -v xcodebuild >/dev/null || { echo 'xcodebuild requires macOS with Xcode' >&2; exit 2; }
command -v ldid >/dev/null || { echo 'ldid is required (brew install ldid)' >&2; exit 2; }
if [[ ! -d NovaBrowser.xcodeproj ]]; then
    command -v xcodegen >/dev/null || { echo 'xcodegen is required' >&2; exit 2; }
    xcodegen generate --spec project.yml
fi
"${ROOT}/scripts/generate_icon.py"
OUT="$ROOT/dist"
DERIVED="$OUT/DerivedData"
mkdir -p "$OUT"
set -o pipefail
xcodebuild -project NovaBrowser.xcodeproj -scheme NovaBrowser -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee "$OUT/xcodebuild.log"
APP="$DERIVED/Build/Products/Release-iphoneos/NovaBrowser.app"
[[ -f "$APP/NovaBrowser" ]] || { echo 'Build did not produce NovaBrowser executable' >&2; exit 4; }
STAGING="$OUT/staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/Payload"
ditto "$APP" "$STAGING/Payload/NovaBrowser.app"
ldid -S"$ROOT/entitlements.plist" "$STAGING/Payload/NovaBrowser.app/NovaBrowser"
(
  cd "$STAGING"
  /usr/bin/zip -qry "$OUT/NovaBrowser.tipa" Payload
)
[[ -s "$OUT/NovaBrowser.tipa" ]] || { echo 'Failed to create .tipa' >&2; exit 5; }
echo "SUCCESS: $OUT/NovaBrowser.tipa"
