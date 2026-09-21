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

# Version bump from cumulative v0.7.16.
s = s.replace(
    "Next Agent 0.7.16 is ready with a standalone system-wide HUD tweak and reliable full-screen app automation.",
    "Next Agent 0.7.17 is ready with a verified RootHide HUD injection stack and full-screen app automation."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.16-hudtweak-fullscreen10"',
    'private static let currentToolSchemaVersion = "0.7.17-huddiag-exactbundle11"'
)
s = s.replace('"client_version": "0.7.16"', '"client_version": "0.7.17"')

router = router.replace(
    '"router_version": "0.7.16-hudtweak-fullscreen10"',
    '"router_version": "0.7.17-huddiag-exactbundle11"'
)
router = router.replace(
    'transportVersion == "0.7.16-cfmessageport1"',
    'transportVersion == "0.7.17-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.16-springboard-vision1"',
    'ocrTransportVersion == "0.7.17-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.16"',
    'splitBridgeVersion == "0.7.17"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.16"',
    'hidBridgeVersion == "0.7.17"'
)
router = router.replace(
    'hudBridgeVersion == "0.7.16"',
    'hudBridgeVersion == "0.7.17"'
)
v07 = v07.replace(
    '"input_path": "springboard_iohid_v0716"',
    '"input_path": "springboard_iohid_v0717"'
)

# Manual Show HUD now uses a direct SpringBoard broadcast instead of relying on
# the daemon progress path. This isolates tweak injection from task execution.
old_test = '''    func testSystemHUD() {
        _ = NAScreenBridgeClient.closeSplitWorkspace()
        status = "Testing system-wide HUD…"
        publishProgress(
            state: "working",
            message: "HUD test • visible system-wide",
            progress: 0.42,
            returnToApp: false
        )

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard let self else { return }
            self.publishProgress(
                state: "complete",
                message: "HUD test complete",
                progress: 1.0,
                returnToApp: false
            )
            self.status = "HUD test complete"
        }
    }
'''
new_test = '''    func testSystemHUD() {
        _ = NAScreenBridgeClient.closeSplitWorkspace()
        status = "Broadcasting HUD test…"
        let result = NAScreenBridgeClient.hudTest()
        guard (result["success"] as? Bool) == true else {
            status = "HUD test bridge failed"
            return
        }

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard let self else { return }
            let check = NAScreenBridgeClient.hudStatus()
            let loaded = (check["tweak_loaded"] as? Bool) == true
            let ready = (check["tweak_window_ready"] as? Bool) == true
            self.status = loaded && ready
                ? "HUD tweak loaded — test should be visible"
                : "HUD tweak not injected — run Self Test for details"
        }
    }
'''
if old_test not in s:
    raise SystemExit("v0.7.17 testSystemHUD marker missing")
s = s.replace(old_test, new_test, 1)

# Self-test must prove actual tweak injection, not merely "fallback expected".
old_hud = '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        let nativeHUD = (hudRaw["success"] as? Bool) == true
        let fallbackExpected = (hudRaw["foreground_hud_fallback_expected"] as? Bool) == true
        results.append([
            "tool": "status_hud_stack",
            "success": hudBridgeVersion == "0.7.17" && (nativeHUD || fallbackExpected),
            "output": String(describing: hudRaw)
        ])

'''
new_hud = '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        let tweakLoaded = (hudRaw["tweak_loaded"] as? Bool) == true
        let tweakReady = (hudRaw["tweak_window_ready"] as? Bool) == true
        results.append([
            "tool": "status_hud_tweak",
            "success": hudBridgeVersion == "0.7.17" && tweakLoaded && tweakReady,
            "output": String(describing: hudRaw)
        ])

'''
if old_hud not in router:
    raise SystemExit("v0.7.17 HUD self-test marker missing")
router = router.replace(old_hud, new_hud, 1)

ui = ui.replace(
    "0.7.16 • RootHide • System HUD Tweak • Full-Screen Apps",
    "0.7.17 • RootHide • Verified HUD Tweak • Full-Screen Apps"
)
ui = ui.replace(
    "Displays the standalone RootHide HUD tweak in Next Agent. The same HUD follows active tasks into other UIKit apps.",
    "Broadcasts a direct HUD test and verifies that the exact-bundle RootHide HUD tweak is injected into Next Agent. The system HUD copy follows active tasks into other UIKit apps."
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.16", "MARKETING_VERSION: 0.7.17")
y = y.replace("CURRENT_PROJECT_VERSION: 24", "CURRENT_PROJECT_VERSION: 25")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.17"
d["CFBundleVersion"] = "25"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.17-huddiag-exactbundle11"' in swift_path.read_text()
assert '"router_version": "0.7.17-huddiag-exactbundle11"' in router_path.read_text()
assert "NAScreenBridgeClient.hudTest()" in swift_path.read_text()
assert "status_hud_tweak" in router_path.read_text()
assert "springboard_iohid_v0717" in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.17" in project.read_text()
