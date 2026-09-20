import Foundation
import UIKit

enum V07ToolSchemas {
    private static let batteryPlists = [
        "/var/db/Battery/BI/delta_nccp.plist",
        "/var/db/Battery/BI/delta_qmaxp.plist",
        "/var/db/Battery/BI/delta_wra.plist",
        "/var/root/Library/Preferences/com.apple.powerd.bdc.plist",
        "/var/root/Library/Preferences/com.apple.powerdatad.plist",
        "/var/root/Library/Preferences/com.apple.peakpowermanagerd.plist",
        "/var/mobile/Library/Preferences/com.apple.powerui.cec.plist"
    ]

    static let extra: [[String: Any]] = [
        tool("screen_capture", "Capture the current iPhone display and save a JPEG under /var/mobile/Library/NextAgent/Captures. Read-only.", [
            "quality": num("JPEG quality from 0.25 to 0.95")
        ]),
        tool("ocr_screen", "Recognize visible text on the current screen and return normalized top-left coordinates that can be passed directly to tap. Read-only.", [
            "fast": bool("Use faster lower-accuracy recognition"),
            "languages": arrayString("Optional BCP-47 language codes such as en-US")
        ]),
        tool("describe_screen", "Capture and OCR the current screen, returning compact text plus coordinates and screenshot metadata. Read-only.", [:]),
        tool("find_text_on_screen", "Find visible OCR text and return matching coordinates. Read-only.", [
            "text": str("Text to find")
        ], required: ["text"]),
        tool("tap_text", "Find visible text with OCR and tap its center. Requires Sensitive Actions. Do not use for purchase, send, delete, authentication or other consequential controls unless the user explicitly authorized that exact action.", [
            "text": str("Visible text to tap"),
            "occurrence": int("1-based occurrence when multiple matches exist")
        ], required: ["text"]),
        tool("wait_for_text", "Wait until OCR detects specified visible text. Read-only.", [
            "text": str("Text to wait for"),
            "timeout_seconds": num("Timeout from 1 to 20 seconds")
        ], required: ["text"]),
        tool("wait_for_text_disappear", "Wait until specified OCR text is no longer visible. Read-only.", [
            "text": str("Text expected to disappear"),
            "timeout_seconds": num("Timeout from 1 to 20 seconds")
        ], required: ["text"]),

        tool("press_button", "Press a hardware-style HID button: home, power, volume_up, volume_down or mute. Requires Sensitive Actions.", [
            "button": str("home, power, volume_up, volume_down or mute")
        ], required: ["button"]),
        tool("go_home", "Return to the Home Screen using the HID Home/Menu event. Requires Sensitive Actions.", [:]),
        tool("wake_device", "Send a Home/Menu event to wake or reveal the Home/lock interface. Does not bypass a secure passcode. Requires Sensitive Actions.", [:]),
        tool("lock_device", "Press the Power button to lock/turn off the display. Requires explicit user authorization in the current request and Sensitive Actions.", [:]),
        tool("go_back", "Perform the common iOS left-edge back gesture. Requires Sensitive Actions.", [:]),
        tool("open_control_center", "Open Control Center using a top-right edge gesture. Requires Sensitive Actions.", [:]),
        tool("open_notification_center", "Open Notification Center using a top-center edge gesture. Requires Sensitive Actions.", [:]),
        tool("open_app_by_name", "Find an installed app by display name and open it. For ambiguous names, returns candidates instead of guessing.", [
            "name": str("Installed app display name")
        ], required: ["name"]),

        tool("battery_properties", "Read live battery properties through IOKit, including capacity/cycle fields where the device exposes them. Read-only; identifier-like properties are redacted.", [:]),
        tool("read_battery_plist", "Decode one allowlisted battery-related binary/XML plist. Read-only.", [
            "path": [
                "type": "string",
                "enum": batteryPlists,
                "description": "Allowlisted battery property list path"
            ]
        ], required: ["path"]),

        tool("package_install_deb", "Install a local .deb with the RootHide bootstrap dpkg. Requires Sensitive Actions and explicit user authorization for this exact package installation.", [
            "path": str("Readable .deb path under /var/mobile or a temporary directory")
        ], required: ["path"]),
        tool("package_remove", "Remove an installed bootstrap package using dpkg -r. Requires Sensitive Actions and explicit user authorization for this exact package removal.", [
            "package_id": str("Exact package identifier")
        ], required: ["package_id"]),
        tool("ldrestart", "Perform ldrestart. This interrupts many system services. Requires Sensitive Actions and explicit confirmation in the current request.", [:]),
        tool("userspace_reboot", "Perform a userspace reboot with launchctl. This is disruptive. Requires Sensitive Actions and explicit confirmation in the current request.", [:]),

        tool("service_list", "Inspect the launchd user/system service domain. Read-only.", [:]),
        tool("service_status", "Inspect a specific launchd service in user/501 or system domain. Read-only.", [
            "label": str("Exact launchd service label")
        ], required: ["label"]),
        tool("service_start", "Kickstart a launchd service. Requires Sensitive Actions.", [
            "label": str("Exact launchd service label")
        ], required: ["label"]),
        tool("service_restart", "Restart a launchd service with kickstart -k. Requires Sensitive Actions.", [
            "label": str("Exact launchd service label")
        ], required: ["label"]),
        tool("service_stop", "Send SIGTERM to a launchd service. Requires Sensitive Actions.", [
            "label": str("Exact launchd service label")
        ], required: ["label"]),

        tool("root_file_info", "Return root-visible metadata for a file or directory. Read-only.", [
            "path": str("Absolute path or /jbroot alias")
        ], required: ["path"]),
        tool("root_search_files", "Search filenames recursively under a root-visible directory, bounded to depth 6 and 500 results. Read-only; protected credential/message roots remain blocked.", [
            "root": str("Absolute directory or /jbroot alias"),
            "name_contains": str("Case-insensitive filename fragment")
        ], required: ["root", "name_contains"]),
        tool("root_create_folder", "Create a directory in mutable /var/mobile, temporary, preferences or RootHide bootstrap storage. Requires Sensitive Actions.", [
            "path": str("Destination path")
        ], required: ["path"]),
        tool("root_copy", "Copy a file/folder between allowed mutable roots. Requires Sensitive Actions.", [
            "source": str("Source path"),
            "destination": str("Destination path")
        ], required: ["source", "destination"]),
        tool("root_move", "Move/rename a file/folder between allowed mutable roots. Requires Sensitive Actions.", [
            "source": str("Source path"),
            "destination": str("Destination path")
        ], required: ["source", "destination"]),
        tool("root_delete", "Recursively delete a path from allowed mutable roots. Requires Sensitive Actions and explicit authorization for that exact deletion.", [
            "path": str("Path to delete")
        ], required: ["path"]),
        tool("root_write_text", "Write UTF-8 text to an allowed mutable root path, maximum 256 KiB. Requires Sensitive Actions.", [
            "path": str("Destination path"),
            "text": str("Text content")
        ], required: ["path", "text"]),
        tool("zip_path", "Create a zip archive from an allowed mutable path when the bootstrap zip utility is installed. Requires Sensitive Actions.", [
            "source": str("File/folder to archive"),
            "destination_zip": str("Destination .zip path")
        ], required: ["source", "destination_zip"]),
        tool("unzip_archive", "Extract a zip archive into an allowed mutable destination when the bootstrap unzip utility is installed. Requires Sensitive Actions.", [
            "archive": str("Source .zip path"),
            "destination": str("Destination directory")
        ], required: ["archive", "destination"]),

        tool("automation_record_start", "Start recording subsequent Next Agent UI-control tool calls into a reusable automation.", [
            "name": str("Automation name")
        ], required: ["name"]),
        tool("automation_record_stop", "Stop the current automation recording and save it.", [:]),
        tool("automation_record_cancel", "Cancel the current automation recording without saving.", [:]),
        tool("automation_save", "Save a reusable automation from explicit UI-control steps.", [
            "name": str("Automation name"),
            "steps": automationSteps()
        ], required: ["name", "steps"]),
        tool("automation_list", "List saved Next Agent automations. Read-only.", [:]),
        tool("automation_run", "Run a previously saved automation locally. Requires Sensitive Actions.", [
            "name": str("Saved automation name")
        ], required: ["name"]),
        tool("automation_delete", "Delete a saved automation definition. Requires Sensitive Actions.", [
            "name": str("Saved automation name")
        ], required: ["name"])
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

    private static func arrayString(_ description: String) -> [String: Any] {
        [
            "type": "array",
            "items": ["type": "string"],
            "maxItems": 6,
            "description": description
        ]
    }
}

extension DeviceToolRegistry {
    func executeV07(_ name: String, arguments: [String: Any], allowSensitive: Bool) async -> ToolResult? {
        switch name {
        case "screen_capture":
            return v07ScreenCapture(arguments)
        case "ocr_screen":
            return v07OCR(arguments)
        case "describe_screen":
            return v07DescribeScreen()
        case "find_text_on_screen":
            return v07FindText(arguments)
        case "tap_text":
            guard allowSensitive else { return v07SensitiveOff() }
            return v07TapText(arguments)
        case "wait_for_text":
            return await v07WaitForText(arguments, shouldAppear: true)
        case "wait_for_text_disappear":
            return await v07WaitForText(arguments, shouldAppear: false)

        case "press_button":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let button = arguments["button"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "button", argument: button.lowercased())
        case "go_home", "wake_device":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "button", argument: "home")
        case "lock_device":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "button", argument: "power")
        case "go_back":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "swipe", argument: "0.010000,0.500000,0.780000,0.500000,0.350")
        case "open_control_center":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "swipe", argument: "0.965000,0.010000,0.965000,0.620000,0.450")
        case "open_notification_center":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "swipe", argument: "0.500000,0.010000,0.500000,0.620000,0.450")
        case "open_app_by_name":
            return v07OpenAppByName(arguments)

        case "battery_properties":
            return RootDaemonClient.request(action: "battery_properties")
        case "read_battery_plist":
            guard let path = arguments["path"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "read_battery_plist", argument: path)

        case "package_install_deb":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let path = arguments["path"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "package_install", argument: path)
        case "package_remove":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let packageID = arguments["package_id"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "package_remove", argument: packageID)
        case "ldrestart":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "ldrestart")
        case "userspace_reboot":
            guard allowSensitive else { return v07SensitiveOff() }
            return RootDaemonClient.request(action: "userspace_reboot")

        case "service_list":
            return RootDaemonClient.request(action: "service_list")
        case "service_status":
            guard let label = arguments["label"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "service_status", argument: label)
        case "service_start":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let label = arguments["label"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "service_start", argument: label)
        case "service_restart":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let label = arguments["label"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "service_restart", argument: label)
        case "service_stop":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let label = arguments["label"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "service_stop", argument: label)

        case "root_file_info":
            guard let path = arguments["path"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_stat", argument: path)
        case "root_search_files":
            guard
                let root = arguments["root"] as? String,
                let needle = arguments["name_contains"] as? String
            else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_search", argument: root + "\n" + needle)
        case "root_create_folder":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let path = arguments["path"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_mkdir", argument: path)
        case "root_copy":
            guard allowSensitive else { return v07SensitiveOff() }
            guard
                let source = arguments["source"] as? String,
                let destination = arguments["destination"] as? String
            else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_copy", argument: source + "\n" + destination)
        case "root_move":
            guard allowSensitive else { return v07SensitiveOff() }
            guard
                let source = arguments["source"] as? String,
                let destination = arguments["destination"] as? String
            else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_move", argument: source + "\n" + destination)
        case "root_delete":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let path = arguments["path"] as? String else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_delete", argument: path)
        case "root_write_text":
            guard allowSensitive else { return v07SensitiveOff() }
            guard
                let path = arguments["path"] as? String,
                let text = arguments["text"] as? String
            else { return v07BadArgs() }
            return RootDaemonClient.request(action: "root_write_text", argument: path + "\n" + text)
        case "zip_path":
            guard allowSensitive else { return v07SensitiveOff() }
            guard
                let source = arguments["source"] as? String,
                let destination = arguments["destination_zip"] as? String
            else { return v07BadArgs() }
            return RootDaemonClient.request(action: "archive_zip", argument: source + "\n" + destination)
        case "unzip_archive":
            guard allowSensitive else { return v07SensitiveOff() }
            guard
                let source = arguments["archive"] as? String,
                let destination = arguments["destination"] as? String
            else { return v07BadArgs() }
            return RootDaemonClient.request(action: "archive_unzip", argument: source + "\n" + destination)

        case "automation_record_start":
            guard let automationName = arguments["name"] as? String else { return v07BadArgs() }
            return v07JSON(AutomationRecorder.shared.start(name: automationName))
        case "automation_record_stop":
            return v07JSON(AutomationRecorder.shared.stop(save: true))
        case "automation_record_cancel":
            return v07JSON(AutomationRecorder.shared.cancel())
        case "automation_save":
            guard
                let automationName = arguments["name"] as? String,
                let steps = arguments["steps"] as? [[String: Any]],
                v07ValidateAutomationSteps(steps)
            else { return v07BadArgs() }
            return v07JSON(AutomationRecorder.shared.save(name: automationName, steps: steps))
        case "automation_list":
            return v07JSON([
                "recording": AutomationRecorder.shared.currentRecordingName as Any,
                "automations": AutomationRecorder.shared.list()
            ])
        case "automation_run":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let automationName = arguments["name"] as? String else { return v07BadArgs() }
            return await v07RunAutomation(automationName, allowSensitive: allowSensitive)
        case "automation_delete":
            guard allowSensitive else { return v07SensitiveOff() }
            guard let automationName = arguments["name"] as? String else { return v07BadArgs() }
            return v07JSON(AutomationRecorder.shared.delete(name: automationName))

        default:
            return nil
        }
    }

    private func v07ScreenCapture(_ args: [String: Any]) -> ToolResult {
        guard let image = NAScreenVision.shared.captureScreen() else {
            return ToolResult(success: false, output: "System screen capture is unavailable")
        }
        let quality = CGFloat(max(0.25, min(0.95, (args["quality"] as? NSNumber)?.doubleValue ?? 0.78)))
        guard let metadata = NAScreenVision.shared.saveCapture(image, quality: quality) else {
            return ToolResult(success: false, output: "Screenshot was captured but could not be saved")
        }
        return v07JSON(["success": true, "capture": metadata])
    }

    private func v07OCR(_ args: [String: Any]) -> ToolResult {
        guard let image = NAScreenVision.shared.captureScreen() else {
            return ToolResult(success: false, output: "System screen capture is unavailable")
        }
        let fast = (args["fast"] as? Bool) ?? false
        let languages = args["languages"] as? [String] ?? []
        let matches = NAScreenVision.shared.recognizeText(image: image, languages: languages, fast: fast)
        return v07JSON([
            "success": true,
            "coordinate_space": "normalized top-left; x/y range 0...1",
            "items": matches.map(\.dictionary)
        ])
    }

    private func v07DescribeScreen() -> ToolResult {
        guard let image = NAScreenVision.shared.captureScreen() else {
            return ToolResult(success: false, output: "System screen capture is unavailable")
        }
        let matches = NAScreenVision.shared.recognizeText(image: image, fast: true, maxItems: 120)
        let capture = NAScreenVision.shared.saveCapture(image, quality: 0.62) ?? [:]
        let compact = matches.prefix(100).map { item in
            [
                "text": item.text,
                "confidence": item.confidence,
                "center": ["x": item.centerX, "y": item.centerY]
            ] as [String: Any]
        }
        return v07JSON([
            "success": true,
            "capture": capture,
            "visible_text": compact,
            "coordinate_space": "normalized top-left; x/y range 0...1"
        ])
    }

    private func v07FindText(_ args: [String: Any]) -> ToolResult {
        guard
            let query = args["text"] as? String,
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let image = NAScreenVision.shared.captureScreen()
        else { return v07BadArgs() }

        let matches = NAScreenVision.shared.recognizeText(image: image, fast: false)
        let found = NAScreenVision.shared.findText(query, in: matches)
        return v07JSON([
            "success": true,
            "query": query,
            "count": found.count,
            "matches": found.map(\.dictionary)
        ])
    }

    private func v07TapText(_ args: [String: Any]) -> ToolResult {
        guard
            let query = args["text"] as? String,
            !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let image = NAScreenVision.shared.captureScreen()
        else { return v07BadArgs() }

        let matches = NAScreenVision.shared.findText(
            query,
            in: NAScreenVision.shared.recognizeText(image: image, fast: false)
        )
        let occurrence = max(1, (args["occurrence"] as? NSNumber)?.intValue ?? 1)
        guard occurrence <= matches.count else {
            return ToolResult(success: false, output: "Text not found at requested occurrence")
        }
        let match = matches[occurrence - 1]
        let argument = String(format: "%.6f,%.6f", match.centerX, match.centerY)
        let result = RootDaemonClient.request(action: "tap", argument: argument)
        if !result.success { return result }
        return v07JSON([
            "success": true,
            "tapped": match.dictionary,
            "occurrence": occurrence
        ])
    }

    private func v07WaitForText(_ args: [String: Any], shouldAppear: Bool) async -> ToolResult {
        guard let query = args["text"] as? String, !query.isEmpty else { return v07BadArgs() }
        let timeout = max(1.0, min(20.0, (args["timeout_seconds"] as? NSNumber)?.doubleValue ?? 10.0))
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if let image = NAScreenVision.shared.captureScreen() {
                let matches = NAScreenVision.shared.findText(
                    query,
                    in: NAScreenVision.shared.recognizeText(image: image, fast: true, maxItems: 120)
                )
                let present = !matches.isEmpty
                if present == shouldAppear {
                    return v07JSON([
                        "success": true,
                        "text": query,
                        "present": present,
                        "matches": matches.map(\.dictionary)
                    ])
                }
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        } while Date() < deadline

        return ToolResult(
            success: false,
            output: shouldAppear
                ? "Timed out waiting for text to appear"
                : "Timed out waiting for text to disappear"
        )
    }

    @MainActor
    private func v07OpenAppByName(_ args: [String: Any]) -> ToolResult {
        guard let query = args["name"] as? String, !query.isEmpty else { return v07BadArgs() }
        guard let cls = NSClassFromString("LSApplicationWorkspace") else {
            return ToolResult(success: false, output: "LaunchServices unavailable")
        }
        let classObject: AnyObject = cls as AnyObject
        guard
            let unmanaged = classObject.perform(NSSelectorFromString("defaultWorkspace")),
            let workspace = unmanaged.takeUnretainedValue() as? NSObject,
            let applicationsUnmanaged = workspace.perform(NSSelectorFromString("allApplications")),
            let applications = applicationsUnmanaged.takeUnretainedValue() as? [NSObject]
        else {
            return ToolResult(success: false, output: "Could not enumerate installed applications")
        }

        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        var candidates: [(name: String, bundleID: String)] = []

        for proxy in applications {
            let name =
                (proxy.value(forKey: "localizedName") as? String) ??
                (proxy.value(forKey: "itemName") as? String) ??
                (proxy.value(forKey: "bundleIdentifier") as? String) ??
                ""
            let bundleID =
                (proxy.value(forKey: "bundleIdentifier") as? String) ??
                (proxy.value(forKey: "applicationIdentifier") as? String) ??
                ""
            guard !bundleID.isEmpty else { continue }
            let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            if folded == needle || folded.contains(needle) {
                candidates.append((name, bundleID))
            }
        }

        let exact = candidates.filter {
            $0.name.caseInsensitiveCompare(query) == .orderedSame
        }

        let selected: (name: String, bundleID: String)?
        if exact.count == 1 { selected = exact[0] }
        else if exact.isEmpty && candidates.count == 1 { selected = candidates[0] }
        else { selected = nil }

        guard let selected else {
            return v07JSON([
                "success": false,
                "message": candidates.isEmpty ? "No installed app matched that name" : "App name is ambiguous",
                "candidates": candidates.prefix(20).map { ["name": $0.name, "bundle_id": $0.bundleID] }
            ])
        }

        let selector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: selector) else {
            return ToolResult(success: false, output: "LaunchServices open selector unavailable")
        }
        _ = workspace.perform(selector, with: selected.bundleID)
        return v07JSON([
            "success": true,
            "name": selected.name,
            "bundle_id": selected.bundleID
        ])
    }

    private func v07RunAutomation(_ name: String, allowSensitive: Bool) async -> ToolResult {
        guard let steps = AutomationRecorder.shared.load(name: name), !steps.isEmpty else {
            return ToolResult(success: false, output: "Saved automation not found or contains no steps")
        }

        AutomationRecorder.shared.beginReplay()
        defer { AutomationRecorder.shared.endReplay() }

        var results: [[String: Any]] = []
        for (index, step) in steps.enumerated() {
            guard let action = step["action"] as? String else {
                return ToolResult(success: false, output: "Automation contains a step without an action")
            }

            if action == "wait" {
                let seconds = max(0.05, min(15.0, (step["seconds"] as? NSNumber)?.doubleValue ?? 1.0))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                results.append(["step": index + 1, "action": "wait", "success": true])
                continue
            }

            var args = step
            args.removeValue(forKey: "action")
            let result = await execute(action, arguments: args, allowSensitive: allowSensitive)
            results.append([
                "step": index + 1,
                "action": action,
                "success": result.success,
                "output": result.output
            ])
            if !result.success {
                return v07JSON([
                    "success": false,
                    "automation": name,
                    "failed_step": index + 1,
                    "results": results
                ])
            }
        }

        return v07JSON([
            "success": true,
            "automation": name,
            "steps_completed": steps.count,
            "results": results
        ])
    }

    private func v07ValidateAutomationSteps(_ steps: [[String: Any]]) -> Bool {
        guard !steps.isEmpty, steps.count <= 80 else { return false }
        let allowed: Set<String> = [
            "open_app", "open_apps_sequence", "wait",
            "tap", "double_tap", "long_press", "swipe",
            "type_text", "press_key", "press_button",
            "go_home", "go_back", "open_control_center",
            "open_notification_center", "wake_device"
        ]
        for step in steps {
            guard let action = step["action"] as? String, allowed.contains(action) else { return false }
            guard JSONSerialization.isValidJSONObject(step) else { return false }
        }
        return true
    }

    private func v07JSON(_ object: Any) -> ToolResult {
        guard
            JSONSerialization.isValidJSONObject(object),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
            let text = String(data: data, encoding: .utf8)
        else {
            return ToolResult(success: false, output: "Could not serialize tool result")
        }

        var success = true
        if let dictionary = object as? [String: Any], let value = dictionary["success"] as? Bool {
            success = value
        }
        return ToolResult(success: success, output: text)
    }

    private func v07BadArgs() -> ToolResult {
        ToolResult(success: false, output: "Invalid or missing arguments")
    }

    private func v07SensitiveOff() -> ToolResult {
        ToolResult(success: false, output: "Sensitive actions are disabled in Next Agent Settings")
    }
}
