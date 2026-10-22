# NovaBrowser — Milestone 1

A native iOS 16+ SwiftUI / WKWebView browser generated with XcodeGen and packaged for TrollStore. Bundle identifier: `com.example.novabrowser`.

## Build on GitHub (no local Mac)

Upload the **entire** directory to `NovaBrowser/` in a GitHub repository and upload `.github/workflows/build-novabrowser.yml` to the **repository-root** workflow folder (`.github/workflows/build-novabrowser.yml`). Pushing those files starts the macOS Actions workflow automatically; alternatively use **Actions → NovaBrowser M1 iOS Build → Run workflow**. Download the `NovaBrowser-M1` artifact when the run completes.

The workflow installs XcodeGen and ldid via Homebrew, Pillow via pip, runs `xcodegen generate`, and then `./build_tipa.sh`. The script executes `xcodebuild build` with `CODE_SIGNING_ALLOWED=NO` for a generic iOS device, checks the compiled executable, stages `Payload/NovaBrowser.app`, applies `ldid -Sentitlements.plist`, and zips `dist/NovaBrowser.tipa`.

## Local macOS build

Install Xcode (including iOS SDK), `brew install xcodegen ldid`, and `python3 -m pip install Pillow`. Run `xcodegen generate` followed by `./build_tipa.sh`. The source tree does not include a hand-maintained `.pbxproj`.

## TrollStore installation

Send the generated `.tipa` to the iPhone, open/share it in TrollStore, and select Install. The app is compiled without Apple Developer provisioning and then *ad-hoc signed* by ldid; it is not literally signature-free. Installation requires a TrollStore-compatible iOS version/device. The app's Documents/Downloads folder is visible in Files and via file sharing.

## Entitlements

- `com.apple.private.security.no-sandbox`: asks TrollStore to omit the usual app sandbox. It is not needed for ordinary WebKit browsing; kept for the explicitly requested TrollStore profile. This raises the app's privilege level.
- `platform-application`: privileged platform classification; not needed for M1 browsing, retained only for the requested TrollStore experiment.
- `dynamic-codesigning`: allows dynamic code-signing on supported systems. Not required by M1 and may not be honored outside TrollStore contexts.
- `com.apple.security.iokit-user-client-class`: deliberately **not included**, because M1 does not use direct IOKit device clients.

Remove any nonessential privileges for a production build. Entitlement acceptance depends on TrollStore and the OS, not the Xcode compile check.

## Browser features

- WebKit tabs, tab grid, reordering, private nonpersistent tabs, address search, progress, back/forward, reload/stop, pull refresh, in-page find, page zoom, share sheet, bookmarks, history, downloads and network-deferred session restore. Restored pages only connect after tapping **Load Restored Page**.
- Search engines: DuckDuckGo, Google, Bing, Brave.
- Private tabs are not restored and their visited URLs are not added to persistent history.
- `SiteSettingsResolver` combines global and exact-host overrides for user-agent preset, desktop mode, JavaScript, and pop-up mode. Applying compatibility overrides to WKWebView is part of Milestone 2, rather than pretending they are already active.
- Both new-window routing paths call `PopupPolicy.decide`, which deliberately always returns `.allow` in M1. Actual blocking is Milestone 2.

## Known limitations

All iOS browsers built with WKWebView use the installed iOS WebKit engine. This does not supply newer WebKit APIs, Flash, NPAPI, Chrome extensions, or a different Chromium/Gecko engine. Userscripts, compatibility polyfills, real pop-up blocking, certificate overrides, and the VPN extension are not M1 capabilities. Native Web Inspector attachment is available on iOS 16.4+ when paired with a Mac. Full website-specific permission and external-scheme handling will be considered in later milestones.

## Tests

`NovaBrowserTests` includes URL routing, site-settings override precedence, pop-up-policy dispatch, and state encoding tests. These can run on an iOS simulator using `xcodebuild test`, while the packaging workflow intentionally builds for a physical generic iOS destination.

## 1.0.1 startup-crash mitigation and diagnostics

This patch removes the unnecessary platform/no-sandbox/dynamic-codesigning entitlements from the standard browser build, defers WKWebView construction until a website is actually opened, and adds an offline `NovaBrowserDiagnostics.txt` under Documents (Files > On My iPhone > NovaBrowser). The log records only startup milestones, never browsing URLs or credentials. From Settings, use **Copy Launch Diagnostics** or **Share Launch Diagnostics**. If the process is terminated before it reaches the entry point or by iOS code-signature enforcement, there may be no app-created log. Check iOS Settings > Privacy & Security > Analytics & Improvements > Analytics Data for native crash reports. This mitigates plausible startup crash causes but requires on-device verification.
