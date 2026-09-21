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
modern_ui = modern_ui_path.read_text()

s = s.replace(
    "Next Agent 0.7.7 is ready with direct in-memory SpringBoard vision and experimental split workspace.",
    "Next Agent 0.7.8 is ready with SpringBoard-native OCR and enforced split workspace for interactive app tasks."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.7-directsplit1"',
    'private static let currentToolSchemaVersion = "0.7.8-sbocr-split2"'
)
s = s.replace('"client_version": "0.7.7"', '"client_version": "0.7.8"')

def replace_function(text, start_marker, end_marker, replacement):
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"missing function start: {start_marker}")
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"missing function end: {end_marker}")
    return text[:start] + replacement + text[end:]

# Resolve app names without automatically foregrounding the target.
resolve_marker = '''        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: selector) else {
'''
resolve_insert = '''        if (args["resolve_only"] as? Bool) == true {
            return v07JSON([
                "success": true,
                "resolved_only": true,
                "name": selected.name,
                "bundle_id": selected.bundleID
            ])
        }

        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: selector) else {
'''
if resolve_marker not in v07:
    raise SystemExit("v0.7.8 app-name resolve marker missing")
v07 = v07.replace(resolve_marker, resolve_insert, 1)

ocr_func = '''    private func v07OCR(_ args: [String: Any]) -> ToolResult {
        let fast = (args["fast"] as? Bool) ?? false
        let languages = args["languages"] as? [String] ?? []
        guard let payload = NAScreenBridgeClient.ocrScreen(
            fast: fast,
            languages: languages,
            maxItems: 180
        ) as? [String: Any] else {
            return ToolResult(success: false, output: "SpringBoard OCR bridge returned an unreadable response")
        }
        return v07JSON(payload)
    }

'''
v07 = replace_function(
    v07,
    '    private func v07OCR(_ args: [String: Any]) -> ToolResult {',
    '    private func v07DescribeScreen() -> ToolResult {',
    ocr_func
)

describe_func = '''    private func v07DescribeScreen() -> ToolResult {
        guard let payload = NAScreenBridgeClient.ocrScreen(
            fast: false,
            languages: [],
            maxItems: 160
        ) as? [String: Any] else {
            return ToolResult(success: false, output: "SpringBoard OCR bridge returned an unreadable response")
        }

        guard (payload["success"] as? Bool) == true,
              let items = payload["items"] as? [[String: Any]],
              !items.isEmpty else {
            return v07JSON(payload)
        }

        let compact = items.prefix(120).map { item -> [String: Any] in
            [
                "text": item["text"] as? String ?? "",
                "confidence": item["confidence"] ?? 0,
                "center": [
                    "x": item["center_x"] ?? 0,
                    "y": item["center_y"] ?? 0
                ]
            ]
        }

        return v07JSON([
            "success": true,
            "source": payload["source"] ?? "springboard_vision",
            "quality": payload["quality"] ?? [:],
            "visible_text": compact,
            "count": items.count,
            "coordinate_space": payload["coordinate_space"] ?? "normalized top-left; x/y range 0...1",
            "transport_version": payload["transport_version"] ?? "0.7.8-springboard-vision1"
        ])
    }

'''
v07 = replace_function(
    v07,
    '    private func v07DescribeScreen() -> ToolResult {',
    '    private func v07FindText(_ args: [String: Any]) -> ToolResult {',
    describe_func
)

find_func = '''    private func v078NormalizedText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func v078FindItems(_ query: String, in items: [[String: Any]]) -> [[String: Any]] {
        let needle = v078NormalizedText(query)
        guard !needle.isEmpty else { return [] }

        return items.filter { item in
            let hay = v078NormalizedText(item["text"] as? String ?? "")
            return hay == needle || hay.contains(needle) || needle.contains(hay)
        }
        .sorted { a, b in
            let at = v078NormalizedText(a["text"] as? String ?? "")
            let bt = v078NormalizedText(b["text"] as? String ?? "")
            let aExact = at == needle
            let bExact = bt == needle
            if aExact != bExact { return aExact && !bExact }
            let ac = (a["confidence"] as? NSNumber)?.doubleValue ?? 0
            let bc = (b["confidence"] as? NSNumber)?.doubleValue ?? 0
            return ac > bc
        }
    }

    private func v07FindText(_ args: [String: Any]) -> ToolResult {
        guard let query = args["text"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return v07BadArgs()
        }
        guard let payload = NAScreenBridgeClient.ocrScreen(
            fast: false,
            languages: [],
            maxItems: 180
        ) as? [String: Any] else {
            return ToolResult(success: false, output: "SpringBoard OCR bridge returned an unreadable response")
        }
        guard (payload["success"] as? Bool) == true,
              let items = payload["items"] as? [[String: Any]] else {
            return v07JSON(payload)
        }

        let found = v078FindItems(query, in: items)
        return v07JSON([
            "success": true,
            "query": query,
            "count": found.count,
            "matches": found,
            "source": payload["source"] ?? "springboard_vision",
            "transport_version": payload["transport_version"] ?? "0.7.8-springboard-vision1"
        ])
    }

'''
v07 = replace_function(
    v07,
    '    private func v07FindText(_ args: [String: Any]) -> ToolResult {',
    '    private func v07TapText(_ args: [String: Any]) -> ToolResult {',
    find_func
)

