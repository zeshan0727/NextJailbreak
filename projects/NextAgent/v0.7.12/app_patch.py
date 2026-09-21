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
    "Next Agent 0.7.11 is ready with SpringBoard-native touch and keyboard injection.",
    "Next Agent 0.7.12 is ready with a system-wide SpringBoard status HUD and faster screen navigation."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.11-sbocr-hid5"',
    'private static let currentToolSchemaVersion = "0.7.12-status-perf6"'
)
s = s.replace('"client_version": "0.7.11"', '"client_version": "0.7.12"')

router = router.replace(
    '"router_version": "0.7.11-sbocr-hid5"',
    '"router_version": "0.7.12-status-perf6"'
)
router = router.replace(
    'transportVersion == "0.7.11-cfmessageport1"',
    'transportVersion == "0.7.12-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.11-springboard-vision1"',
    'ocrTransportVersion == "0.7.12-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.11"',
    'splitBridgeVersion == "0.7.12"'
)
router = router.replace(
    'hidBridgeVersion == "0.7.11"',
    'hidBridgeVersion == "0.7.12"'
)

# ----- performance: routine UI navigation uses proven fast OCR -----
def patch_function(text, start_marker, end_marker, replacements):
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"v0.7.12 function start missing: {start_marker}")
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"v0.7.12 function end missing: {end_marker}")
    segment = text[start:end]
    for old, new in replacements:
        if old not in segment:
            raise SystemExit(f"v0.7.12 marker missing in {start_marker}: {old}")
        segment = segment.replace(old, new, 1)
    return text[:start] + segment + text[end:]

v07 = patch_function(
    v07,
    '    private func v07DescribeScreen() -> ToolResult {',
    '    private func v078NormalizedText',
    [('fast: false,', 'fast: true,')]
)
v07 = patch_function(
    v07,
    '    private func v07FindText(_ args: [String: Any]) -> ToolResult {',
    '    private func v07TapText(_ args: [String: Any]) -> ToolResult {',
    [('fast: false,', 'fast: true,')]
)
v07 = patch_function(
    v07,
    '    private func v07TapText(_ args: [String: Any]) -> ToolResult {',
    '    private func v07WaitForText(_ args: [String: Any], shouldAppear: Bool) async -> ToolResult {',
    [('fast: false,', 'fast: true,')]
)
v07 = v07.replace(
    'try? await Task.sleep(nanoseconds: 550_000_000)',
    'try? await Task.sleep(nanoseconds: 250_000_000)'
)
v07 = v07.replace(
    '"input_path": "springboard_iohid_v0711"',
    '"input_path": "springboard_iohid_v0712"'
)

# Split scene readiness polling was intentionally conservative in 0.7.10.
router = router.replace(
    'try? await Task.sleep(nanoseconds: 250_000_000)',
    'try? await Task.sleep(nanoseconds: 150_000_000)'
)

# ----- status heartbeat while the model is reasoning between tool calls -----
record_start = s.find('    func recordTool(_ name: String, _ result: ToolResult) {')
record_end = s.find('    private func currentProgressEstimate()', record_start)
if record_start < 0 or record_end < 0:
    raise SystemExit("v0.7.12 recordTool bounds missing")
record_segment = s[record_start:record_end]
needle = '''        publishProgress(
            state: "working",
            message: result.success ? "\\(label) ✓" : "\\(label) — retrying",
            progress: min(0.92, currentProgressEstimate() + 0.025),
            returnToApp: activeReturnToApp
        )
'''
replacement = needle + '''        if result.success {
            let completedStep = progressStepCount
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard let self,
                      self.busy,
                      self.progressStepCount == completedStep else { return }
                self.publishProgress(
                    state: "working",
                    message: "Thinking…",
                    progress: min(0.94, self.currentProgressEstimate() + 0.03),
                    returnToApp: self.activeReturnToApp
                )
            }
        }
'''
if needle not in record_segment:
    raise SystemExit("v0.7.12 recordTool progress marker missing")
record_segment = record_segment.replace(needle, replacement, 1)
s = s[:record_start] + record_segment + s[record_end:]

# ----- agent policy: fewer redundant OCR calls/waits, one final verification -----
instruction = '''              Touch and keyboard actions are dispatched by the SpringBoard HID bridge. A successful dispatch is not proof that the UI changed: after type_text, tap, or press_key, verify the expected visible result with phone_screen/OCR before claiming completion. For typing diagnostics, the Next Agent composer itself is the first acceptance target before attempting Notes.
'''
speed_instruction = instruction + '''              For speed, when the target label is already known, use phone_screen find_text/tap_text directly instead of describe_screen followed by another OCR call. Prefer wait_text/wait_text_gone after an interaction instead of fixed sleeps or repeated full-screen descriptions. Routine navigation should use Fast OCR; use accurate OCR only when Fast OCR cannot resolve the requested text. Verify the requested final outcome once before reporting success; avoid redundant verification after it is confirmed.
'''
if instruction not in s:
    raise SystemExit("v0.7.12 speed instruction anchor missing")
s = s.replace(instruction, speed_instruction, 1)

ui = ui.replace(
    "0.7.11 • RootHide • SpringBoard HID • System Theme",
    "0.7.12 • RootHide • System HUD • Fast OCR"
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.11", "MARKETING_VERSION: 0.7.12")
y = y.replace("CURRENT_PROJECT_VERSION: 19", "CURRENT_PROJECT_VERSION: 20")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.12"
d["CFBundleVersion"] = "20"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.12-status-perf6"' in swift_path.read_text()
assert '"router_version": "0.7.12-status-perf6"' in router_path.read_text()
assert "Thinking…" in swift_path.read_text()
assert "springboard_iohid_v0712" in v07_path.read_text()
assert "fast: true" in v07_path.read_text()
assert "250_000_000" in v07_path.read_text()
assert "150_000_000" in router_path.read_text()
assert "MARKETING_VERSION: 0.7.12" in project.read_text()
