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

# Incremental update from cumulative v0.7.17.
s = s.replace(
    "Next Agent 0.7.17 is ready with a verified RootHide HUD injection stack and full-screen app automation.",
    "Next Agent 0.7.18 is ready with lifecycle-safe RootHide HUD startup and full-screen app automation."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.17-huddiag-exactbundle11"',
    'private static let currentToolSchemaVersion = "0.7.18-hud-lifecycle12"'
)
s = s.replace('"client_version": "0.7.17"', '"client_version": "0.7.18"')

router = router.replace(
    '"router_version": "0.7.17-huddiag-exactbundle11"',
    '"router_version": "0.7.18-hud-lifecycle12"'
)
router = router.replace(
    'transportVersion == "0.7.17-cfmessageport1"',
    'transportVersion == "0.7.18-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.17-springboard-vision1"',
    'ocrTransportVersion == "0.7.18-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.17"',
    'splitBridgeVersion == "0.7.18"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.17"',
    'hidBridgeVersion == "0.7.18"'
)
router = router.replace(
    'hudBridgeVersion == "0.7.17"',
    'hudBridgeVersion == "0.7.18"'
)

old_hud = '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        let tweakLoaded = (hudRaw["tweak_loaded"] as? Bool) == true
        let tweakReady = (hudRaw["tweak_window_ready"] as? Bool) == true
        results.append([
            "tool": "status_hud_tweak",
            "success": hudBridgeVersion == "0.7.18" && tweakLoaded && tweakReady,
            "output": String(describing: hudRaw)
        ])

'''
new_hud = '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        let tweakLoaded = (hudRaw["tweak_loaded"] as? Bool) == true
        let tweakReady = (hudRaw["tweak_window_ready"] as? Bool) == true
        let bootstrapTimedOut = (hudRaw["tweak_bootstrap_timed_out"] as? Bool) == true
        results.append([
            "tool": "status_hud_tweak",
            "success": hudBridgeVersion == "0.7.18" && tweakLoaded && tweakReady && !bootstrapTimedOut,
            "output": String(describing: hudRaw)
        ])

'''
if old_hud not in router:
    raise SystemExit("v0.7.18 cumulative HUD self-test marker missing")
router = router.replace(old_hud, new_hud, 1)

v07 = v07.replace(
    '"input_path": "springboard_iohid_v0717"',
    '"input_path": "springboard_iohid_v0718"'
)

ui = ui.replace(
    "0.7.17 • RootHide • Verified HUD Tweak • Full-Screen Apps",
    "0.7.18 • RootHide • Lifecycle-Safe HUD • Full-Screen Apps"
)
ui = ui.replace(
    "Broadcasts a direct HUD test and verifies that the exact-bundle RootHide HUD tweak is injected into Next Agent. The system HUD copy follows active tasks into other UIKit apps.",
    "Broadcasts a direct HUD test and verifies both injection and UIWindowScene readiness. The 0.7.18 HUD retries startup through application and scene lifecycle events so early TrollStore injection cannot miss the active scene."
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.17", "MARKETING_VERSION: 0.7.18")
y = y.replace("CURRENT_PROJECT_VERSION: 25", "CURRENT_PROJECT_VERSION: 26")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.18"
d["CFBundleVersion"] = "26"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.18-hud-lifecycle12"' in swift_path.read_text()
assert '"router_version": "0.7.18-hud-lifecycle12"' in router_path.read_text()
assert "tweak_bootstrap_timed_out" in router_path.read_text()
assert "springboard_iohid_v0718" in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.18" in project.read_text()
