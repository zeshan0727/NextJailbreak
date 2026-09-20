import Foundation

enum V071ToolSchemas {
    static let grouped: [[String: Any]] = [
        tool(
            "phone_status",
            "Read-only device and diagnostic router. Use action to request device/root/jailbreak/process/network/storage/screen/battery/HID/package status, or self_test to verify the local tool engine without modifying the phone.",
            [
                "action": enumString([
                    "device_info", "root_helper", "jailbreak", "processes",
                    "network", "storage", "screen_info", "battery_info",
                    "battery_properties", "battery_plist", "hid_status",
                    "packages", "self_test"
                ], "Status action"),
                "path": str("Optional allowlisted battery plist path for battery_plist")
            ],
            required: ["action"]
        ),

        tool(
            "phone_apps",
            "Application/router tool for listing installed apps, opening by bundle ID or display name, opening several apps locally in sequence, or opening a URL.",
            [
                "action": enumString(["list", "open_bundle", "open_name", "open_sequence", "open_url"], "Application action"),
                "bundle_id": str("Bundle identifier for open_bundle"),
                "name": str("Display name for open_name"),
                "bundle_ids": arrayString("Bundle IDs for open_sequence", max: 10),
                "delay_seconds": num("Delay between sequence launches, 0.5 to 5 seconds"),
                "url": str("URL for open_url")
            ],
            required: ["action"]
        ),

        tool(
            "phone_screen",
            "Screen-vision router. Capture the current display, OCR it, describe it, find text, tap visible text, or wait for text to appear/disappear.",
            [
                "action": enumString(["capture", "ocr", "describe", "find_text", "tap_text", "wait_text", "wait_text_disappear"], "Screen action"),
                "text": str("Visible text for find/tap/wait actions"),
                "occurrence": int("1-based occurrence for tap_text"),
                "timeout_seconds": num("Timeout 1 to 20 seconds for wait actions"),
                "quality": num("JPEG quality 0.25 to 0.95 for capture"),
                "fast": bool("Use fast OCR"),
                "languages": arrayString("Optional OCR BCP-47 language codes", max: 6)
            ],
            required: ["action"]
        ),

        tool(
            "phone_input",
            "Global UI input router. Requires Sensitive Actions for state-changing input. Supports tap, swipe, typing, keys, buttons, Home/Back, Control Center, Notification Center, wake and lock.",
            [
                "action": enumString([
                    "tap", "double_tap", "long_press", "swipe",
                    "type_text", "key", "button", "home", "back",
                    "control_center", "notification_center", "wake", "lock"
                ], "Input action"),
                "x": num("Normalized x 0 to 1"),
                "y": num("Normalized y 0 to 1"),
                "x1": num("Swipe start x 0 to 1"),
                "y1": num("Swipe start y 0 to 1"),
                "x2": num("Swipe end x 0 to 1"),
                "y2": num("Swipe end y 0 to 1"),
                "duration": num("Gesture duration"),
                "text": str("Text for type_text"),
                "key": str("Key name"),
                "button": str("home, power, volume_up, volume_down or mute")
            ],
            required: ["action"]
        ),

        tool(
            "phone_files",
            "File-management router. Read-only actions can list/read/stat/search. Mutating actions require Sensitive Actions and remain limited to allowed mutable roots; protected credential/message paths remain blocked.",
            [
                "action": enumString(["list", "read", "info", "search", "mkdir", "write", "copy", "move", "delete", "zip", "unzip"], "File action"),
                "path": str("Primary path"),
                "root": str("Search root"),
                "name_contains": str("Filename fragment"),
                "text": str("UTF-8 text for write"),
                "source": str("Source path"),
                "destination": str("Destination path")
            ],
            required: ["action"]
        ),

        tool(
            "phone_packages",
            "RootHide package router. List is read-only. Install/remove requires Sensitive Actions and explicit authorization for the exact package operation.",
            [
                "action": enumString(["list", "install_deb", "remove"], "Package action"),
                "path": str("Local .deb path for install_deb"),
                "package_id": str("Exact package ID for remove")
            ],
            required: ["action"]
        ),

        tool(
            "phone_services",
            "System/service router. Status/list are read-only. Start/stop/restart, uicache, respring, ldrestart, userspace reboot and process termination require Sensitive Actions; disruptive actions require explicit authorization.",
            [
                "action": enumString([
                    "list", "status", "start", "stop", "restart",
                    "uicache", "respring", "ldrestart", "userspace_reboot",
                    "terminate_process"
                ], "Service/system action"),
                "label": str("Exact launchd service label"),
                "pid": int("Process ID for terminate_process")
            ],
            required: ["action"]
        ),

        tool(
            "phone_automation",
            "Saved automation router. Record, save, list, run or delete local UI flows. run_steps executes an immediate multi-step sequence locally so foreground app switching does not require model round trips.",
            [
                "action": enumString(["record_start", "record_stop", "record_cancel", "save", "list", "run", "delete", "run_steps"], "Automation action"),
                "name": str("Automation name"),
                "steps": automationSteps()
            ],
            required: ["action"]
        ),

        tool(
            "phone_clipboard",
            "Clipboard router. Read current text or replace it.",
            [
                "action": enumString(["get", "set"], "Clipboard action"),
                "text": str("Text for set")
            ],
            required: ["action"]
        ),

        tool(
            "phone_display",
            "Display router for reading or setting brightness.",
            [
                "action": enumString(["get_brightness", "set_brightness"], "Display action"),
                "value": num("Brightness from 0 to 1")
            ],
            required: ["action"]
        )
    ]

