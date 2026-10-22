import Foundation

enum BrowserStore {
    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("browser-state.json")
    }

    static func load() -> BrowserSnapshot {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode(BrowserSnapshot.self, from: data) else {
            return BrowserSnapshot()
        }
        return value
    }

    static func save(_ snapshot: BrowserSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