tap_func = '''    private func v07TapText(_ args: [String: Any]) -> ToolResult {
        guard let query = args["text"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return v07BadArgs()
        }
        guard let payload = NAScreenBridgeClient.ocrScreen(
            fast: false,
            languages: [],
            maxItems: 180
        ) as? [String: Any] else {
            return ToolResult(success: false, output: "SpringBoard OCR bridge returned an unreadable response")
        }
        guard (payload["success"] as? Bool) == true,
              let items = payload["items"] as? [[String: Any]] else {
            return v07JSON(payload)
        }

        let matches = v078FindItems(query, in: items)
        let occurrence = max(1, (args["occurrence"] as? NSNumber)?.intValue ?? 1)
        guard occurrence <= matches.count else {
            return ToolResult(success: false, output: "Text not found at requested occurrence")
        }

        let match = matches[occurrence - 1]
        guard let x = match["center_x"] as? NSNumber,
              let y = match["center_y"] as? NSNumber else {
            return ToolResult(success: false, output: "OCR match did not include usable coordinates")
        }

        let argument = String(format: "%.6f,%.6f", x.doubleValue, y.doubleValue)
        let result = RootDaemonClient.request(action: "tap", argument: argument)
        if !result.success { return result }

        return v07JSON([
            "success": true,
            "tapped": match,
            "occurrence": occurrence,
            "source": payload["source"] ?? "springboard_vision"
        ])
    }

'''
v07 = replace_function(
    v07,
    '    private func v07TapText(_ args: [String: Any]) -> ToolResult {',
    '    private func v07WaitForText(_ args: [String: Any], shouldAppear: Bool) async -> ToolResult {',
    tap_func
)

wait_func = '''    private func v07WaitForText(_ args: [String: Any], shouldAppear: Bool) async -> ToolResult {
        guard let query = args["text"] as? String, !query.isEmpty else { return v07BadArgs() }
        let timeout = max(1.0, min(20.0, (args["timeout_seconds"] as? NSNumber)?.doubleValue ?? 10.0))
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if let payload = NAScreenBridgeClient.ocrScreen(
                fast: true,
                languages: [],
                maxItems: 160
            ) as? [String: Any],
               let items = payload["items"] as? [[String: Any]] {
                let matches = v078FindItems(query, in: items)
                let present = !matches.isEmpty
                if present == shouldAppear {
                    return v07JSON([
                        "success": true,
                        "text": query,
                        "present": present,
                        "matches": matches,
                        "source": payload["source"] ?? "springboard_vision"
                    ])
                }
            }
            try? await Task.sleep(nanoseconds: 550_000_000)
        } while Date() < deadline

        return ToolResult(
            success: false,
            output: shouldAppear
                ? "Timed out waiting for SpringBoard OCR text to appear"
                : "Timed out waiting for SpringBoard OCR text to disappear"
        )
    }

'''
v07 = replace_function(
    v07,
    '    private func v07WaitForText(_ args: [String: Any], shouldAppear: Bool) async -> ToolResult {',
    '    @MainActor\n    private func v07OpenAppByName(_ args: [String: Any]) -> ToolResult {',
    wait_func
)

# Self-test must really test OCR, and split must test capability rather than an idle status endpoint.
old_selftest = '''        let splitStatusRaw = NAScreenBridgeClient.splitWorkspaceStatus()
        results.append([
            "tool": "split_workspace_bridge",
            "success": (splitStatusRaw["success"] as? Bool) == true,
            "output": String(describing: splitStatusRaw)
        ])

'''
new_selftest = '''        let ocrRaw = NAScreenBridgeClient.ocrScreen(
            fast: false,
            languages: ["en-US"],
            maxItems: 100
        )
        let ocrCount = (ocrRaw["count"] as? NSNumber)?.intValue ?? 0
        results.append([
            "tool": "direct_ocr_bridge",
            "success": (ocrRaw["success"] as? Bool) == true && ocrCount > 0,
            "output": String(describing: ocrRaw)
        ])

        let splitCapabilityRaw = NAScreenBridgeClient.splitCapabilities()
        results.append([
            "tool": "split_workspace_capability",
            "success": (splitCapabilityRaw["success"] as? Bool) == true,
            "output": String(describing: splitCapabilityRaw)
        ])

'''
if old_selftest not in router:
    raise SystemExit("v0.7.8 self-test marker missing")
router = router.replace(old_selftest, new_selftest, 1)

