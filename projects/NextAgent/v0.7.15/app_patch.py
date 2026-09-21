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

# v0.7.15 is applied after the cumulative v0.7.14 patch.
s = s.replace(
    "Next Agent 0.7.14 is ready with dual-layer task status and deeper HUD/background diagnostics.",
    "Next Agent 0.7.15 is ready with an in-app HUD verification probe and SpringBoard scene-manager recovery for app launches."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.14-dualhud-bgdiag8"',
    'private static let currentToolSchemaVersion = "0.7.15-hudprobe-scenes9"'
)
s = s.replace('"client_version": "0.7.14"', '"client_version": "0.7.15"')

router = router.replace(
    '"router_version": "0.7.14-dualhud-bgdiag8"',
    '"router_version": "0.7.15-hudprobe-scenes9"'
)
router = router.replace(
    'transportVersion == "0.7.14-cfmessageport1"',
    'transportVersion == "0.7.15-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.14-springboard-vision1"',
    'ocrTransportVersion == "0.7.15-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.14"',
    'splitBridgeVersion == "0.7.15"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.14"',
    'hidBridgeVersion == "0.7.15"'
)
router = router.replace(
    'let deadline = Date().addingTimeInterval(9.0)',
    'let deadline = Date().addingTimeInterval(12.0)'
)

# The existing v0.7.14 HUD-stack self-test remains valid; require the new generation.
router = router.replace(
    'hudBridgeVersion == "0.7.14"',
    'hudBridgeVersion == "0.7.15"'
)

# Preserve the proven HID implementation and only move the diagnostic path label.
v07 = v07.replace(
    '"input_path": "springboard_iohid_v0714"',
    '"input_path": "springboard_iohid_v0715"'
)

instruction = '''              Task status is provided by a dual HUD stack: native SpringBoard HUD when available, otherwise a foreground-app HUD injected into the currently active UIKit app. Do not treat native HUD unavailability by itself as task failure.
'''
extra = instruction + '''              The foreground HUD is also injected into Next Agent itself. A short "HUD ready" probe may appear when Next Agent launches; during an active task the same HUD should continue showing status before and after opening another app.
'''
if instruction not in s:
    raise SystemExit("v0.7.15 HUD instruction anchor missing")
s = s.replace(instruction, extra, 1)

ui = ui.replace(
    "0.7.14 • RootHide • Dual HUD • Background Diagnostics",
    "0.7.15 • RootHide • HUD Probe • Scene Recovery"
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.14", "MARKETING_VERSION: 0.7.15")
y = y.replace("CURRENT_PROJECT_VERSION: 22", "CURRENT_PROJECT_VERSION: 23")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.15"
d["CFBundleVersion"] = "23"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.15-hudprobe-scenes9"' in swift_path.read_text()
assert '"router_version": "0.7.15-hudprobe-scenes9"' in router_path.read_text()
assert "HUD ready" in swift_path.read_text()
assert "springboard_iohid_v0715" in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.15" in project.read_text()
