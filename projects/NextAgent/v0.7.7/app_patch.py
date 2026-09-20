from pathlib import Path
import plistlib

root = Path(".")
swift_path = root / "NextAgent/NextAgent.swift"
screen_path = root / "NextAgent/ScreenVision.swift"
router_path = root / "NextAgent/V071Router.swift"
v07_path = root / "NextAgent/V07Tools.swift"
modern_ui_path = root / "NextAgent/ModernUI.swift"
bridge_header_path = root / "NextAgent/NextAgent-Bridging-Header.h"

s = swift_path.read_text()
screen = screen_path.read_text()
router = router_path.read_text()
v07 = v07_path.read_text()
modern_ui = modern_ui_path.read_text()
bridge_header = bridge_header_path.read_text()

s = s.replace(
    "Next Agent 0.7.6 is ready with validated CoreVideo screen capture and a foreground-app progress HUD.",
    "Next Agent 0.7.7 is ready with direct in-memory SpringBoard vision and experimental split workspace."
)
s = s.replace(
    'private static let currentToolSchemaVersion = "0.7.6-capturehud1"',
    'private static let currentToolSchemaVersion = "0.7.7-directsplit1"'
)
s = s.replace('"client_version": "0.7.6"', '"client_version": "0.7.7"')

if '#import "NAScreenBridgeClient.h"' not in bridge_header:
    bridge_header = bridge_header.rstrip() + '\n#import "NAScreenBridgeClient.h"\n'
bridge_header_path.write_text(bridge_header)

screen = screen.replace(
    '    private let captureDirectory = "/var/mobile/Library/NextAgent/Captures"\n',
    '''    private var captureDirectory: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NextAgentCaptures", isDirectory: true)
            .path
    }
'''
)

old_bridge = '''    private func captureFromSpringBoard() -> UIImage? {
        let result = RootDaemonClient.request(action: "screen_capture_real")

        guard let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            lastCaptureMetadata = [
                "success": false,
                "error": String(result.output.prefix(1200))
            ]
            lastCaptureSource = "springboard_bridge_invalid_response"
            return nil
        }

        lastCaptureMetadata = json
        lastCaptureSource = (json["source"] as? String) ?? "springboard"

        guard result.success,
              (json["success"] as? Bool) == true,
              let quality = json["quality"] as? [String: Any],
              (quality["valid"] as? Bool) == true,
              let path = json["path"] as? String,
              let image = UIImage(contentsOfFile: path) else {
            if (json["success"] as? Bool) == true {
                lastCaptureSource = "springboard_bridge_unusable_frame"
            }
            return nil
        }

        return image
    }
'''
new_bridge = '''    private func captureFromSpringBoard() -> UIImage? {
        let raw = NAScreenBridgeClient.captureScreen()
        guard var json = raw as? [String: Any] else {
            lastCaptureMetadata = [
                "success": false,
                "error": "direct SpringBoard bridge returned an unreadable dictionary"
            ]
            lastCaptureSource = "direct_bridge_invalid_response"
            return nil
        }

        let imageData = json["image_data"] as? Data
        json.removeValue(forKey: "image_data")
        lastCaptureMetadata = json
        lastCaptureSource = (json["source"] as? String) ?? "direct_springboard"

        guard
            (json["success"] as? Bool) == true,
            let quality = json["quality"] as? [String: Any],
            (quality["valid"] as? Bool) == true,
            let imageData,
            let image = UIImage(data: imageData)
        else {
            if (json["success"] as? Bool) == true {
                lastCaptureSource = "direct_bridge_unusable_frame"
            }
            return nil
        }

        return image
    }
'''
if old_bridge not in screen:
    raise SystemExit("v0.7.7 direct capture replacement marker missing")
screen = screen.replace(old_bridge, new_bridge, 1)

# The old daemon-mediated screen handoff is intentionally retired from self-test.
old_test = '''        let realScreen = RootDaemonClient.request(action: "screen_capture_real")
        results.append([
            "tool": "real_screen_bridge",
            "success": realScreen.success,
            "output": String(realScreen.output.prefix(1600))
        ])

'''
new_test = '''        let directBridgeRaw = NAScreenBridgeClient.captureScreen()
        if var directBridge = directBridgeRaw as? [String: Any] {
            directBridge.removeValue(forKey: "image_data")
            results.append([
                "tool": "direct_screen_bridge",
                "success": (directBridge["success"] as? Bool) == true,
                "output": String(describing: directBridge)
            ])
        } else {
            results.append([
                "tool": "direct_screen_bridge",
                "success": false,
                "output": "Direct SpringBoard bridge returned an unreadable response"
            ])
        }

        let splitStatusRaw = NAScreenBridgeClient.splitWorkspaceStatus()
        results.append([
            "tool": "split_workspace_bridge",
            "success": (splitStatusRaw["success"] as? Bool) == true,
            "output": String(describing: splitStatusRaw)
        ])

'''
if old_test not in router:
    raise SystemExit("v0.7.7 old real-screen self-test marker missing")
