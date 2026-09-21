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
    "Next Agent 0.7.12 is ready with a system-wide SpringBoard status HUD and faster screen navigation.",
    "Next Agent 0.7.13 is ready with native SpringBoard HUD status and precision tap OCR."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.12-status-perf6"',
    'private static let currentToolSchemaVersion = "0.7.13-nativehud-tap7"'
)
s = s.replace('"client_version": "0.7.12"', '"client_version": "0.7.13"')

router = router.replace(
    '"router_version": "0.7.12-status-perf6"',
    '"router_version": "0.7.13-nativehud-tap7"'
)
router = router.replace(
    'transportVersion == "0.7.12-cfmessageport1"',
    'transportVersion == "0.7.13-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.12-springboard-vision1"',
    'ocrTransportVersion == "0.7.13-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.12"',
    'splitBridgeVersion == "0.7.13"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.12"',
    'hidBridgeVersion == "0.7.13"'
)

# ----- precision: actual taps go back to Accurate Vision OCR -----
tap_start = v07.find('    private func v07TapText(_ args: [String: Any]) -> ToolResult {')
tap_end = v07.find('    private func v07WaitForText(_ args: [String: Any], shouldAppear: Bool) async -> ToolResult {', tap_start)
if tap_start < 0 or tap_end < 0:
    raise SystemExit("v0.7.13 tap_text bounds missing")
tap_segment = v07[tap_start:tap_end]
if 'fast: true,' not in tap_segment:
    raise SystemExit("v0.7.13 expected v0.7.12 fast tap OCR marker missing")
tap_segment = tap_segment.replace('fast: true,', 'fast: false,', 1)
tap_segment = tap_segment.replace(
    '"input_path": "springboard_iohid_v0712"',
    '"input_path": "springboard_iohid_v0713"'
)
v07 = v07[:tap_start] + tap_segment + v07[tap_end:]

# Keep any remaining explicit v0.7.12 HID label current without changing the HID implementation.
v07 = v07.replace('"input_path": "springboard_iohid_v0712"', '"input_path": "springboard_iohid_v0713"')

# ----- self test now verifies native HUD bridge availability -----
hid_test = '''        let hidBridgeRaw = NAScreenBridgeClient.hidStatus()
        let hidBridgeVersion = hidBridgeRaw["bridge_version"] as? String ?? ""
        results.append([
            "tool": "springboard_hid_bridge",
            "success": (hidBridgeRaw["success"] as? Bool) == true
                && (hidBridgeRaw["touch_client"] as? Bool) == true
                && (hidBridgeRaw["keyboard_admin_client"] as? Bool) == true
                && hidBridgeVersion == "0.7.13",
            "output": String(describing: hidBridgeRaw)
        ])

'''
if hid_test not in router:
    raise SystemExit("v0.7.13 HID self-test marker missing after version bump")
hud_test = hid_test + '''        let hudRaw = NAScreenBridgeClient.hudStatus()
        let hudBridgeVersion = hudRaw["bridge_version"] as? String ?? ""
        results.append([
            "tool": "native_status_hud",
            "success": (hudRaw["success"] as? Bool) == true
                && (hudRaw["hud_view_controller_class_available"] as? Bool) == true
                && hudBridgeVersion == "0.7.13",
            "output": String(describing: hudRaw)
        ])

'''
router = router.replace(hid_test, hud_test, 1)

# ----- completion policy: do not substitute diagnostics for requested UI navigation -----
anchor = '''              For speed, when the target label is already known, use phone_screen find_text/tap_text directly instead of describe_screen followed by another OCR call. Prefer wait_text/wait_text_gone after an interaction instead of fixed sleeps or repeated full-screen descriptions. Routine navigation should use Fast OCR; use accurate OCR only when Fast OCR cannot resolve the requested text. Verify the requested final outcome once before reporting success; avoid redundant verification after it is confirmed.
'''
policy = anchor + '''              When the user explicitly asks to navigate through an app UI (for example Settings → General → About), that visible UI route is part of the requested task. If a requested screen or row cannot be opened, do not substitute phone_status/device_info or another diagnostic source and then claim the UI task succeeded. Diagnostic tools may be used only to troubleshoot or provide clearly labeled secondary information; report the requested UI route as incomplete until the visible destination is reached and verified. phone_screen tap_text uses Accurate OCR for the actual tap target even though read/find/wait operations remain optimized for speed.
'''
if anchor not in s:
    raise SystemExit("v0.7.13 policy anchor missing")
s = s.replace(anchor, policy, 1)

ui = ui.replace(
    "0.7.12 • RootHide • System HUD • Fast OCR",
    "0.7.13 • RootHide • Native HUD • Precision Tap"
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.12", "MARKETING_VERSION: 0.7.13")
y = y.replace("CURRENT_PROJECT_VERSION: 20", "CURRENT_PROJECT_VERSION: 21")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.13"
d["CFBundleVersion"] = "21"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.13-nativehud-tap7"' in swift_path.read_text()
assert '"router_version": "0.7.13-nativehud-tap7"' in router_path.read_text()
assert "NAScreenBridgeClient.hudStatus()" in router_path.read_text()
assert "native_status_hud" in router_path.read_text()
assert "fast: false" in v07_path.read_text()
assert "springboard_iohid_v0713" in v07_path.read_text()
assert "do not substitute phone_status/device_info" in swift_path.read_text()
assert "MARKETING_VERSION: 0.7.13" in project.read_text()
