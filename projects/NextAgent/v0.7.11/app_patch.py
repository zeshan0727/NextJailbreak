from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
router_path = root / "NextAgent/V071Router.swift"
v05_path = root / "NextAgent/V05Tools.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"

s = swift_path.read_text()
router = router_path.read_text()
v05 = v05_path.read_text()
ui = modern_ui_path.read_text()

# ----- version -----
s = s.replace(
    "Next Agent 0.7.10 is ready with asynchronous split workspace, resilient OCR, and System / Light / Dark appearance.",
    "Next Agent 0.7.11 is ready with SpringBoard-native touch and keyboard injection."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.10-sbocr-split4"',
    'private static let currentToolSchemaVersion = "0.7.11-sbocr-hid5"'
)
s = s.replace('"client_version": "0.7.10"', '"client_version": "0.7.11"')
router = router.replace(
    '"router_version": "0.7.10-sbocr-split4"',
    '"router_version": "0.7.11-sbocr-hid5"'
)
router = router.replace(
    'transportVersion == "0.7.10-cfmessageport1"',
    'transportVersion == "0.7.11-cfmessageport1"'
)
router = router.replace(
    'ocrTransportVersion == "0.7.10-springboard-vision1"',
    'ocrTransportVersion == "0.7.11-springboard-vision1"'
)
router = router.replace(
    'splitBridgeVersion == "0.7.10"',
    'splitBridgeVersion == "0.7.11"'
)

# ----- route interactive input through the injected SpringBoard bridge -----
v05 = v05.replace(
    'tool("hid_status", "Check whether the RootHide global touch and keyboard injection service is available.", [:])',
    'tool("hid_status", "Check the SpringBoard-native touch and Admin keyboard injection bridge. Read-only; does not generate input.", [:])'
)
v05 = v05.replace(
    'tool("type_text", "Enter text into the currently focused field by temporarily placing the text on the clipboard and dispatching the system Paste keyboard shortcut. The previous clipboard is restored. Requires Sensitive Actions. Never use for passwords, passcodes, authentication tokens, banking/payment credentials or private keys.",',
    'tool("type_text", "Enter text into the currently focused field through SpringBoard-native HID keyboard events. Unicode falls back to clipboard plus a SpringBoard Cmd+V shortcut. Requires Sensitive Actions. Never use for passwords, passcodes, authentication tokens, banking/payment credentials or private keys.",'
)

v05 = v05.replace(
    '        case "hid_status":\n            return RootDaemonClient.request(action: "hid_status")',
    '        case "hid_status":\n            return v0511BridgeResult(NAScreenBridgeClient.hidStatus())'
)
v05 = v05.replace(
    '''        case "press_key":
            guard allowSensitive else { return v05SensitiveOff() }
            guard let key = arguments["key"] as? String else { return v05BadArgs() }
            return RootDaemonClient.request(action: "key", argument: key.lowercased())
''',
    '''        case "press_key":
            guard allowSensitive else { return v05SensitiveOff() }
            guard let key = arguments["key"] as? String else { return v05BadArgs() }
            return v0511BridgeResult(NAScreenBridgeClient.hidPressKey(key.lowercased()))
'''
)

old_point = '''    private func v05Point(action: String, args: [String: Any]) -> ToolResult {
        guard let x = v05Normalized(args["x"]), let y = v05Normalized(args["y"]) else { return v05BadArgs() }
        return RootDaemonClient.request(action: action, argument: String(format: "%.6f,%.6f", x, y))
    }
'''
new_point = '''    private func v05Point(action: String, args: [String: Any]) -> ToolResult {
        guard let x = v05Normalized(args["x"]), let y = v05Normalized(args["y"]) else { return v05BadArgs() }
        let count = action == "double_tap" ? 2 : 1
        return v0511BridgeResult(NAScreenBridgeClient.hidTap(x: x, y: y, count: count))
    }
'''
if old_point not in v05:
    raise SystemExit("v0.7.11 point helper marker missing")
v05 = v05.replace(old_point, new_point, 1)

