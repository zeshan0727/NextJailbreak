import Foundation
import UIKit

enum V05ToolSchemas {
    static let extra: [[String: Any]] = [
        tool("screen_info", "Return current display dimensions, scale, brightness and orientation.", [:]),
        tool("battery_info", "Return battery level and charging state.", [:]),
        tool("hid_status", "Check whether the RootHide global touch and keyboard injection service is available.", [:]),
        tool("tap", "Tap the global iPhone screen at normalized coordinates from 0.0 to 1.0. Requires Sensitive Actions. Do not use on purchase, payment, send, authentication or other consequential controls unless the user explicitly authorized that exact action.", ["x": num("Horizontal position: 0.0 left to 1.0 right"), "y": num("Vertical position: 0.0 top to 1.0 bottom")], required: ["x", "y"]),
        tool("double_tap", "Double-tap the global iPhone screen at normalized coordinates. Requires Sensitive Actions.", ["x": num("Horizontal position 0.0 to 1.0"), "y": num("Vertical position 0.0 to 1.0")], required: ["x", "y"]),
        tool("long_press", "Long-press the global iPhone screen. Requires Sensitive Actions.", ["x": num("Horizontal position 0.0 to 1.0"), "y": num("Vertical position 0.0 to 1.0"), "duration": num("Duration in seconds, 0.2 to 8")], required: ["x", "y"]),
        tool("swipe", "Swipe globally between two normalized screen points. Requires Sensitive Actions.", ["x1": num("Start x 0.0 to 1.0"), "y1": num("Start y 0.0 to 1.0"), "x2": num("End x 0.0 to 1.0"), "y2": num("End y 0.0 to 1.0"), "duration": num("Duration in seconds, 0.1 to 5")], required: ["x1", "y1", "x2", "y2"]),
        tool("type_text", "Enter text into the currently focused field by temporarily placing the text on the clipboard and dispatching the system Paste keyboard shortcut. The previous clipboard is restored. Requires Sensitive Actions. Never use for passwords, passcodes, authentication tokens, banking/payment credentials or private keys.", ["text": str("Text to enter")], required: ["text"]),
        tool("press_key", "Press one supported keyboard key: enter, backspace, tab, space, escape, up, down, left or right. Requires Sensitive Actions.", ["key": str("Supported key name")], required: ["key"]),
        tool("ui_automation", "Run several local UI steps as one sequence so opening another app does not require a model round trip between every tap. Supported actions: open_app, wait, tap, double_tap, long_press, swipe, type_text, press_key. Requires Sensitive Actions.", [
            "steps": [
                "type": "array",
                "minItems": 1,
                "maxItems": 40,
                "items": [
                    "type": "object",
                    "properties": [
                        "action": ["type": "string"],
                        "bundle_id": ["type": "string"],
                        "x": ["type": "number"],
                        "y": ["type": "number"],
                        "x1": ["type": "number"],
                        "y1": ["type": "number"],
                        "x2": ["type": "number"],
                        "y2": ["type": "number"],
                        "duration": ["type": "number"],
                        "seconds": ["type": "number"],
                        "text": ["type": "string"],
                        "key": ["type": "string"]
                    ],
                    "required": ["action"],
                    "additionalProperties": false
                ]
            ]
        ], required: ["steps"]),
        tool("create_folder", "Create a folder under /var/mobile or the app container. Requires Sensitive Actions.", ["path": str("Folder path")], required: ["path"]),
        tool("copy_file", "Copy a file or folder within allowed user roots. Requires Sensitive Actions.", ["source": str("Source path"), "destination": str("Destination path")], required: ["source", "destination"]),
        tool("move_file", "Move or rename a file or folder within allowed user roots. Requires Sensitive Actions.", ["source": str("Source path"), "destination": str("Destination path")], required: ["source", "destination"]),
        tool("delete_file", "Delete a file or folder within allowed user roots. Requires Sensitive Actions.", ["path": str("Path to delete")], required: ["path"]),
        tool("package_list", "List installed RootHide bootstrap packages and versions. Read-only.", [:])
    ]

    private static func tool(_ name: String, _ description: String, _ props: [String: Any], required: [String] = []) -> [String: Any] {
        [
            "type": "function",
            "name": name,
            "description": description,
            "parameters": [
                "type": "object",
                "properties": props,
                "required": required,
                "additionalProperties": false
            ]
        ]
    }

