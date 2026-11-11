import Foundation

final class ProtectedSecretStore {
    static let shared = ProtectedSecretStore()
    private let queue = DispatchQueue(label: "com.nextsolution.dailyledger.protected-secrets")

    private init() {}

    func value(for key: String) -> String? {
        queue.sync {
            load()[key]
        }
    }

    func save(_ value: String, for key: String) throws {
        try queue.sync {
            var values = load()
            values[key] = value
            try write(values)
        }
    }

    func removeValue(for key: String) {
        try? queue.sync {
            var values = load()
            values.removeValue(forKey: key)
            try write(values)
        }
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return values
    }

    private func write(_ values: [String: String]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private var fileURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("DailyLedger", isDirectory: true)
            .appendingPathComponent("protected-secrets.json")
    }
}
