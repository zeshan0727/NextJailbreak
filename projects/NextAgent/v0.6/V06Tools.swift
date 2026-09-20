import Foundation
import UIKit
import Vision

enum V06ToolSchemas {
    static let extra: [[String: Any]] = [
        tool("screenshot", "Capture the current global iPhone screen through the RootHide helper and save it to the Next Agent working folder. Read-only.", [:]),
        tool("screen_ocr", "Capture the current screen and return recognized text with normalized tap coordinates. Read-only.", [:]),
        tool("find_text_on_screen", "Capture the current screen and find visible text matching a string. Returns normalized tap coordinates. Read-only.", ["text": str("Visible text to find"), "contains": bool("If true, substring match; otherwise exact case-insensitive match")], required: ["text"]),
        tool("tap_text", "Find visible text on the current screen and tap its center. Requires Sensitive Actions and explicit authorization when the target is consequential.", ["text": str("Visible text to tap"), "contains": bool("If true, substring match; otherwise exact case-insensitive match")], required: ["text"]),

        tool("save_automation", "Save a named reusable UI automation flow locally in Next Agent.", ["name": str("Automation name"), "steps": stepsSchema()], required: ["name", "steps"]),
        tool("list_automations", "List saved local automation flows. Read-only.", [:]),
        tool("run_saved_automation", "Run a previously saved UI automation flow. Requires Sensitive Actions.", ["name": str("Saved automation name")], required: ["name"]),
        tool("delete_automation", "Delete a saved automation definition. Requires Sensitive Actions.", ["name": str("Saved automation name")], required: ["name"]),

        tool("file_search", "Search filenames recursively under /var/mobile or the app container. Read-only.", ["root": str("Search root"), "query": str("Filename substring"), "max_results": integer("Maximum results, 1 to 250")], required: ["root", "query"]),
        tool("plist_read", "Read a property list under /var/mobile/Library/Preferences or the app container. Read-only.", ["path": str("Plist path")], required: ["path"]),
        tool("plist_set", "Set a property-list value under /var/mobile/Library/Preferences or the app container. Requires Sensitive Actions.", ["path": str("Plist path"), "key": str("Top-level key"), "value": anyValue("JSON-compatible property-list value")], required: ["path", "key", "value"]),
        tool("archive_create", "Create a .tar.gz archive from an allowed /var/mobile path using the RootHide helper. Requires Sensitive Actions.", ["source": str("Source path"), "destination": str("Destination .tar.gz path")], required: ["source", "destination"]),
        tool("archive_extract", "Extract a .tar.gz archive into an allowed /var/mobile destination using the RootHide helper. Requires Sensitive Actions.", ["archive": str("Archive path"), "destination": str("Destination directory")], required: ["archive", "destination"]),

        tool("package_install", "Install a local .deb from /var/mobile using the RootHide package manager. Consequential: use only when the user explicitly asks to install that exact package.", ["path": str("Absolute .deb path")], required: ["path"]),
        tool("package_remove", "Remove a non-critical RootHide package by package identifier. Consequential: use only when the user explicitly asks to remove that exact package.", ["package": str("Package identifier")], required: ["package"]),
        tool("uicache_all", "Refresh application registration/icons. Requires Sensitive Actions.", [:]),
        tool("respring", "Restart SpringBoard. Consequential: use only when explicitly requested in the current instruction.", [:]),
        tool("ldrestart", "Restart userland daemons using ldrestart when available. Consequential: use only when explicitly requested.", [:]),
        tool("userspace_reboot", "Request a userspace reboot. Highly consequential: use only when explicitly requested.", [:]),
        tool("service_status", "Inspect a third-party launchd service in the current RootHide user domain. Read-only.", ["label": str("Third-party launchd label")], required: ["label"]),
        tool("service_start", "Start a third-party launchd service. Requires Sensitive Actions and explicit authorization.", ["label": str("Third-party launchd label")], required: ["label"]),
        tool("service_restart", "Restart a third-party launchd service. Requires Sensitive Actions and explicit authorization.", ["label": str("Third-party launchd label")], required: ["label"]),
        tool("service_stop", "Stop a third-party launchd service. Requires Sensitive Actions and explicit authorization.", ["label": str("Third-party launchd label")], required: ["label"]),

        tool("battery_properties", "Read live battery properties directly from IOKit through nextagentd. Read-only.", [:]),
        tool("read_battery_plist", "Decode one allow-listed battery-related binary/XML plist. Read-only.", ["path": [
            "type": "string",
            "enum": [
                "/var/db/Battery/BI/delta_nccp.plist",
                "/var/db/Battery/BI/delta_qmaxp.plist",
                "/var/db/Battery/BI/delta_wra.plist",
                "/var/root/Library/Preferences/com.apple.powerd.bdc.plist",
                "/var/root/Library/Preferences/com.apple.powerdatad.plist",
                "/var/root/Library/Preferences/com.apple.peakpowermanagerd.plist",
                "/var/mobile/Library/Preferences/com.apple.powerui.cec.plist"
            ]
        ]], required: ["path"])
    ]

