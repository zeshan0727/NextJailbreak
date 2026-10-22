#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
mkdir -p build
xcrun simctl list devices available -j > build/simulators.json
SIMULATOR_ID="$(python3 - <<'PY'
import json
data=json.load(open('build/simulators.json'))
for runtime, devices in sorted(data['devices'].items(), reverse=True):
    if 'iOS' not in runtime: continue
    for device in devices:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid']); raise SystemExit(0)
raise SystemExit('No installed iPhone simulator runtime. Install one in Xcode Settings > Platforms.')
PY
)"
rm -rf build/NovaBrowserTests.xcresult
xcodebuild -project NovaBrowser.xcodeproj -scheme NovaBrowser -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -destination-timeout 120 \
  -derivedDataPath build/simulator -resultBundlePath build/NovaBrowserTests.xcresult \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO test 2>&1 | tee build/simulator-tests.log
xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcrun simctl install "$SIMULATOR_ID" build/simulator/Build/Products/Debug-iphonesimulator/NovaBrowser.app
xcrun simctl status_bar "$SIMULATOR_ID" override --time '9:41' --batteryState charged --batteryLevel 100
xcrun simctl launch --terminate-running-process "$SIMULATOR_ID" com.example.novabrowser
sleep 3
xcrun simctl io "$SIMULATOR_ID" screenshot build/iPhone-start-page.png
xcrun simctl ui "$SIMULATOR_ID" appearance dark
sleep 1
xcrun simctl io "$SIMULATOR_ID" screenshot build/iPhone-dark-start-page.png
xcrun simctl ui "$SIMULATOR_ID" appearance light
