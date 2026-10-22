# NovaBrowser — Milestone 1

An iOS 16+ browser written in Swift 5.9-compatible Swift, SwiftUI and UIKit, using the device's WKWebView engine. Bundle ID: `com.example.novabrowser`. Version: `1.0.0 (1)`. iPhone and iPad, portrait and landscape, light/dark/system appearance, Dynamic Type, VoiceOver labels and 44-point primary controls.

This is the first runnable milestone, not the completed M2–M4 feature set. See [MILESTONES.md](MILESTONES.md) for the remaining scope. There are no runtime third-party dependencies and no automatic network calls on launch. The generated Xcode project and all icon assets are checked in.

## Included in M1

- WKWebView navigation, back/forward gestures, reload/stop, progress and pull-to-refresh.
- Smart address parsing and Google, DuckDuckGo, Bing or Brave search.
- New/close/switch tabs, a thumbnail grid, drag-to-reorder and accessible Move Earlier/Later actions.
- Private tabs sharing a separate in-memory website store for the current private session. The store is discarded after the last private tab closes. Private tab URLs, thumbnails and cookies are never written by NovaBrowser to its session file.
- Atomic regular-session persistence. Restored tabs show a Resume button and do not connect until tapped. Titles, order and current URLs restore; the native back/forward list does not survive process termination.
- Share sheet, find-in-page and page zoom.
- Native JavaScript dialogs, file-upload controls, WebKit media permission prompts, inline video, picture-in-picture and AirPlay configuration.
- User-activated new-window links; unsolicited windows are rejected pending M2's full pop-up engine. Confirmed `tel:`, `mailto:` and `itms-apps:` taps can open their external apps.
- Clear all regular website data. Private content is covered when the app becomes inactive.
- Local browser test page and 15 XCTest cases covering URL and session behavior.

## Install the first TrollStore build

1. Use a device/iOS combination already supported by TrollStore. The app targets iOS 16+, but that does **not** mean TrollStore supports every later iOS version.
2. Download `NovaBrowser.tipa` from the workflow's `NovaBrowser-M1-TrollStore` artifact and extract the artifact ZIP first.
3. Share the `.tipa` to TrollStore and install it. No developer certificate or provisioning profile is required for this distribution path.
4. Open NovaBrowser, enter a URL, or use Settings → Open Local Browser Test for an offline check.

The app is built with Apple code signing disabled. `ldid` then applies an ad-hoc/fake signature carrying the entitlements, as required by TrollStore. Therefore “unsigned TIPA” here means **not Apple-provisioned or distribution-signed**, not an executable with absolutely no signature data.

## Build on a Mac

Requirements: Xcode 15+ with iOS SDK and a simulator runtime, Command Line Tools, Python 3, and `ldid` (`brew install ldid`). Swift uses Xcode's `SWIFT_VERSION = 5.0` language mode; Xcode does not accept `5.9` as a language-mode value. Source uses only language features available in Swift 5.9. CI prefers Xcode 15.4 when installed and records the actual toolchain.

```bash
cd NovaBrowser
bash build_tipa.sh
bash Scripts/test_simulator.sh
```

Output: `dist/NovaBrowser.tipa`, SHA-256 checksum, compiler logs and XCTest results. `build_tipa.sh` builds Release for `generic/platform=iOS`, `arm64`, with `CODE_SIGNING_ALLOWED=NO`; copies the app into `Payload/NovaBrowser.app`; applies `ldid -Sentitlements.plist`; validates the executable, minimum OS and entitlements; then ZIPs Payload. Any failed build, signing or archive check stops the script. No dummy app or stale output is substituted.

The project generator is dependency-free and deterministic:

```bash
python3 Scripts/generate_project.py
open NovaBrowser.xcodeproj
```

The included Python/Pillow icon generator creates the opaque square 1024-pixel master and every iPhone/iPad AppIcon slot. Icon generation is not needed for a normal build because the assets are included. To reproduce them:

```bash
python3 -m venv .venv
.venv/bin/pip install Pillow==11.3.0
.venv/bin/python Scripts/generate_icon.py
```

## Build without a Mac

In `zeshan0727/NextJailbreak`, the workflow lives at repository-root `.github/workflows/build-novabrowser.yml`; a copy is included inside this source folder. Pushes to `codex/novabrowser-m1` build automatically. Pull requests touching this project also run the workflow. Once the workflow is on your default branch, Actions → NovaBrowser M1 — Build and Test → Run workflow can start manual builds.

It builds the arm64 app, runs XCTest on an installed iPhone simulator, launches the simulator app, captures light/dark screenshots, and uploads the TIPA only after all steps pass. Evidence is uploaded even on failure. CI uses no signing certificates, repository secrets, external server credentials or site deployment steps.

For a standalone repository, place this folder's contents at the repo root and keep its `.github` directory. Adjust the workflow push branch/path filters to your preferred branch; its build steps detect either layout.

