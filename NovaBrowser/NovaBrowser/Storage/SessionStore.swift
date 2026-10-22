import Foundation

struct TabRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var url: URL?
    var isPrivate: Bool
}

struct BrowserSession: Codable, Equatable {
    var version = 1
    var selectedID: UUID?
    var tabs: [TabRecord]
}

struct SessionStore {
    let fileURL: URL
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NovaBrowser", isDirectory: true).appendingPathComponent("session.json")
    }
    func load() throws -> BrowserSession? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoded = try JSONDecoder().decode(BrowserSession.self, from: Data(contentsOf: fileURL))
        guard decoded.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        var seen = Set<UUID>()
        let tabs = decoded.tabs.filter { record in
            !record.isPrivate && seen.insert(record.id).inserted &&
            (record.url == nil || ["https", "http"].contains(record.url?.scheme?.lowercased() ?? ""))
        }
        return BrowserSession(selectedID: tabs.contains(where: { $0.id == decoded.selectedID }) ? decoded.selectedID : tabs.first?.id, tabs: tabs)
    }
    func save(tabs: [TabRecord], selectedID: UUID?) throws {
        let publicTabs = tabs.filter { !$0.isPrivate && ($0.url == nil || ["https", "http"].contains($0.url?.scheme ?? "")) }
        let selected = publicTabs.contains { $0.id == selectedID } ? selectedID : publicTabs.first?.id
        let data = try JSONEncoder().encode(BrowserSession(selectedID: selected, tabs: publicTabs))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
}