    private static func stepsSchema() -> [String: Any] {
        [
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

    private static func str(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func bool(_ description: String) -> [String: Any] { ["type": "boolean", "description": description] }
    private static func integer(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }
    private static func anyValue(_ description: String) -> [String: Any] {
        ["description": description, "type": ["string", "number", "integer", "boolean", "array", "object", "null"]]
    }
}

private struct NAOCRHit {
    let text: String
    let confidence: Float
    let rect: CGRect

    var tapX: Double { Double(rect.midX) }
    var tapY: Double { Double(1.0 - rect.midY) }
}

private enum NAAutomationStore {
    static let key = "nextagent.savedAutomations.v1"

    static func load() -> [String: [[String: Any]]] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [String: [[String: Any]]] = [:]
        for (name, raw) in object {
            if let steps = raw as? [[String: Any]] { result[name] = steps }
        }
        return result
    }

    static func save(_ automations: [String: [[String: Any]]]) -> Bool {
        guard JSONSerialization.isValidJSONObject(automations),
              let data = try? JSONSerialization.data(withJSONObject: automations)
        else { return false }
        UserDefaults.standard.set(data, forKey: key)
        return true
    }
}

extension DeviceToolRegistry {
    @MainActor
    func executeV06(_ name: String, arguments: [String: Any], allowSensitive: Bool) async -> ToolResult? {
        switch name {
        case "screenshot":
            return RootDaemonClient.request(action: "screenshot")
        case "screen_ocr":
            return await v06OCRResult()
        case "find_text_on_screen":
            guard let needle = arguments["text"] as? String, !needle.isEmpty else { return v06BadArgs() }
            return await v06FindText(needle, contains: arguments["contains"] as? Bool ?? true)
        case "tap_text":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let needle = arguments["text"] as? String, !needle.isEmpty else { return v06BadArgs() }
            return await v06TapText(needle, contains: arguments["contains"] as? Bool ?? true)

        case "save_automation":
            guard let automationName = v06AutomationName(arguments["name"]),
                  let steps = arguments["steps"] as? [[String: Any]],
                  !steps.isEmpty, steps.count <= 40 else { return v06BadArgs() }
            var saved = NAAutomationStore.load()
            saved[automationName] = steps
            return NAAutomationStore.save(saved)
                ? v06JSON(["saved": automationName, "steps": steps.count])
                : ToolResult(success: false, output: "Could not save automation")
        case "list_automations":
            let saved = NAAutomationStore.load()
            let rows = saved.keys.sorted().map { ["name": $0, "steps": saved[$0]?.count ?? 0] as [String : Any] }
            return v06JSON(["automations": rows, "count": rows.count])
        case "run_saved_automation":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let automationName = v06AutomationName(arguments["name"]),
                  let steps = NAAutomationStore.load()[automationName] else {
                return ToolResult(success: false, output: "Saved automation not found")
            }
            return await executeV05("ui_automation", arguments: ["steps": steps], allowSensitive: true)
                ?? ToolResult(success: false, output: "UI automation engine unavailable")
        case "delete_automation":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let automationName = v06AutomationName(arguments["name"]) else { return v06BadArgs() }
            var saved = NAAutomationStore.load()
            guard saved.removeValue(forKey: automationName) != nil else {
                return ToolResult(success: false, output: "Saved automation not found")
            }
            return NAAutomationStore.save(saved)
                ? v06JSON(["deleted": automationName])
                : ToolResult(success: false, output: "Could not update automation store")

        case "file_search":
            guard let rawRoot = arguments["root"] as? String,
                  let root = v06AllowedMobilePath(rawRoot),
                  let query = arguments["query"] as? String,
                  !query.isEmpty else { return v06BadArgs() }
            let limit = max(1, min(250, (arguments["max_results"] as? NSNumber)?.intValue ?? 100))
            return await v06FileSearch(root: root, query: query, limit: limit)

        case "plist_read":
            guard let raw = arguments["path"] as? String,
                  let path = v06AllowedPlistPath(raw) else { return v06BadArgs() }
            return v06PlistRead(path)
        case "plist_set":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let raw = arguments["path"] as? String,
                  let path = v06AllowedPlistPath(raw),
                  let key = arguments["key"] as? String,
                  !key.isEmpty, key.count <= 256,
                  let value = arguments["value"] else { return v06BadArgs() }
            return v06PlistSet(path, key: key, value: value)

        case "archive_create":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let source = arguments["source"] as? String,
                  let destination = arguments["destination"] as? String else { return v06BadArgs() }
            return RootDaemonClient.request(action: "archive_create", argument: source + "\t" + destination)
        case "archive_extract":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let archive = arguments["archive"] as? String,
                  let destination = arguments["destination"] as? String else { return v06BadArgs() }
            return RootDaemonClient.request(action: "archive_extract", argument: archive + "\t" + destination)

        case "package_install":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let path = arguments["path"] as? String else { return v06BadArgs() }
            return RootDaemonClient.request(action: "package_install", argument: path)
        case "package_remove":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let package = arguments["package"] as? String else { return v06BadArgs() }
            return RootDaemonClient.request(action: "package_remove", argument: package)
        case "uicache_all":
            guard allowSensitive else { return v06SensitiveOff() }
            return RootDaemonClient.request(action: "uicache")
        case "respring":
            guard allowSensitive else { return v06SensitiveOff() }
            return RootDaemonClient.request(action: "respring")
        case "ldrestart":
            guard allowSensitive else { return v06SensitiveOff() }
            return RootDaemonClient.request(action: "ldrestart")
        case "userspace_reboot":
            guard allowSensitive else { return v06SensitiveOff() }
            return RootDaemonClient.request(action: "userspace_reboot")
        case "service_status":
            guard let label = arguments["label"] as? String else { return v06BadArgs() }
            return RootDaemonClient.request(action: "service_status", argument: label)
        case "service_start", "service_restart", "service_stop":
            guard allowSensitive else { return v06SensitiveOff() }
            guard let label = arguments["label"] as? String else { return v06BadArgs() }
            let daemonAction = name.replacingOccurrences(of: "service_", with: "service_")
            return RootDaemonClient.request(action: daemonAction, argument: label)

        case "battery_properties":
            return RootDaemonClient.request(action: "battery_properties")
        case "read_battery_plist":
            guard let path = arguments["path"] as? String else { return v06BadArgs() }
            return RootDaemonClient.request(action: "read_battery_plist", argument: path)

        default:
            return nil
        }
    }

    @MainActor
    private func v06CaptureOCR() async -> (ToolResult, [NAOCRHit]) {
        let capture = RootDaemonClient.request(action: "screenshot")
        guard capture.success else { return (capture, []) }

        guard let data = capture.output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["path"] as? String,
              let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let image = UIImage(data: imageData),
              let cg = image.cgImage else {
            return (ToolResult(success: false, output: "Screenshot was captured but could not be decoded"), [])
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return (ToolResult(success: false, output: "OCR failed: \(error.localizedDescription)"), [])
        }

        let hits: [NAOCRHit] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return NAOCRHit(text: candidate.string, confidence: candidate.confidence, rect: observation.boundingBox)
        }
        return (capture, hits)
    }

    @MainActor
    private func v06OCRResult() async -> ToolResult {
        let (capture, hits) = await v06CaptureOCR()
        guard capture.success else { return capture }

        let rows: [[String: Any]] = hits.prefix(250).map {
            [
                "text": $0.text,
                "confidence": Double($0.confidence),
                "tap_x": $0.tapX,
                "tap_y": $0.tapY,
                "width": Double($0.rect.width),
                "height": Double($0.rect.height)
            ]
        }
        return v06JSON(["recognized": rows, "count": rows.count])
    }

    @MainActor
    private func v06FindText(_ needle: String, contains: Bool) async -> ToolResult {
        let (capture, hits) = await v06CaptureOCR()
        guard capture.success else { return capture }

        let normalized = needle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matches = hits.filter {
            let candidate = $0.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return contains ? candidate.contains(normalized) : candidate == normalized
        }
        let rows: [[String: Any]] = matches.prefix(50).map {
            ["text": $0.text, "confidence": Double($0.confidence), "tap_x": $0.tapX, "tap_y": $0.tapY]
        }
        return v06JSON(["query": needle, "matches": rows, "count": rows.count])
    }

    @MainActor
    private func v06TapText(_ needle: String, contains: Bool) async -> ToolResult {
        let (capture, hits) = await v06CaptureOCR()
        guard capture.success else { return capture }

        let normalized = needle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let matches = hits.filter {
            let candidate = $0.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return contains ? candidate.contains(normalized) : candidate == normalized
        }
        guard let hit = matches.max(by: { $0.confidence < $1.confidence }) else {
            return ToolResult(success: false, output: "Text not found on the current screen")
        }
        let argument = String(format: "%.6f,%.6f", hit.tapX, hit.tapY)
        let tapped = RootDaemonClient.request(action: "tap", argument: argument)
        if tapped.success {
            return v06JSON(["tapped": hit.text, "tap_x": hit.tapX, "tap_y": hit.tapY, "confidence": Double(hit.confidence)])
        }
        return tapped
    }

    private func v06AutomationName(_ raw: Any?) -> String? {
        guard let value = raw as? String else { return nil }
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, !name.contains("\n"), !name.contains("\r") else { return nil }
        return name
    }

    private func v06AllowedMobilePath(_ raw: String) -> String? {
        let path = (raw as NSString).standardizingPath
        let home = NSHomeDirectory()
        if path == "/var/mobile" || path.hasPrefix("/var/mobile/") || path == home || path.hasPrefix(home + "/") {
            return path
        }
        return nil
    }

    private func v06AllowedPlistPath(_ raw: String) -> String? {
        guard let path = v06AllowedMobilePath(raw), path.lowercased().hasSuffix(".plist") else { return nil }
        if path.hasPrefix("/var/mobile/Library/Preferences/") || path.hasPrefix(NSHomeDirectory() + "/") { return path }
        return nil
    }

    private func v06FileSearch(root: String, query: String, limit: Int) async -> ToolResult {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                return ToolResult(success: false, output: "Could not enumerate search root")
            }

            var rows: [[String: Any]] = []
            let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if name.contains(needle) {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    rows.append([
                        "path": url.path,
                        "directory": values?.isDirectory ?? false,
                        "size": values?.fileSize ?? 0
                    ])
                    if rows.count >= limit { break }
                }
            }
            return v06JSONStatic(["query": query, "root": root, "results": rows, "count": rows.count])
        }.value
    }

    private func v06PlistRead(_ path: String) -> ToolResult {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), data.count <= 2_000_000 else {
            return ToolResult(success: false, output: "Plist is unavailable or exceeds 2 MB")
        }
        do {
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            guard JSONSerialization.isValidJSONObject(object) else {
                return ToolResult(success: false, output: "Plist contains values that are not JSON-compatible")
            }
            return v06JSON(["path": path, "contents": object])
        } catch {
            return ToolResult(success: false, output: "Plist decode failed: \(error.localizedDescription)")
        }
    }

    private func v06PlistSet(_ path: String, key: String, value: Any) -> ToolResult {
        var dictionary: [String: Any] = [:]
        if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            dictionary = object
        }
        dictionary[key] = value
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return v06JSON(["updated": path, "key": key])
        } catch {
            return ToolResult(success: false, output: "Plist write failed: \(error.localizedDescription)")
        }
    }

    private func v06JSON(_ object: Any) -> ToolResult {
        Self.v06JSONStatic(object)
    }

    private static func v06JSONStatic(_ object: Any) -> ToolResult {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return ToolResult(success: false, output: "Could not serialize result")
        }
        return ToolResult(success: true, output: text)
    }

    private func v06BadArgs() -> ToolResult { ToolResult(success: false, output: "Invalid or missing arguments") }
    private func v06SensitiveOff() -> ToolResult { ToolResult(success: false, output: "Sensitive actions are disabled in Next Agent Settings") }
}

private func v06JSONStatic(_ object: Any) -> ToolResult {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
          let text = String(data: data, encoding: .utf8) else {
        return ToolResult(success: false, output: "Could not serialize result")
    }
    return ToolResult(success: true, output: text)
}