# The grouped app router now keeps Next Agent foreground by default.
router = router.replace(
    'enumString(["list", "open_bundle", "open_name", "open_sequence", "open_url", "split_open", "split_status", "split_close"], "Application action")',
    'enumString(["list", "open_bundle", "open_name", "open_sequence", "open_url", "split_open", "split_status", "split_close", "foreground_open_bundle", "foreground_open_name"], "Application action")'
)
router = router.replace(
    '"Application/router tool for app discovery/launch plus the experimental SpringBoard-hosted 50/50 split workspace. split_open keeps Next Agent in the top pane and the target app in the bottom pane."',
    '"Application/router tool. open_bundle and open_name now open the target inside the SpringBoard-hosted 50/50 workspace so Next Agent stays foreground. Use foreground_open_* only when the user explicitly wants to leave Next Agent and view one app full-screen."'
)

old_routes = '''        case "open_bundle":
            guard let bundleID = args["bundle_id"] as? String else { return routerBadArgs() }
            return await execute("open_app", arguments: ["bundle_id": bundleID], allowSensitive: allowSensitive)
        case "open_name":
            guard let appName = args["name"] as? String else { return routerBadArgs() }
            return await execute("open_app_by_name", arguments: ["name": appName], allowSensitive: allowSensitive)
'''
new_routes = '''        case "open_bundle":
            guard let bundleID = args["bundle_id"] as? String else { return routerBadArgs() }
            return routerJSON(NAScreenBridgeClient.openSplitWorkspace(secondary: bundleID))
        case "open_name":
            guard let appName = args["name"] as? String else { return routerBadArgs() }
            let resolved = await execute(
                "open_app_by_name",
                arguments: ["name": appName, "resolve_only": true],
                allowSensitive: allowSensitive
            )
            guard resolved.success,
                  let data = resolved.output.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let bundleID = object["bundle_id"] as? String else {
                return resolved
            }
            return routerJSON(NAScreenBridgeClient.openSplitWorkspace(secondary: bundleID))
'''
if old_routes not in router:
    raise SystemExit("v0.7.8 enforced split route marker missing")
router = router.replace(old_routes, new_routes, 1)

route_foreground_marker = '''        case "split_close":
            return routerJSON(NAScreenBridgeClient.closeSplitWorkspace())
        default:
'''
route_foreground_replacement = '''        case "split_close":
            return routerJSON(NAScreenBridgeClient.closeSplitWorkspace())
        case "foreground_open_bundle":
            guard let bundleID = args["bundle_id"] as? String else { return routerBadArgs() }
            return await execute("open_app", arguments: ["bundle_id": bundleID], allowSensitive: allowSensitive)
        case "foreground_open_name":
            guard let appName = args["name"] as? String else { return routerBadArgs() }
            return await execute("open_app_by_name", arguments: ["name": appName], allowSensitive: allowSensitive)
        default:
'''
if route_foreground_marker not in router:
    raise SystemExit("v0.7.8 foreground route insertion marker missing")
router = router.replace(route_foreground_marker, route_foreground_replacement, 1)

router = router.replace(
    '"router_version": "0.7.7-directsplit1"',
    '"router_version": "0.7.8-sbocr-split2"'
)

instruction = '''              For UI tasks that need another foreground app, especially Notes, prefer phone_apps action=split_open with that app's bundle ID before using phone_screen. The experimental workspace keeps Next Agent in the top half and the target app in the bottom half so reasoning stays foreground while OCR and HID act on the combined display. If split_open reports failure, do not fall back to blind coordinates. Close the split workspace when the task is complete.
'''
replacement = '''              For any interactive task in another app, phone_apps open_name/open_bundle now automatically creates the split workspace; do not use the foreground_open_* actions unless the user explicitly asked to leave Next Agent and view only that app. After the split opens, use phone_screen OCR/describe/find_text before every coordinate-sensitive step. The OCR path is SpringBoard-native and must return actual text observations; do not treat a successful screenshot alone as vision success. Close the split workspace when the task is complete.
'''
if instruction not in s:
    raise SystemExit("v0.7.8 interaction instruction marker missing")
s = s.replace(instruction, replacement, 1)

modern_ui = modern_ui.replace(
    "0.7.7 • RootHide • Direct Vision • Split Workspace",
    "0.7.8 • RootHide • SpringBoard OCR • Enforced Split"
)

swift_path.write_text(s)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(modern_ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.7", "MARKETING_VERSION: 0.7.8")
y = y.replace("CURRENT_PROJECT_VERSION: 15", "CURRENT_PROJECT_VERSION: 16")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.8"
d["CFBundleVersion"] = "16"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.8-sbocr-split2"' in swift_path.read_text()
assert "direct_ocr_bridge" in router_path.read_text()
assert "split_workspace_capability" in router_path.read_text()
assert "foreground_open_bundle" in router_path.read_text()
assert "NAScreenBridgeClient.ocrScreen" in v07_path.read_text()
assert "resolve_only" in v07_path.read_text()
assert "MARKETING_VERSION: 0.7.8" in project.read_text()
