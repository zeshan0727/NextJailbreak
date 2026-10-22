import XCTest
@testable import NovaBrowser

final class SessionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SessionStore!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = SessionStore(fileURL: directory.appendingPathComponent("session.json"))
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
    func testRoundTripPreservesRegularTabOrderAndSelection() throws {
        let records = [record("https://example.com"), record("https://apple.com")]
        try store.save(tabs: records, selectedID: records[1].id)
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.tabs, records)
        XCTAssertEqual(restored.selectedID, records[1].id)
    }
    func testPrivateURLNeverAppearsOnDisk() throws {
        let publicTab = record("https://example.com")
        let privateTab = record("https://private.example/secret", isPrivate: true)
        try store.save(tabs: [publicTab, privateTab], selectedID: privateTab.id)
        let bytes = try String(contentsOf: store.fileURL)
        XCTAssertFalse(bytes.contains("private.example"))
        XCTAssertFalse(bytes.contains(privateTab.id.uuidString))
        XCTAssertEqual(try store.load()?.selectedID, publicTab.id)
    }
    func testLocalFilesAreNeverRestored() throws {
        try store.save(tabs: [record("file:///tmp/test.html")], selectedID: nil)
        XCTAssertEqual(try store.load()?.tabs, [])
    }
    func testMissingAndCorruptSessionAreDistinct() throws {
        XCTAssertNil(try store.load())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }
    func testLoadFiltersPrivateAndDuplicateRecords() throws {
        let normal = record("https://example.com")
        let privateTab = record("https://private.example", isPrivate: true)
        let session = BrowserSession(selectedID: privateTab.id, tabs: [normal, normal, privateTab])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: store.fileURL)
        XCTAssertEqual(try store.load()?.tabs, [normal])
        XCTAssertEqual(try store.load()?.selectedID, normal.id)
    }
    func testClearRemovesPersistedSession() throws {
        try store.save(tabs: [record("https://example.com")], selectedID: nil)
        try store.clear()
        XCTAssertNil(try store.load())
    }
    private func record(_ address: String, isPrivate: Bool = false) -> TabRecord {
        TabRecord(id: UUID(), title: "Test", url: URL(string: address), isPrivate: isPrivate)
    }
}