    private static func str(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func num(_ description: String) -> [String: Any] { ["type": "number", "description": description] }
}

extension DeviceToolRegistry {
    @MainActor
    func executeV05(_ name: String, arguments: [String: Any], allowSensitive: Bool) async -> ToolResult? {
        switch name {
        case "screen_info":
            return v05ScreenInfo()
        case "battery_info":
            return v05BatteryInfo()
        case "hid_status":
            return RootDaemonClient.request(action: "hid_status")
        case "tap":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05Point(action: "tap", args: arguments)
        case "double_tap":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05Point(action: "double_tap", args: arguments)
        case "long_press":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05LongPress(arguments)
        case "swipe":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05Swipe(arguments)
        case "type_text":
            guard allowSensitive else { return v05SensitiveOff() }
            return await v05TypeText(arguments)
        case "press_key":
            guard allowSensitive else { return v05SensitiveOff() }
            guard let key = arguments["key"] as? String else { return v05BadArgs() }
            return RootDaemonClient.request(action: "key", argument: key.lowercased())
        case "ui_automation":
            guard allowSensitive else { return v05SensitiveOff() }
            return await v05Automation(arguments)
        case "create_folder":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05CreateFolder(arguments)
        case "copy_file":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05CopyFile(arguments)
        case "move_file":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05MoveFile(arguments)
        case "delete_file":
            guard allowSensitive else { return v05SensitiveOff() }
            return v05DeleteFile(arguments)
        case "package_list":
            return RootDaemonClient.request(action: "packages")
        default:
            return nil
        }
    }

    private func v05Normalized(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let value = number.doubleValue
        return (0...1).contains(value) ? value : nil
    }

    @MainActor
    private func v05ScreenInfo() -> ToolResult {
        let bounds = UIScreen.main.bounds
        let orientation = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.interfaceOrientation
        let orientationName: String
        switch orientation {
        case .portrait: orientationName = "portrait"
        case .portraitUpsideDown: orientationName = "portrait_upside_down"
        case .landscapeLeft: orientationName = "landscape_left"
        case .landscapeRight: orientationName = "landscape_right"
        default: orientationName = "unknown"
        }
        return v05JSON([
            "width_points": bounds.width,
            "height_points": bounds.height,
            "scale": UIScreen.main.scale,
            "native_scale": UIScreen.main.nativeScale,
            "brightness": UIScreen.main.brightness,
            "orientation": orientationName
        ])
    }

    private func v05BatteryInfo() -> ToolResult {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state: String
        switch UIDevice.current.batteryState {
        case .charging: state = "charging"
        case .full: state = "full"
        case .unplugged: state = "unplugged"
        default: state = "unknown"
        }
        return v05JSON(["level": UIDevice.current.batteryLevel, "state": state])
    }

    private func v05Point(action: String, args: [String: Any]) -> ToolResult {
        guard let x = v05Normalized(args["x"]), let y = v05Normalized(args["y"]) else { return v05BadArgs() }
        return RootDaemonClient.request(action: action, argument: String(format: "%.6f,%.6f", x, y))
    }

    private func v05LongPress(_ args: [String: Any]) -> ToolResult {
        guard let x = v05Normalized(args["x"]), let y = v05Normalized(args["y"]) else { return v05BadArgs() }
        let duration = max(0.2, min(8.0, (args["duration"] as? NSNumber)?.doubleValue ?? 0.8))
        return RootDaemonClient.request(action: "long_press", argument: String(format: "%.6f,%.6f,%.3f", x, y, duration))
    }

    private func v05Swipe(_ args: [String: Any]) -> ToolResult {
        guard
            let x1 = v05Normalized(args["x1"]), let y1 = v05Normalized(args["y1"]),
            let x2 = v05Normalized(args["x2"]), let y2 = v05Normalized(args["y2"])
        else { return v05BadArgs() }
        let duration = max(0.1, min(5.0, (args["duration"] as? NSNumber)?.doubleValue ?? 0.5))
        return RootDaemonClient.request(action: "swipe", argument: String(format: "%.6f,%.6f,%.6f,%.6f,%.3f", x1, y1, x2, y2, duration))
    }

    @MainActor
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

