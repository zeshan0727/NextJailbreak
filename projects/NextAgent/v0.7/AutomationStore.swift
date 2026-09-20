import Foundation

final class AutomationRecorder {
    static let shared = AutomationRecorder()

    private let queue = DispatchQueue(label: "uk.zeshanbarvi.nextagent.automation-store")
    private let storePath = "/var/mobile/Library/NextAgent/automations.json"

    private var recordingName: String?
    private var recordedSteps: [[String: Any]] = []
    private var replayDepth = 0

    private let recordableTools: Set<String> = [
        "open_app",
        "open_apps_sequence",
        "tap",
        "double_tap",
        "long_press",
        "swipe",
        "type_text",
        "press_key",
        "press_button",
        "go_home",
        "go_back",
        "open_control_center",
        "open_notification_center",
        "wake_device"
    ]

    private init() {}

    var isRecording: Bool {
        queue.sync { recordingName != nil }
    }

    var currentRecordingName: String? {
        queue.sync { recordingName }
    }

    func start(name: String) -> [String: Any] {
        queue.sync {
            let clean = sanitizeName(name)
            guard !clean.isEmpty else {
                return ["success": false, "error": "Automation name cannot be empty"]
            }
            recordingName = clean
            recordedSteps = []
            return ["success": true, "recording": clean]
        }
    }

    func cancel() -> [String: Any] {
        queue.sync {
            let old = recordingName ?? ""
            recordingName = nil
            recordedSteps = []
            return ["success": true, "cancelled": old]
        }
    }

    func stop(save: Bool = true) -> [String: Any] {
        queue.sync {
            guard let name = recordingName else {
                return ["success": false, "error": "No automation recording is active"]
            }
            let steps = recordedSteps
            recordingName = nil
            recordedSteps = []

            if save {
                var all = loadStoreUnsafe()
                let record: [String: Any] = [
                    "name": name,
                    "updated_at": ISO8601DateFormatter().string(from: Date()),
                    "steps": steps
                ]
                if let index = all.firstIndex(where: { ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame }) {
                    all[index] = record
                } else {
                    all.append(record)
                }
                if !writeStoreUnsafe(all) {
                    return ["success": false, "error": "Could not save automation", "name": name, "steps": steps]
                }
            }

            return [
                "success": true,
                "name": name,
                "saved": save,
                "step_count": steps.count,
                "steps": steps
            ]
        }
    }

    func save(name: String, steps: [[String: Any]]) -> [String: Any] {
        queue.sync {
            let clean = sanitizeName(name)
            guard !clean.isEmpty, !steps.isEmpty, steps.count <= 80 else {
                return ["success": false, "error": "Invalid name or step count"]
            }
            guard JSONSerialization.isValidJSONObject(steps) else {
                return ["success": false, "error": "Automation steps are not JSON serializable"]
            }

            var all = loadStoreUnsafe()
            let record: [String: Any] = [
                "name": clean,
                "updated_at": ISO8601DateFormatter().string(from: Date()),
                "steps": steps
            ]
            if let index = all.firstIndex(where: { ($0["name"] as? String)?.caseInsensitiveCompare(clean) == .orderedSame }) {
                all[index] = record
            } else {
                all.append(record)
            }
            all = Array(all.prefix(100))
            return writeStoreUnsafe(all)
                ? ["success": true, "name": clean, "step_count": steps.count]
                : ["success": false, "error": "Could not save automation"]
        }
    }

    func list() -> [[String: Any]] {
        queue.sync {
            loadStoreUnsafe().map { item in
                let steps = item["steps"] as? [[String: Any]] ?? []
                return [
                    "name": item["name"] as? String ?? "Unnamed",
                    "updated_at": item["updated_at"] as? String ?? "",
                    "step_count": steps.count
                ]
            }
        }
    }

    func load(name: String) -> [[String: Any]]? {
        queue.sync {
            let all = loadStoreUnsafe()
            return all.first(where: {
                ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
            })?["steps"] as? [[String: Any]]
        }
    }

    func delete(name: String) -> [String: Any] {
        queue.sync {
            var all = loadStoreUnsafe()
            let original = all.count
            all.removeAll {
                ($0["name"] as? String)?.caseInsensitiveCompare(name) == .orderedSame
            }
            guard all.count != original else {
                return ["success": false, "error": "Automation not found"]
            }
            return writeStoreUnsafe(all)
                ? ["success": true, "deleted": name]
                : ["success": false, "error": "Could not update automation store"]
        }
    }

    func record(tool: String, arguments: [String: Any]) {
        queue.async {
            guard self.recordingName != nil, self.replayDepth == 0 else { return }

            if tool == "ui_automation",
               let steps = arguments["steps"] as? [[String: Any]] {
                for step in steps.prefix(80 - self.recordedSteps.count) {
                    if JSONSerialization.isValidJSONObject(step) {
                        self.recordedSteps.append(step)
                    }
                }
                return
            }

            guard self.recordableTools.contains(tool), self.recordedSteps.count < 80 else { return }

            var step = arguments
            step["action"] = tool
            if JSONSerialization.isValidJSONObject(step) {
                self.recordedSteps.append(step)
            }
        }
    }

    func beginReplay() {
        queue.sync { replayDepth += 1 }
    }

    func endReplay() {
        queue.sync { replayDepth = max(0, replayDepth - 1) }
    }

    private func sanitizeName(_ value: String) -> String {
        String(value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80))
    }

    private func loadStoreUnsafe() -> [[String: Any]] {
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: storePath)),
            let value = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return value
    }

    private func writeStoreUnsafe(_ value: [[String: Any]]) -> Bool {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted])
        else { return false }

        let dir = (storePath as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(
                atPath: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: URL(fileURLWithPath: storePath), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