old_long = '''    private func v05LongPress(_ args: [String: Any]) -> ToolResult {
        guard let x = v05Normalized(args["x"]), let y = v05Normalized(args["y"]) else { return v05BadArgs() }
        let duration = max(0.2, min(8.0, (args["duration"] as? NSNumber)?.doubleValue ?? 0.8))
        return RootDaemonClient.request(action: "long_press", argument: String(format: "%.6f,%.6f,%.3f", x, y, duration))
    }
'''
new_long = '''    private func v05LongPress(_ args: [String: Any]) -> ToolResult {
        guard let x = v05Normalized(args["x"]), let y = v05Normalized(args["y"]) else { return v05BadArgs() }
        let duration = max(0.2, min(8.0, (args["duration"] as? NSNumber)?.doubleValue ?? 0.8))
        return v0511BridgeResult(NAScreenBridgeClient.hidLongPress(x: x, y: y, duration: duration))
    }
'''
if old_long not in v05:
    raise SystemExit("v0.7.11 long press marker missing")
v05 = v05.replace(old_long, new_long, 1)

old_swipe = '''    private func v05Swipe(_ args: [String: Any]) -> ToolResult {
        guard
            let x1 = v05Normalized(args["x1"]), let y1 = v05Normalized(args["y1"]),
            let x2 = v05Normalized(args["x2"]), let y2 = v05Normalized(args["y2"])
        else { return v05BadArgs() }
        let duration = max(0.1, min(5.0, (args["duration"] as? NSNumber)?.doubleValue ?? 0.5))
        return RootDaemonClient.request(action: "swipe", argument: String(format: "%.6f,%.6f,%.6f,%.6f,%.3f", x1, y1, x2, y2, duration))
    }
'''
new_swipe = '''    private func v05Swipe(_ args: [String: Any]) -> ToolResult {
        guard
            let x1 = v05Normalized(args["x1"]), let y1 = v05Normalized(args["y1"]),
            let x2 = v05Normalized(args["x2"]), let y2 = v05Normalized(args["y2"])
        else { return v05BadArgs() }
        let duration = max(0.1, min(5.0, (args["duration"] as? NSNumber)?.doubleValue ?? 0.5))
        return v0511BridgeResult(
            NAScreenBridgeClient.hidSwipe(x1: x1, y1: y1, x2: x2, y2: y2, duration: duration)
        )
    }
'''
if old_swipe not in v05:
    raise SystemExit("v0.7.11 swipe marker missing")
v05 = v05.replace(old_swipe, new_swipe, 1)

old_type = '''    @MainActor
    private func v05TypeText(_ args: [String: Any]) async -> ToolResult {
        guard let text = args["text"] as? String, !text.isEmpty, text.utf8.count <= 32_000 else { return v05BadArgs() }
        let pasteboard = UIPasteboard.general
        let previousItems = pasteboard.items
        pasteboard.string = text
        let result = RootDaemonClient.request(action: "paste")
        try? await Task.sleep(nanoseconds: 350_000_000)
        pasteboard.items = previousItems
        return result.success ? ToolResult(success: true, output: "Entered \(text.count) characters") : result
    }
'''
new_type = '''    private func v0511CanDirectType(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            scalar.value == 9 || scalar.value == 10 || scalar.value == 13 ||
            (scalar.value >= 32 && scalar.value <= 126)
        }
    }

    @MainActor
    private func v05TypeText(_ args: [String: Any]) async -> ToolResult {
        guard let text = args["text"] as? String, !text.isEmpty, text.utf8.count <= 32_000 else {
            return v05BadArgs()
        }

        if text.count <= 4096 && v0511CanDirectType(text) {
            let direct = NAScreenBridgeClient.hidTypeText(text)
            let result = v0511BridgeResult(direct)
            if result.success {
                return ToolResult(
                    success: true,
                    output: "Dispatched \(text.count) characters through SpringBoard HID keyboard; verify the field with screen OCR."
                )
            }
            return result
        }

        let pasteboard = UIPasteboard.general
        let previousItems = pasteboard.items
        pasteboard.string = text
        try? await Task.sleep(nanoseconds: 220_000_000)

        let result = v0511BridgeResult(NAScreenBridgeClient.hidPasteShortcut())
        try? await Task.sleep(nanoseconds: 550_000_000)
        pasteboard.items = previousItems

        return result.success
            ? ToolResult(success: true, output: "Dispatched Unicode text through SpringBoard HID paste shortcut; verify with screen OCR.")
            : result
    }
'''
if old_type not in v05:
    raise SystemExit("v0.7.11 type_text marker missing")
v05 = v05.replace(old_type, new_type, 1)