router = router.replace(old_test, new_test, 1)

router = router.replace(
    'enumString(["list", "open_bundle", "open_name", "open_sequence", "open_url"], "Application action")',
    'enumString(["list", "open_bundle", "open_name", "open_sequence", "open_url", "split_open", "split_status", "split_close"], "Application action")'
)
router = router.replace(
    '                "name": str("Display name for open_name"),\n',
    '                "name": str("Display name for open_name"),\n'
    '                "secondary_bundle_id": str("Target app bundle identifier for split_open; Next Agent remains the primary pane"),\n'
)
router = router.replace(
    '"Application/router tool for listing installed apps, opening by bundle ID or display name, opening several apps locally in sequence, or opening a URL."',
    '"Application/router tool for app discovery/launch plus the experimental SpringBoard-hosted 50/50 split workspace. split_open keeps Next Agent in the top pane and the target app in the bottom pane."'
)

route_marker = '''        case "open_url":
            guard let url = args["url"] as? String else { return routerBadArgs() }
            return await execute("open_url", arguments: ["url": url], allowSensitive: allowSensitive)
        default:
            return routerBadArgs()
'''
route_replacement = '''        case "open_url":
            guard let url = args["url"] as? String else { return routerBadArgs() }
            return await execute("open_url", arguments: ["url": url], allowSensitive: allowSensitive)
        case "split_open":
            guard let secondary = args["secondary_bundle_id"] as? String, !secondary.isEmpty else {
                return routerBadArgs()
            }
            let response = NAScreenBridgeClient.openSplitWorkspace(secondary: secondary)
            return routerJSON(response)
        case "split_status":
            return routerJSON(NAScreenBridgeClient.splitWorkspaceStatus())
        case "split_close":
            return routerJSON(NAScreenBridgeClient.closeSplitWorkspace())
        default:
            return routerBadArgs()
'''
if route_marker not in router:
    raise SystemExit("v0.7.7 routeApps split marker missing")
router = router.replace(route_marker, route_replacement, 1)
router = router.replace(
    '"router_version": "0.7.1-router1"',
    '"router_version": "0.7.7-directsplit1"'
)

v07 = v07.replace(
    'Capture the current iPhone display and save a lossless PNG under /var/mobile/Library/NextAgent/Captures. Read-only.',
    'Capture the current iPhone display through the direct in-memory SpringBoard bridge and optionally cache a temporary PNG. Read-only.'
)

instruction = '''              A phone_screen result is usable for coordinate planning only when its SpringBoard bridge reports success=true and quality.valid=true. Empty OCR is a real failure for text-driven UI steps such as Notes; do not guess a Compose button position after an empty OCR result.
'''
replacement = instruction + '''              For UI tasks that need another foreground app, especially Notes, prefer phone_apps action=split_open with that app's bundle ID before using phone_screen. The experimental workspace keeps Next Agent in the top half and the target app in the bottom half so reasoning stays foreground while OCR and HID act on the combined display. If split_open reports failure, do not fall back to blind coordinates. Close the split workspace when the task is complete.
'''
if instruction not in s:
    raise SystemExit("v0.7.7 agent split instruction marker missing")
s = s.replace(instruction, replacement, 1)

modern_ui = modern_ui.replace(
    "0.7.6 • RootHide • GPT-6 Astra",
    "0.7.7 • RootHide • Direct Vision • Split Workspace"
)

swift_path.write_text(s)
screen_path.write_text(screen)
router_path.write_text(router)
v07_path.write_text(v07)
modern_ui_path.write_text(modern_ui)

project = root / "project.yml"
y = project.read_text()
y = y.replace("MARKETING_VERSION: 0.7.6", "MARKETING_VERSION: 0.7.7")
y = y.replace("CURRENT_PROJECT_VERSION: 14", "CURRENT_PROJECT_VERSION: 15")
project.write_text(y)

plist_path = root / "NextAgent/Info.plist"
d = plistlib.loads(plist_path.read_bytes())
d["CFBundleShortVersionString"] = "0.7.7"
d["CFBundleVersion"] = "15"
plist_path.write_bytes(plistlib.dumps(d))

assert 'currentToolSchemaVersion = "0.7.7-directsplit1"' in swift_path.read_text()
assert "NAScreenBridgeClient.captureScreen()" in screen_path.read_text()
assert "split_open" in router_path.read_text()
assert "direct_screen_bridge" in router_path.read_text()
assert '#import "NAScreenBridgeClient.h"' in bridge_header_path.read_text()
assert "MARKETING_VERSION: 0.7.7" in project.read_text()
