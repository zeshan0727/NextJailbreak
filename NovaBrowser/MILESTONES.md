# NovaBrowser implementation contract

Each milestone must compile and pass its relevant tests before the next starts. The first delivery is M1. Features below are requirements for subsequent milestones, not claims about the current binary.

## M1 — Browsing, tabs, icon and distribution

- Native iOS 16+ SwiftUI/UIKit browser, smart URL/search routing, private/regular tabs, tab grid/reorder, in-memory web-view preservation, opt-in restored-tab loading.
- Navigation/progress/refresh/share/find/zoom, native dialogs, media settings, basic external-scheme confirmation and local test page.
- Reproducible 1024 icon and all AppIcon sizes, complete Xcode project, arm64 Release TIPA packaging with ldid, GitHub macOS workflow and compiler/test evidence.
- URL parser and session privacy tests. Physical TrollStore installation remains a device test.

## M2 — Core storage and compatibility engine

- Bookmarks, history and WKDownload manager; Documents files visible in Files. Regular data only in persistent history. Explicit confirmation before retaining private-session downloads.
- Global/per-host user agents: iPhone Safari, iPad/desktop Safari, Windows Chrome, Android Chrome, Linux Firefox. Desktop mode must also use preferredContentMode, with a recreated configuration when required.
- Per-host JS, content blocker, autoplay, cookie policy and zoom settings; deterministic resolution and tests. Bundled content rules, site allowlist, site-specific clearing and cookie JSON import/export.
- Toggleable document-start, all-frame shims: structuredClone with honest unsupported cases; Array.at/findLast; Object.hasOwn; AbortSignal.timeout; crypto.randomUUID using secure randomness; ResizeObserver fallback; userAgentData stub; Promise.withResolvers. Never overwrite native implementations or pretend a stub supplies missing security/engine guarantees.
- HTTPS-first and tracking-parameter stripping; private-tab Face ID and clear-on-exit with lifecycle limits explained. Explicit per-host certificate warning and user choice; never globally trust invalid certificates.
- Complete file upload, camera/mic/geolocation flows and explain WebKit's service-worker, push, storage, codec and third-party-cookie restrictions.

### Pop-up blocker (mandatory M2 scope)

- Settings → Privacy & Security → Block Pop-ups, default ON; per-host Use Global / Always Block / Always Allow; address-menu quick switch reflecting resolved state. Per-site overrides win over global.
- A blocked-popup badge for the current page opens URL/timestamp/source-host records with Open and Always Allow on This Site. Persistent aggregate blocked count in Settings; private URLs never persisted.
- Shared decision function used by WKUIDelegate creation and navigation policy. Allow user-activated visible-link or same-site form flows; block no-gesture scripts, >1 window per gesture, about:blank redirect traps and bundled ad/pop-under patterns.
- Editable login/payment allowlist (including accounts.google.com, appleid.apple.com and paypal.com). Match exact hosts or valid subdomains, not substring lookalikes. Validate blank/redirect popup destinations too. Explain that public WebKit APIs expose navigation type rather than an infallible trusted gesture flag; correlate with frame-scoped JS gesture data and never claim perfect detection.
- Document-start all-frame window.open and anchor-click interception; trusted pointer/touch/key gesture window about 1 second; blocked calls return a safe closed-window stub and report to native. Per-site OFF makes interception a no-op.
- Separate toggle for heuristic click-hijack overlays and click-anywhere listeners; avoid breaking visible legitimate controls. Block programmatic app-store/custom-scheme redirects; provide explicit confirm banner.
- After >2 consecutive JavaScript dialogs, offer Prevent This Page From Showing More Dialogs.
- Decision tests: gesture/no gesture, one-per-gesture, allowlist, unsafe redirects and per-host precedence. Include `test-popups.html` with manual buttons and automatically fired scenarios.

## M3 — Userscripts and developer tools