## Entitlements and platform limits

| Entitlement | Reason / status |
| --- | --- |
| `application-identifier` | Stable app identity for TrollStore. |
| `com.apple.private.security.no-sandbox` | Requested TrollStore unsandboxed configuration, retaining the app container. The M1 browser itself does not need arbitrary filesystem access. |
| `platform-application` | Requested platform flag; TrollStore documents side effects and does not provide full platformization. |
| `com.apple.private.security.storage.AppDataContainers` | Retains access to the application's data container with the above two flags. |
| `dynamic-codesigning` | **Deliberately omitted.** TrollStore documents this as a banned entitlement on A12+ that can crash apps on launch. This is a necessary deviation from the original entitlement request for devices such as iPhone 14 Pro Max. WKWebView does not require the app to have this entitlement. |
| `com.apple.security.iokit-user-client-class` | Omitted: no direct IOKit user clients are used. Do not add broad exceptions without evidence of a specific need. |

Reference: [official TrollStore README, banned entitlements and unsandboxing](https://github.com/opa334/TrollStore#banned-entitlements). `ldid` success is not proof of physical-device compatibility; installation and browsing on the target phone remain a device acceptance test.

## M1 acceptance checks

1. Launch with networking off: local start page appears, search/address entry and settings work.
2. Open a page, follow a link, navigate back/forward, pull to refresh, and stop a slow load.
3. Open several tabs, switch without losing page state, reorder with drag or context menu, and close tabs.
4. Enter Private mode, browse, close the last private tab, and reopen Private mode: its website session is new.
5. Terminate and relaunch: regular URLs return in order and wait for Resume; private tabs do not return.
6. Use the bundled test page for alert/confirm/prompt, file input, zoom, find and an external-scheme confirmation.
7. Check iPad layout, landscape, dark mode and larger accessibility text sizes.

## Troubleshooting

- **No Xcode / no `xcodebuild`:** use GitHub Actions; Linux cannot compile Apple's iOS frameworks.
- **No simulator:** install an iOS runtime in Xcode Settings → Platforms. The test script discovers an available iPhone rather than assuming a specific model.
- **`ldid` missing:** `brew install ldid`, or set `LDID=/absolute/path/to/ldid` when running the build script.
- **App will not launch after TrollStore installation:** check that no banned entitlements were added, use a supported TrollStore/iOS combination, and refresh app registrations using TrollStore's persistence helper if an icon-cache reload changed registration.
- **Site has an invalid certificate:** M1 shows the WebKit error and refuses the connection. M2 will add the requested explicit per-host warning flow; there is no silent trust bypass.
- **HTTP-only router page fails:** turn off HTTPS-first addresses and enter the `http://` address explicitly. The setting affects typed addresses, not every subresource or redirect.
- **Page stopped under memory pressure:** tap Reload; iOS can terminate WebContent processes. Many open tabs can increase memory usage.
- **A JavaScript login popup is blocked:** M1 intentionally lacks the configurable login allowlist. The full user-gesture, login/payment allowlist and blocked-popup UI arrive in M2.
- **Remote inspection:** `isInspectable` is enabled only on iOS 16.4+ where the public API exists. iOS 16.0–16.3 does not offer the same release-app opt-in API. [Apple documentation](https://developer.apple.com/documentation/safari-developer-tools/enabling-inspecting-content-in-your-apps).

## Userscripts and VPN

M1 has no userscript installer or VPN controls. M3 will provide `.user.js` import from paste or URL, metadata matching, timing and a scoped native GM bridge. M4 will add the embedded `NovaTunnel.appex`, Keychain-backed profiles and explicit WireGuard imports. No placeholder VPN connection, fake leak test or invented server list is included in this build. The complete requirements, including import and troubleshooting work, are retained in MILESTONES.md.

## Known limitations

- This is WebKit, not a newer Safari engine. User-agent spoofing and JavaScript shims cannot add missing engine, codec, DRM or operating-system capabilities.
- No Flash, NPAPI plugins or Chrome/Firefox extension runtime.
- M1 does not yet include bookmarks, history UI, WKDownload management, per-site compatibility settings, polyfills, content blockers, advanced popup blocking, userscripts, Eruda, private-tab Face ID or VPN.
- Fullscreen/video/DRM, service workers, Web Push, cookie policy, camera, geolocation, PiP and AirPlay remain subject to iOS and website restrictions; configuration is not a guarantee that each website supports them.
- “Allow third-party cookies” cannot override all iOS Intelligent Tracking Prevention restrictions through public WKWebView APIs; M2 must explain this rather than promise a full Safari-policy override.
- Private browsing is local-storage isolation, not network anonymity. The underlying OS/WebKit may retain operational data outside the app's session file.
- No default-browser entitlement is included. No root CA is installed and there is no HTTPS interception.
- Simulator checks do not prove TrollStore registration, physical camera behavior, DRM playback or future Network Extension functionality.