# ui_automation press_key must use the same SpringBoard path.
v05 = v05.replace(
    'result = RootDaemonClient.request(action: "key", argument: key.lowercased())',
    'result = v0511BridgeResult(NAScreenBridgeClient.hidPressKey(key.lowercased()))'
)

# Generic NSDictionary -> ToolResult adapter.
helper_marker = '''    private func v05JSON(_ object: Any) -> ToolResult {
'''
bridge_helper = '''    private func v0511BridgeResult(_ raw: Any) -> ToolResult {
        let dictionary: [AnyHashable: Any]
        if let value = raw as? [AnyHashable: Any] {
            dictionary = value
        } else if let value = raw as? NSDictionary {
            dictionary = value as? [AnyHashable: Any] ?? [:]
        } else {
            return ToolResult(success: false, output: String(describing: raw))
        }

        let success = (dictionary["success"] as? Bool) ?? false
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted]),
              let output = String(data: data, encoding: .utf8) else {
            return ToolResult(success: success, output: String(describing: dictionary))
        }
        return ToolResult(success: success, output: output)
    }

'''
if helper_marker not in v05:
    raise SystemExit("v0.7.11 V05 helper insertion marker missing")
v05 = v05.replace(helper_marker, bridge_helper + helper_marker, 1)

# ----- self-test: distinguish symbol creation from the real SpringBoard HID transport -----
split_test = '''        let splitCapabilityRaw = NAScreenBridgeClient.splitCapabilities()
        let splitBridgeVersion = splitCapabilityRaw["bridge_version"] as? String ?? ""
        results.append([
            "tool": "split_workspace_capability",
            "success": (splitCapabilityRaw["success"] as? Bool) == true
                && splitBridgeVersion == "0.7.11",
            "output": String(describing: splitCapabilityRaw)
        ])

'''
hid_test = split_test + '''        let hidBridgeRaw = NAScreenBridgeClient.hidStatus()
        let hidBridgeVersion = hidBridgeRaw["bridge_version"] as? String ?? ""
        results.append([
            "tool": "springboard_hid_bridge",
            "success": (hidBridgeRaw["success"] as? Bool) == true
                && (hidBridgeRaw["touch_client"] as? Bool) == true
                && (hidBridgeRaw["keyboard_admin_client"] as? Bool) == true
                && hidBridgeVersion == "0.7.11",
            "output": String(describing: hidBridgeRaw)
        ])

'''
if split_test not in router:
    raise SystemExit("v0.7.11 split self-test marker missing")
router = router.replace(split_test, hid_test, 1)

# Agent must verify input, not accept a dispatch call as proof.
instruction = '''              For any interactive task in another app, phone_apps open_name/open_bundle now automatically creates the split workspace; do not use the foreground_open_* actions unless the user explicitly asked to leave Next Agent and view only that app. After the split opens, use phone_screen OCR/describe/find_text before every coordinate-sensitive step. The OCR path is SpringBoard-native and must return actual text observations; do not treat a successful screenshot alone as vision success. Close the split workspace when the task is complete.
'''
replacement = instruction + '''              Touch and keyboard actions are dispatched by the SpringBoard HID bridge. A successful dispatch is not proof that the UI changed: after type_text, tap, or press_key, verify the expected visible result with phone_screen/OCR before claiming completion. For typing diagnostics, the Next Agent composer itself is the first acceptance target before attempting Notes.
'''
if instruction in s:
    s = s.replace(instruction, replacement, 1)

ui = ui.replace(
    "0.7.10 • RootHide • Async Split • System Theme",
    "0.7.11 • RootHide • SpringBoard HID • System Theme"
)

swift_path.write_text(s)
router_path.write_text(router)
v05_path.write_text(v05)
modern_ui_path.write_text(ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.10", "MARKETING_VERSION: 0.7.11")
y = y.replace("CURRENT_PROJECT_VERSION: 18", "CURRENT_PROJECT_VERSION: 19")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.11"
d["CFBundleVersion"] = "19"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.11-sbocr-hid5"' in swift_path.read_text()
assert "NAScreenBridgeClient.hidTypeText" in v05_path.read_text()
assert "NAScreenBridgeClient.hidTap" in v05_path.read_text()
assert "springboard_hid_bridge" in router_path.read_text()
assert "MARKETING_VERSION: 0.7.11" in project.read_text()
