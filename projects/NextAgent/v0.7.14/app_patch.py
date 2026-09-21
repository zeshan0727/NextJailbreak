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

# ----- version -----
s = s.replace(
    "Next Agent 0.7.13 is ready with native SpringBoard HUD status and precision tap OCR.",
    "Next Agent 0.7.14 is ready with dual-layer task status and deeper HUD/background diagnostics."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.13-nativehud-tap7"',
    'private static let currentToolSchemaVersion = "0.7.14-dualhud-bgdiag8"'
)
s = s.replace('"client_version": "0.7.13"', '"client_version": "0.7.14"')

router = router.replace(
    '"router_version": "0.7.13-nativehud-tap7"',
    '"router_version": "0.7.14-dualhud-bgdiag8"'
)
router = router.replace(
    'transportVersion == "0.7.13-cfmessageport1"',
    'transportVersion == "0.7.14-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.13-springboard-vision1"',
    'ocrTransportVersion == "0.7.14-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.13"',
    'splitBridgeVersion == "0.7.14"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.13"',
    'hidBridgeVersion == "0.7.14"'
)

# v0.7.14 accepts either the native SpringBoard HUD or the packaged per-app HUD fallback.
old_hud = '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        results.append([
            "tool": "native_status_hud",
            "success": (hudRaw["success"] as? Bool) == true
                && (hudRaw["hud_view_controller_class_available"] as? Bool) == true
                && hudBridgeVersion == "0.7.13",
            "output": String(describing: hudRaw)
        ])

'''
new_hud = '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        let nativeHUD = (hudRaw["success"] as? Bool) == true
        let fallbackExpected = (hudRaw["foreground_hud_fallback_expected"] as? Bool) == true
        results.append([
            "tool": "status_hud_stack",
            "success": hudBridgeVersion == "0.7.14" && (nativeHUD || fallbackExpected),
            "output": String(describing: hudRaw)
        ])

'''
if old_hud not in router:
    raise SystemExit("v0.7.14 HUD self-test marker missing")
router = router.replace(old_hud, new_hud, 1)

# Keep diagnostic output explicit about native HUD failure vs foreground-app fallback.
anchor = '''              When the user explicitly asks to navigate through an app UI (for example Settings → General → About), that visible UI route is part of the requested task. If a requested screen or row cannot be opened, do not substitute phone_status/device_info or another diagnostic source and then claim the UI task succeeded. Diagnostic tools may be used only to troubleshoot or provide clearly labeled secondary information; report the requested UI route as incomplete until the visible destination is reached and verified. phone_screen tap_text uses Accurate OCR for the actual tap target even though read/find/wait operations remain optimized for speed.
'''
extra = anchor + '''              Task status is provided by a dual HUD stack: native SpringBoard HUD when available, otherwise a foreground-app HUD injected into the currently active UIKit app. Do not treat native HUD unavailability by itself as task failure.
'''
if anchor not in s:
    raise SystemExit("v0.7.14 instruction anchor missing")
s = s.replace(anchor, extra, 1)

v07 = v07.replace('"input_path": "springboard_iohid_v0713"', '"input_path": "springboard_iohid_v0714"')

ui = ui.replace(
    "0.7.13 • RootHide • Native HUD • Precision Tap",
    "0.7.14 • RootHide • Dual HUD • Background Diagnostics"
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.13", "MARKETING_VERSION: 0.7.14")
y = y.replace("CURRENT_PROJECT_VERSION: 21", "CURRENT_PROJECT_VERSION: 22")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.14"
d["CFBundleVersion"] = "22"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.14-dualhud-bgdiag8"' in swift_path.read_text()
assert '"router_version": "0.7.14-dualhud-bgdiag8"' in router_path.read_text()
assert "status_hud_stack" in router_path.read_text()
assert "foreground_hud_fallback_expected" in router_path.read_text()
assert "springboard_iohid_v0714" in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.14" in project.read_text()