- URL/paste `.user.js` import; @match/@include/@exclude, @run-at, enable/edit/remove, metadata matching tests and bundled samples.
- GM_getValue/GM_setValue scoped to script, GM_addStyle, GM_openInTab through pop-up policy, GM_xmlhttpRequest through native URLSession with explicit permissions and request/response correlation. Never let arbitrary page code spoof privileged handlers. Validate frame/origin/script identity and resource limits.
- Vendor Eruda locally with license and pinned version; no CDN injection. Per-tab toggle, view source, bounded fetch/XHR request log and cookie/localStorage viewer. Do not log passwords, tokens or full sensitive payloads by default.
- Bundle all third-party runtime code and document update process. No launch-time dependency downloads.

## M4 — System-wide VPN

### Targets and storage

- NovaTunnel NEPacketTunnelProvider embedded at PlugIns/NovaTunnel.appex; NETunnelProviderManager preference load/create/save/start/stop/status observation in main app.
- Both targets receive packet-tunnel-provider Network Extension entitlement and group.com.example.novabrowser App Group. Share nonsecret configuration through group container; private keys/passwords only in appropriately shared Keychain access group. Keychain references passed to extension, no full configs in preferences, JSON, UserDefaults or logs.
- Extend build_tipa.sh to build app+extension, sign extension with its own entitlements first, then host, validate PlugIns layout. Compile both together. README verification of extension discovery/launch and system VPN state.

### Protocols and profiles

- Official WireGuardKit with pinned source and Go backend, vendored build dependencies or explicitly pinned package plus backend build. Strict standard .conf parser; paste, file picker and AVFoundation QR import. Clear malformed-config errors with secret redaction.
- Optional separate OpenVPN phase using pinned OpenVPNAdapter and .ovpn import, marked experimental behind Settings toggle; never pretend a WireGuard extension can open an OpenVPN config.
- Saved profiles show name, protocol, endpoint, last connected, duration and connecting/connected/reasserting/disconnected status with connect toggle.
- Provider templates open the provider's official configuration-download/help page in the browser: Proton VPN free, Cloudflare WARP, VPN Gate. Check current availability and protocol support; do not promise every provider exports standard WireGuard profiles. No scraping or bundling server lists, private keys or third-party credentials. Only explicitly imported user profiles may connect.

### Connection behavior

- Kill-switch option with includeAllNetworks/exclude-local choices where available and clear platform limitations. Exponential-backoff reconnect with cancellation and bounded delays.
- Custom DNS per profile (e.g. 1.1.1.1/9.9.9.9), DNS routed inside the tunnel. Full-tunnel IPv4 and IPv6 coverage necessary before calling it leak-protected; validate AllowedIPs and report split routes honestly.
- NEOnDemandRule generation for chosen domains/untrusted Wi-Fi, with rule-order and policy tests.
- Failed/unreachable pages offer Connect VPN and Retry only using an explicitly selected saved profile.
- User-initiated connection test for public IP, DNS resolver attribution and WebRTC exposure. Actual observed values only; report indeterminate results honestly. Disable browser WebRTC local-address exposure while VPN is active; explain that JavaScript wrappers alone cannot guarantee system-wide WebRTC enforcement.
- Latency measurements to user-saved endpoints; distinguish TCP reachability from UDP WireGuard handshake/latency. No invented pings.

### Safety, tests and documentation

- One-time notice: free VPNs can log or tamper with traffic; recommend reputable providers or self-hosting. No root CA or HTTPS interception. No traffic to unadded servers.
- Tests: strict WireGuard parser, invalid/duplicate keys, secret storage isolation, profile lifecycle and on-demand rule generation.
- README: setup, import, connect, extension-loading verification, troubleshooting, memory constraints (avoid claiming a fixed universal limit), TrollStore entitlement/registration differences, no App Store review, and possible registration/reinstall needs after supported OS changes. An unsupported OS update can remove TrollStore compatibility entirely.
- Network Extension behavior and kill-switch guarantees need physical-device proof on iOS 16; simulator-only evidence is insufficient.