    @MainActor
    private func v05Automation(_ args: [String: Any]) async -> ToolResult {
        guard let steps = args["steps"] as? [[String: Any]], !steps.isEmpty, steps.count <= 40 else { return v05BadArgs() }
        var results: [[String: Any]] = []

        for (index, step) in steps.enumerated() {
            guard let action = (step["action"] as? String)?.lowercased() else { return v05BadArgs() }
            let result: ToolResult

            switch action {
            case "open_app":
                guard let bundleID = step["bundle_id"] as? String else { return v05BadArgs() }
                result = v05OpenApp(bundleID)
            case "wait":
                let seconds = max(0.05, min(15.0, (step["seconds"] as? NSNumber)?.doubleValue ?? 1.0))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                result = ToolResult(success: true, output: "waited \(seconds)s")
            case "tap", "double_tap":
                result = v05Point(action: action, args: step)
            case "long_press":
                result = v05LongPress(step)
            case "swipe":
                result = v05Swipe(step)
            case "type_text":
                guard let text = step["text"] as? String else { return v05BadArgs() }
                result = await v05TypeText(["text": text])
            case "press_key":
                guard let key = step["key"] as? String else { return v05BadArgs() }
                result = RootDaemonClient.request(action: "key", argument: key.lowercased())
            default:
                result = ToolResult(success: false, output: "Unsupported automation action: \(action)")
            }

            results.append(["step": index + 1, "action": action, "success": result.success, "output": result.output])
            if !result.success {
                return v05JSON(["completed": false, "results": results])
            }
        }

        return v05JSON(["completed": true, "results": results])
    }

    private func v05OpenApp(_ bundleID: String) -> ToolResult {
        guard !bundleID.isEmpty, let cls = NSClassFromString("LSApplicationWorkspace") else {
            return ToolResult(success: false, output: "LaunchServices unavailable")
        }
        let classObject: AnyObject = cls as AnyObject
        guard
            let unmanaged = classObject.perform(NSSelectorFromString("defaultWorkspace")),
            let workspace = unmanaged.takeUnretainedValue() as? NSObject
        else { return ToolResult(success: false, output: "LaunchServices unavailable") }

        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: selector) else { return ToolResult(success: false, output: "App launch selector unavailable") }
        _ = workspace.perform(selector, with: bundleID)
        return ToolResult(success: true, output: "Launch request sent for \(bundleID)")
    }

    private func v05AllowedPath(_ raw: String) -> String? {
        let path = (raw as NSString).standardizingPath
        let home = NSHomeDirectory()
        if path == "/var/mobile" || path.hasPrefix("/var/mobile/") || path == home || path.hasPrefix(home + "/") { return path }
        return nil
    }

    private func v05CreateFolder(_ args: [String: Any]) -> ToolResult {
        guard let raw = args["path"] as? String, let path = v05AllowedPath(raw) else { return v05BadArgs() }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            return ToolResult(success: true, output: "Created \(path)")
        } catch { return ToolResult(success: false, output: error.localizedDescription) }
    }

    private func v05CopyFile(_ args: [String: Any]) -> ToolResult {
        guard
            let sourceRaw = args["source"] as? String, let destinationRaw = args["destination"] as? String,
            let source = v05AllowedPath(sourceRaw), let destination = v05AllowedPath(destinationRaw)
        else { return v05BadArgs() }
        do {
            if FileManager.default.fileExists(atPath: destination) { return ToolResult(success: false, output: "Destination already exists") }
            try FileManager.default.copyItem(atPath: source, toPath: destination)
            return ToolResult(success: true, output: "Copied to \(destination)")
        } catch { return ToolResult(success: false, output: error.localizedDescription) }
    }

    private func v05MoveFile(_ args: [String: Any]) -> ToolResult {
        guard
            let sourceRaw = args["source"] as? String, let destinationRaw = args["destination"] as? String,
            let source = v05AllowedPath(sourceRaw), let destination = v05AllowedPath(destinationRaw)
        else { return v05BadArgs() }
        do {
            if FileManager.default.fileExists(atPath: destination) { return ToolResult(success: false, output: "Destination already exists") }
            try FileManager.default.moveItem(atPath: source, toPath: destination)
            return ToolResult(success: true, output: "Moved to \(destination)")
        } catch { return ToolResult(success: false, output: error.localizedDescription) }
    }

    private func v05DeleteFile(_ args: [String: Any]) -> ToolResult {
        guard let raw = args["path"] as? String, let path = v05AllowedPath(raw), path != "/var/mobile", path != NSHomeDirectory() else { return v05BadArgs() }
        do {
            try FileManager.default.removeItem(atPath: path)
            return ToolResult(success: true, output: "Deleted \(path)")
        } catch { return ToolResult(success: false, output: error.localizedDescription) }
    }

    private func v05JSON(_ object: Any) -> ToolResult {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let text = String(data: data, encoding: .utf8)
        else { return ToolResult(success: false, output: "Could not serialize result") }
        return ToolResult(success: true, output: text)
    }

    private func v05BadArgs() -> ToolResult { ToolResult(success: false, output: "Invalid or missing arguments") }
    private func v05SensitiveOff() -> ToolResult { ToolResult(success: false, output: "Sensitive actions are disabled in Next Agent Settings") }
}