    private static func automationSteps() -> [String: Any] {
        [
            "type": "array",
            "minItems": 1,
            "maxItems": 80,
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
                    "key": ["type": "string"],
                    "button": ["type": "string"]
                ],
                "required": ["action"],
                "additionalProperties": false
            ]
        ]
    }

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

    private static func str(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    private static func num(_ description: String) -> [String: Any] {
        ["type": "number", "description": description]
    }

    private static func int(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    private static func bool(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }

    private static func enumString(_ values: [String], _ description: String) -> [String: Any] {
        [
            "type": "string",
            "enum": values,
            "description": description
        ]
    }

    private static func arrayString(_ description: String, max: Int) -> [String: Any] {
        [
            "type": "array",
            "items": ["type": "string"],
            "maxItems": max,
            "description": description
        ]
    }
}

extension DeviceToolRegistry {
    @MainActor
    func executeV071(_ name: String, arguments: [String: Any], allowSensitive: Bool) async -> ToolResult? {
        switch name {
        case "phone_status":
            return await routeStatus(arguments, allowSensitive: allowSensitive)
        case "phone_apps":
            return await routeApps(arguments, allowSensitive: allowSensitive)
        case "phone_screen":
            return await routeScreen(arguments, allowSensitive: allowSensitive)
        case "phone_input":
            return await routeInput(arguments, allowSensitive: allowSensitive)
        case "phone_files":
            return await routeFiles(arguments, allowSensitive: allowSensitive)
        case "phone_packages":
            return await routePackages(arguments, allowSensitive: allowSensitive)
        case "phone_services":
            return await routeServices(arguments, allowSensitive: allowSensitive)
        case "phone_automation":
            return await routeAutomation(arguments, allowSensitive: allowSensitive)
        case "phone_clipboard":
            return await routeClipboard(arguments, allowSensitive: allowSensitive)
        case "phone_display":
            return await routeDisplay(arguments, allowSensitive: allowSensitive)
        default:
            return nil
        }
    }

    @MainActor
    func localSelfTest(allowSensitive: Bool) async -> ToolResult {
        let checks: [(String, [String: Any])] = [
            ("root_helper_status", [:]),
            ("device_info", [:]),
            ("hid_status", [:]),
            ("process_list", [:]),
            ("device_storage", [:]),
            ("screen_info", [:]),
            ("battery_info", [:]),
            ("battery_properties", [:]),
            ("screen_capture", ["quality": 0.45])
        ]

        var results: [[String: Any]] = []
        for (toolName, args) in checks {
            let result = await execute(toolName, arguments: args, allowSensitive: allowSensitive)
            results.append([
                "tool": toolName,
                "success": result.success,
                "output": String(result.output.prefix(900))
            ])
        }

        let passed = results.filter { ($0["success"] as? Bool) == true }.count
        return routerJSON([
            "success": passed > 0,
            "router_version": "0.7.1-router1",
            "passed": passed,
            "total": results.count,
            "results": results
        ])
    }

    private func action(_ args: [String: Any]) -> String? {
        (args["action"] as? String)?.lowercased()
    }

    @MainActor
    private func routeStatus(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "device_info": return await execute("device_info", arguments: [:], allowSensitive: allowSensitive)
        case "root_helper": return await execute("root_helper_status", arguments: [:], allowSensitive: allowSensitive)
        case "jailbreak": return await execute("jailbreak_diagnostics", arguments: [:], allowSensitive: allowSensitive)
        case "processes": return await execute("process_list", arguments: [:], allowSensitive: allowSensitive)
        case "network": return await execute("network_interfaces", arguments: [:], allowSensitive: allowSensitive)
        case "storage": return await execute("device_storage", arguments: [:], allowSensitive: allowSensitive)
        case "screen_info": return await execute("screen_info", arguments: [:], allowSensitive: allowSensitive)
        case "battery_info": return await execute("battery_info", arguments: [:], allowSensitive: allowSensitive)
        case "battery_properties": return await execute("battery_properties", arguments: [:], allowSensitive: allowSensitive)
        case "battery_plist":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("read_battery_plist", arguments: ["path": path], allowSensitive: allowSensitive)
        case "hid_status": return await execute("hid_status", arguments: [:], allowSensitive: allowSensitive)
        case "packages": return await execute("package_list", arguments: [:], allowSensitive: allowSensitive)
        case "self_test": return await localSelfTest(allowSensitive: allowSensitive)
        default: return routerBadArgs()
        }
    }

    @MainActor
    private func routeApps(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "list":
            return await execute("list_installed_apps", arguments: [:], allowSensitive: allowSensitive)
        case "open_bundle":
            guard let bundleID = args["bundle_id"] as? String else { return routerBadArgs() }
            return await execute("open_app", arguments: ["bundle_id": bundleID], allowSensitive: allowSensitive)
        case "open_name":
            guard let appName = args["name"] as? String else { return routerBadArgs() }
            return await execute("open_app_by_name", arguments: ["name": appName], allowSensitive: allowSensitive)
        case "open_sequence":
            guard let bundleIDs = args["bundle_ids"] as? [String] else { return routerBadArgs() }
            var routed: [String: Any] = ["bundle_ids": bundleIDs]
            if let delay = args["delay_seconds"] { routed["delay_seconds"] = delay }
            return await execute("open_apps_sequence", arguments: routed, allowSensitive: allowSensitive)
        case "open_url":
            guard let url = args["url"] as? String else { return routerBadArgs() }
            return await execute("open_url", arguments: ["url": url], allowSensitive: allowSensitive)
        default:
            return routerBadArgs()
        }
    }

    @MainActor
    private func routeScreen(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "capture":
            var routed: [String: Any] = [:]
            if let quality = args["quality"] { routed["quality"] = quality }
            return await execute("screen_capture", arguments: routed, allowSensitive: allowSensitive)
        case "ocr":
            var routed: [String: Any] = [:]
            if let fast = args["fast"] { routed["fast"] = fast }
            if let languages = args["languages"] { routed["languages"] = languages }
            return await execute("ocr_screen", arguments: routed, allowSensitive: allowSensitive)
        case "describe":
            return await execute("describe_screen", arguments: [:], allowSensitive: allowSensitive)
        case "find_text":
            guard let text = args["text"] as? String else { return routerBadArgs() }
            return await execute("find_text_on_screen", arguments: ["text": text], allowSensitive: allowSensitive)
        case "tap_text":
            guard let text = args["text"] as? String else { return routerBadArgs() }
            var routed: [String: Any] = ["text": text]
            if let occurrence = args["occurrence"] { routed["occurrence"] = occurrence }
            return await execute("tap_text", arguments: routed, allowSensitive: allowSensitive)
        case "wait_text", "wait_text_disappear":
            guard let text = args["text"] as? String else { return routerBadArgs() }
            var routed: [String: Any] = ["text": text]
            if let timeout = args["timeout_seconds"] { routed["timeout_seconds"] = timeout }
            return await execute(
                action == "wait_text" ? "wait_for_text" : "wait_for_text_disappear",
                arguments: routed,
                allowSensitive: allowSensitive
            )
        default:
            return routerBadArgs()
        }
    }

    @MainActor
    private func routeInput(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "tap", "double_tap":
            guard let x = args["x"], let y = args["y"] else { return routerBadArgs() }
            return await execute(action, arguments: ["x": x, "y": y], allowSensitive: allowSensitive)
        case "long_press":
            guard let x = args["x"], let y = args["y"] else { return routerBadArgs() }
            var routed: [String: Any] = ["x": x, "y": y]
            if let duration = args["duration"] { routed["duration"] = duration }
            return await execute("long_press", arguments: routed, allowSensitive: allowSensitive)
        case "swipe":
            guard let x1 = args["x1"], let y1 = args["y1"], let x2 = args["x2"], let y2 = args["y2"] else { return routerBadArgs() }
            var routed: [String: Any] = ["x1": x1, "y1": y1, "x2": x2, "y2": y2]
            if let duration = args["duration"] { routed["duration"] = duration }
            return await execute("swipe", arguments: routed, allowSensitive: allowSensitive)
        case "type_text":
            guard let text = args["text"] as? String else { return routerBadArgs() }
            return await execute("type_text", arguments: ["text": text], allowSensitive: allowSensitive)
        case "key":
            guard let key = args["key"] as? String else { return routerBadArgs() }
            return await execute("press_key", arguments: ["key": key], allowSensitive: allowSensitive)
        case "button":
            guard let button = args["button"] as? String else { return routerBadArgs() }
            return await execute("press_button", arguments: ["button": button], allowSensitive: allowSensitive)
        case "home": return await execute("go_home", arguments: [:], allowSensitive: allowSensitive)
        case "back": return await execute("go_back", arguments: [:], allowSensitive: allowSensitive)
        case "control_center": return await execute("open_control_center", arguments: [:], allowSensitive: allowSensitive)
        case "notification_center": return await execute("open_notification_center", arguments: [:], allowSensitive: allowSensitive)
        case "wake": return await execute("wake_device", arguments: [:], allowSensitive: allowSensitive)
        case "lock": return await execute("lock_device", arguments: [:], allowSensitive: allowSensitive)
        default: return routerBadArgs()
        }
    }

    @MainActor
    private func routeFiles(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "list":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("root_list_files", arguments: ["path": path], allowSensitive: allowSensitive)
        case "read":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("root_read_text_file", arguments: ["path": path], allowSensitive: allowSensitive)
        case "info":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("root_file_info", arguments: ["path": path], allowSensitive: allowSensitive)
        case "search":
            guard let root = args["root"] as? String, let needle = args["name_contains"] as? String else { return routerBadArgs() }
            return await execute("root_search_files", arguments: ["root": root, "name_contains": needle], allowSensitive: allowSensitive)
        case "mkdir":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("root_create_folder", arguments: ["path": path], allowSensitive: allowSensitive)
        case "write":
            guard let path = args["path"] as? String, let text = args["text"] as? String else { return routerBadArgs() }
            return await execute("root_write_text", arguments: ["path": path, "text": text], allowSensitive: allowSensitive)
        case "copy", "move":
            guard let source = args["source"] as? String, let destination = args["destination"] as? String else { return routerBadArgs() }
            return await execute(action == "copy" ? "root_copy" : "root_move", arguments: ["source": source, "destination": destination], allowSensitive: allowSensitive)
        case "delete":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("root_delete", arguments: ["path": path], allowSensitive: allowSensitive)
        case "zip":
            guard let source = args["source"] as? String, let destination = args["destination"] as? String else { return routerBadArgs() }
            return await execute("zip_path", arguments: ["source": source, "destination_zip": destination], allowSensitive: allowSensitive)
        case "unzip":
            guard let source = args["source"] as? String, let destination = args["destination"] as? String else { return routerBadArgs() }
            return await execute("unzip_archive", arguments: ["archive": source, "destination": destination], allowSensitive: allowSensitive)
        default:
            return routerBadArgs()
        }
    }

    @MainActor
    private func routePackages(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "list": return await execute("package_list", arguments: [:], allowSensitive: allowSensitive)
        case "install_deb":
            guard let path = args["path"] as? String else { return routerBadArgs() }
            return await execute("package_install_deb", arguments: ["path": path], allowSensitive: allowSensitive)
        case "remove":
            guard let packageID = args["package_id"] as? String else { return routerBadArgs() }
            return await execute("package_remove", arguments: ["package_id": packageID], allowSensitive: allowSensitive)
        default: return routerBadArgs()
        }
    }

    @MainActor
    private func routeServices(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "list": return await execute("service_list", arguments: [:], allowSensitive: allowSensitive)
        case "status", "start", "stop", "restart":
            guard let label = args["label"] as? String else { return routerBadArgs() }
            let tool = [
                "status": "service_status",
                "start": "service_start",
                "stop": "service_stop",
                "restart": "service_restart"
            ][action]!
            return await execute(tool, arguments: ["label": label], allowSensitive: allowSensitive)
        case "uicache": return await execute("refresh_icon_cache", arguments: [:], allowSensitive: allowSensitive)
        case "respring": return await execute("respring", arguments: [:], allowSensitive: allowSensitive)
        case "ldrestart": return await execute("ldrestart", arguments: [:], allowSensitive: allowSensitive)
        case "userspace_reboot": return await execute("userspace_reboot", arguments: [:], allowSensitive: allowSensitive)
        case "terminate_process":
            guard let pid = args["pid"] else { return routerBadArgs() }
            return await execute("terminate_process", arguments: ["pid": pid], allowSensitive: allowSensitive)
        default: return routerBadArgs()
        }
    }

    @MainActor
    private func routeAutomation(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        switch action {
        case "record_start":
            guard let name = args["name"] as? String else { return routerBadArgs() }
            return await execute("automation_record_start", arguments: ["name": name], allowSensitive: allowSensitive)
        case "record_stop": return await execute("automation_record_stop", arguments: [:], allowSensitive: allowSensitive)
        case "record_cancel": return await execute("automation_record_cancel", arguments: [:], allowSensitive: allowSensitive)
        case "save":
            guard let name = args["name"] as? String, let steps = args["steps"] as? [[String: Any]] else { return routerBadArgs() }
            return await execute("automation_save", arguments: ["name": name, "steps": steps], allowSensitive: allowSensitive)
        case "list": return await execute("automation_list", arguments: [:], allowSensitive: allowSensitive)
        case "run":
            guard let name = args["name"] as? String else { return routerBadArgs() }
            return await execute("automation_run", arguments: ["name": name], allowSensitive: allowSensitive)
        case "delete":
            guard let name = args["name"] as? String else { return routerBadArgs() }
            return await execute("automation_delete", arguments: ["name": name], allowSensitive: allowSensitive)
        case "run_steps":
            guard let steps = args["steps"] as? [[String: Any]] else { return routerBadArgs() }
            return await execute("ui_automation", arguments: ["steps": steps], allowSensitive: allowSensitive)
        default: return routerBadArgs()
        }
    }

    @MainActor
    private func routeClipboard(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        if action == "get" {
            return await execute("clipboard_get", arguments: [:], allowSensitive: allowSensitive)
        }
        if action == "set", let text = args["text"] as? String {
            return await execute("clipboard_set", arguments: ["text": text], allowSensitive: allowSensitive)
        }
        return routerBadArgs()
    }

    @MainActor
    private func routeDisplay(_ args: [String: Any], allowSensitive: Bool) async -> ToolResult {
        guard let action = action(args) else { return routerBadArgs() }
        if action == "get_brightness" {
            return await execute("get_brightness", arguments: [:], allowSensitive: allowSensitive)
        }
        if action == "set_brightness", let value = args["value"] {
            return await execute("set_brightness", arguments: ["value": value], allowSensitive: allowSensitive)
        }
        return routerBadArgs()
    }

    private func routerJSON(_ object: Any) -> ToolResult {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let text = String(data: data, encoding: .utf8)
        else {
            return ToolResult(success: false, output: "Could not serialize router result")
        }
        let success = (object as? [String: Any])?["success"] as? Bool ?? true
        return ToolResult(success: success, output: text)
    }

    private func routerBadArgs() -> ToolResult {
        ToolResult(success: false, output: "Invalid or missing router arguments")
    }
}
