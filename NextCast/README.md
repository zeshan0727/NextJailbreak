# Next Cast — iOS 16+ / Chromecast

Native SwiftUI movie player and local-file Chromecast sender. **No Google sign-in, cloud account, remote server, subscriptions, or Mac required for CI builds.**

## Features

- Import multiple videos from Files to an on-device library.
- Search, preview/play locally, remove videos, view file sizes.
- Discover Chromecast / Google Cast TVs on the same Wi-Fi with Google's Cast SDK.
- Select a receiver with the standard Chromecast picker and send local movies.
- Remote play, pause, seek slider, and skip back/forward 15 seconds.
- Video is served **from the iPhone** using HTTP with proper byte-range GET/HEAD, seeking, CORS and no upload.
- Ad-hoc signed `.tipa` artifact generated on GitHub Actions for compatible TrollStore test devices.
- Dark responsive UI, custom generated app icon, iOS 16+.

## Setup and testing

1. On the GitHub branch `agent/next-cast-1.0.0`, open **Actions → Build Next Cast iOS**.
2. Download the workflow artifact **NextCast-iOS16-TIPA**.
3. Unzip the GitHub Actions artifact; inside is `NextCast-1.0.0.tipa`.
4. On an iOS 16 device with compatible TrollStore, open the `.tipa` in TrollStore.
5. Give Next Cast **Local Network** permission when requested.
6. Connect iPhone and Chromecast to the same Wi-Fi, with guest/AP isolation disabled.
7. Import an MP4 (recommended: H.264 video and AAC audio), tap the movie and choose Cast TV.
8. Keep Next Cast foregrounded and iPhone awake while the TV reads local file data.

**Compatibility:** Chromecast and Google Cast built-in TVs only. Other TVs require AirPlay or DLNA; this app does not implement those protocols. The TV has to support the video's container and codecs; there is no on-device transcoding in v1. MOV, WEBM, HEVC support varies by receiver. MKV and AVI may be imported for local playback but are intentionally blocked from direct casting.

**Important iOS limitation:** iOS can suspend an app's local HTTP service when backgrounded/locked. Keep the app open for reliable playback; this limitation is not solved by Google account login. The app disables auto screen lock while a Cast session is connected, then restores it on disconnect. Battery use will be higher.

**Security:** The temporary HTTP server runs only on your local Wi-Fi and exposes only imported media IDs, not arbitrary directories. Devices on the same LAN could access a media URL while the app is casting; use trusted Wi-Fi. Traffic is unencrypted HTTP, required by this basic receiver setup.

## Source / build

`NextCast/project.yml` uses XcodeGen + the official [Google Cast iOS SDK](https://github.com/googlecast/google-cast-ios-sdk) via Swift Package Manager. The official Google Cast *Default Media Receiver* ID is `CC1AD845`; a custom/registered receiver app and paid Google developer account are not needed for this limited use case.

The public GitHub Actions macOS runner generates the icon, Xcode project, archives an unsigned device build, applies ad-hoc code signing and uploads a `.tipa` artifact. This package **is for TrollStore testing**, not App Store distribution or ordinary stock-iOS installation. Apple distribution signing would need a provisioning profile and appropriate certificates.

Build on your Mac as an alternative:
```sh
python3 -m pip install pillow
python3 NextCast/tools/create_icon.py
cd NextCast
xcodegen generate
xcodebuild -project NextCast.xcodeproj -scheme NextCast -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Known test boundaries

- The GitHub workflow's compile/package success does not prove that your particular Chromecast TV plays your particular movie. Verify on real hardware.
- HTTP byte-range serving is included to enable seek behavior; some TVs reject container/codec combinations even when the range server works.
- If the Cast device list is empty, confirm iPhone Settings → Next Cast → Local Network, both on the same Wi-Fi, and router multicast/mDNS traffic allowed.
- Future enhancements: media thumbnails, SRT subtitle track serving, playlists, iOS-compatible transcoding/remux, DLNA/AirPlay, sleep/background handling.
