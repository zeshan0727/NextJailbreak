from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
router_path = root / "NextAgent/V071Router.swift"
v07_path = root / "NextAgent/V07Tools.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
router = router_path.read_text()
v07 = v07_path.read_text()
ui = modern_ui_path.read_text()

s = s.replace(
    "Next Agent 0.7.18 is ready with lifecycle-safe RootHide HUD startup and full-screen app automation.",
    "Next Agent 0.7.19 is ready with a SpringBoard-anchored system HUD and full-screen app automation."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.18-hud-lifecycle12"',
    'private static let currentToolSchemaVersion = "0.7.19-springboard-hud13"'
)
s = s.replace('"client_version": "0.7.18"', '"client_version": "0.7.19"')

router = router.replace(
    '"router_version": "0.7.18-hud-lifecycle12"',
    '"router_version": "0.7.19-springboard-hud13"'
)
router = router.replace('transportVersion == "0.7.18-cfmessageport1"', 'transportVersion == "0.7.19-cfmessageport1"')
router = router.replace('ocrTransportVersion == "0.7.18-springboard-vision1"', 'ocrTransportVersion == "0.7.19-springboard-vision1"')
router = router.replace('splitBridgeVersion == "0.7.18"', 'splitBridgeVersion == "0.7.19"')
router = router.replace('hidBridgeVersion == "0.7.18"', 'hidBridgeVersion == "0.7.19"')
router = router.replace('hudBridgeVersion == "0.7.18"', 'hudBridgeVersion == "0.7.19"')

old = '''        let tweakLoaded = (hudRaw["tweak_loaded"] as? Bool) == true
        let tweakReady = (hudRaw["tweak_window_ready"] as? Bool) == true
        let bootstrapTimedOut = (hudRaw["tweak_bootstrap_timed_out"] as? Bool) == true
        results.append([
            "tool": "status_hud_tweak",
            "success": hudBridgeVersion == "0.7.19" && tweakLoaded && tweakReady && !bootstrapTimedOut,
            "output": String(describing: hudRaw)
        ])
'''
new = '''        let sbHUDLoaded = (hudRaw["springboard_hud_tweak_loaded"] as? Bool) == true
        let sbHUDHost = (hudRaw["springboard_hud_host_found"] as? Bool) == true
        let sbHUDReady = (hudRaw["springboard_hud_view_ready"] as? Bool) == true
        results.append([
            "tool": "status_hud_springboard",
            "success": hudBridgeVersion == "0.7.19" && sbHUDLoaded && sbHUDHost && sbHUDReady,
            "output": String(describing: hudRaw)
        ])
'''
if old not in router:
    raise SystemExit("v0.7.19 HUD self-test marker missing")
router = router.replace(old, new, 1)

old_status = '''            let loaded = (check["tweak_loaded"] as? Bool) == true
            let ready = (check["tweak_window_ready"] as? Bool) == true
            self.status = loaded && ready
                ? "HUD tweak loaded — test should be visible"
                : "HUD tweak not injected — run Self Test for details"
'''
new_status = '''            let loaded = (check["springboard_hud_tweak_loaded"] as? Bool) == true
            let host = (check["springboard_hud_host_found"] as? Bool) == true
            let ready = (check["springboard_hud_view_ready"] as? Bool) == true
            self.status = loaded && host && ready
                ? "SpringBoard HUD ready — test should be visible"
                : "SpringBoard HUD host unavailable — run Self Test"
'''
if old_status not in s:
    raise SystemExit("v0.7.19 Show HUD status marker missing")
s = s.replace(old_status, new_status, 1)

v07 = v07.replace('"input_path": "springboard_iohid_v0718"', '"input_path": "springboard_iohid_v0719"')

ui = ui.replace(
    "0.7.18 • RootHide • Lifecycle-Safe HUD • Full-Screen Apps",
    "0.7.19 • RootHide • SpringBoard HUD • Full-Screen Apps"
)
ui = ui.replace(
    "Broadcasts a direct HUD test and verifies both injection and UIWindowScene readiness. The 0.7.18 HUD retries startup through application and scene lifecycle events so early TrollStore injection cannot miss the active scene.",
    "Broadcasts a direct HUD test to a dedicated SpringBoard tweak. The HUD is now anchored to SpringBoard's status-bar/window surface instead of creating a UIWindow inside Next Agent or the foreground app."
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text().replace("MARKETING_VERSION: 0.7.18", "MARKETING_VERSION: 0.7.19").replace("CURRENT_PROJECT_VERSION: 26", "CURRENT_PROJECT_VERSION: 27")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.19"
d["CFBundleVersion"] = "27"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.19-springboard-hud13"' in swift_path.read_text()
assert '"router_version": "0.7.19-springboard-hud13"' in router_path.read_text()
assert "status_hud_springboard" in router_path.read_text()
assert "springboard_iohid_v0719" in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.19" in project.read_text()
