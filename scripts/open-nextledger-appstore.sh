#!/bin/zsh
# Generate and open the release-only Next Ledger project for App Store signing.
# This script does not sign, upload, or change any user data.
set -euo pipefail
cd "${0:A:h}/.."

echo "=== Next Ledger 1.3.84 Build 112 — App Store preparation ==="
echo "macOS: $(sw_vers -productVersion)"
xcodebuild -version
SDK="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iOS SDK: $SDK"
SDK_MAJOR="${SDK%%.*}"
if [[ "$SDK_MAJOR" -lt 26 ]]; then
  echo "ERROR: Apple currently requires Xcode 26+ with the iOS 26+ SDK."
  exit 1
fi
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is missing. Install Homebrew and run: brew install xcodegen"
  exit 1
fi
xcodegen generate
test -f NextLedger.xcodeproj/project.pbxproj
echo "Generated Xcode project: NextLedger.xcodeproj"
echo "Build identity: com.nextsolution.dailyledger"
echo "Widget identity: com.nextsolution.dailyledger.widgets"
echo "iCloud Documents: iCloud.com.nextsolution.dailyledger"
echo
echo "In Xcode: Signing & Capabilities > Team T52CDY8W32 for BOTH targets."
echo "Verify that the App Store Connect app record has the SAME bundle ID."
echo "Then select Any iOS Device (arm64) > Product > Archive."
open NextLedger.xcodeproj
