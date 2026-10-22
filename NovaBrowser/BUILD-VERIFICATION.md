# M1 build verification — 22 October 2026

- GitHub Actions run: https://github.com/zeshan0727/NextJailbreak/actions/runs/39732993240
- Compiled source commit: `9cb7344cc2ebeaae90b441ee94af0d466c30786f`
- Xcode 15.4, Apple Swift 5.10 compiler in Swift 5 language mode; source is Swift 5.9-compatible.
- Release device build: passed; arm64, minimum iOS 16.0.
- XCTest: **15 passed, 0 failures** (9 URL parser, 6 session-storage tests).
- Simulator install and launch: passed; light/dark screenshots captured in the build-evidence artifact.
- TIPA layout, executable architecture, bundle identifier, minimum OS, applied entitlements and ZIP integrity: passed.
- Developer certificate / provisioning profile: none. ldid fake-signs the requested TrollStore entitlements.
- TIPA size: 826,032 bytes.
- SHA-256: `d7ad2812999c8f2da2552393ff932ab834949be4a284ca60b27ff4b9e06e04e3`.

There are no Swift compiler warnings in the successful run. Asset compilation emitted one SDK/simulator trait warning for iPhone17,1 on iOS 18.2; the app built and tests passed. The simulator run is not a physical iOS 16/TrollStore installation test. Camera, DRM, website-specific behavior, and physical-device installation remain device acceptance checks.

The first pipeline attempt compiled the app but failed the packaging architecture-check command; the command was corrected and the full pipeline then passed. Changes after the compiled commit only record these results and expand sparse-checkout paths for a standalone source repository; app code and build script are unchanged.

M2–M4 have not been implemented or compile-checked yet. The VPN extension is not present in M1.
