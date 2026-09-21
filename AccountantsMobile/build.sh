#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VERSION="0.1.0"
BUILD="1"
DIST="$PWD/dist"
rm -rf "$DIST" build AccountantsMobile.xcodeproj
mkdir -p "$DIST"
if ! command -v xcodegen >/dev/null 2>&1; then brew install xcodegen; fi
xcodegen generate
set -o pipefail
xcodebuild -project AccountantsMobile.xcodeproj -scheme AccountantsMobile -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build | tee "$DIST/xcodebuild.log"
APP="$PWD/build/Build/Products/Release-iphoneos/Accountants.app"
test -d "$APP"
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist" | grep -qx 'com.nextsolution.accountantsmobile'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" | grep -qx "$VERSION"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" | grep -qx "$BUILD"
rm -rf /tmp/AccountantsMobilePayload && mkdir -p /tmp/AccountantsMobilePayload/Payload
cp -R "$APP" /tmp/AccountantsMobilePayload/Payload/
(cd /tmp/AccountantsMobilePayload && zip -qry "$DIST/AccountantsMobile-$VERSION.tipa" Payload)
cp "$DIST/AccountantsMobile-$VERSION.tipa" "$DIST/AccountantsMobile-$VERSION.ipa"
zip -qr "$DIST/AccountantsMobile-$VERSION-source.zip" project.yml AccountantsMobile build.sh README.md
(cd "$DIST" && shasum -a 256 AccountantsMobile-$VERSION.tipa AccountantsMobile-$VERSION.ipa AccountantsMobile-$VERSION-source.zip > SHA256SUMS.txt)
unzip -tq "$DIST/AccountantsMobile-$VERSION.tipa"
file "$APP/Accountants" | tee "$DIST/binary.txt"
