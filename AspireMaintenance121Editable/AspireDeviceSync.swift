import Foundation

// Device-specific change journals prevent two phones from rewriting the same iCloud file.
// Records are merged by stable UUID, and deletions travel as tombstones.
struct AspireSyncChange: Codable {
    var deviceID: String
    var changedAt: Date
    var sequence: Int64
    var removed: Bool
    var jsonValue: String?

    func supersedes(_ other: AspireSyncChange) -> Bool {
        if changedAt != other.changedAt { return changedAt > other.changedAt }
        if deviceID == other.deviceID { return sequence > other.sequence }
        return deviceID > other.deviceID
    }
}

struct AspireSyncJournal: Codable {
    var format = 1
    var deviceID: String
    var changes: [String: AspireSyncChange]
}

struct AspireSyncLedger: Codable {
    var deviceID: String
    var sequence: Int64 = 0
    var localChanges: [String: AspireSyncChange] = [:]
    var winners: [String: AspireSyncChange] = [:]
    var lastObserved: [String: String] = [:]
    var initialized = false
}

enum AspireSyncCodec {
    // All these arrays have permanent UUID identifiers in the existing Aspire models.
    static let recordArrays: Set<String> = [
        "customers", "visits", "invoices", "expenses", "employees", "bankAccounts",
        "advancePayments", "expenseRefunds", "catalogItems", "quotations", "visitSchedules"
    ]

    static func jsonDictionary(from data: AspireData) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        let blob = try encoder.encode(data)
        guard let dictionary = try JSONSerialization.jsonObject(with: blob) as? [String: Any] else {
            throw AspireSyncError.invalidData
        }
        return dictionary
    }

    static func flatten(_ data: AspireData) throws -> [String: String] {
        var result: [String: String] = [:]
        for (field, value) in try jsonDictionary(from: data) {
            if recordArrays.contains(field), let array = value as? [[String: Any]] {
                for item in array {
                    guard let id = item["id"] as? String else { throw AspireSyncError.invalidData }
                    result["\(field)|\(id)"] = try serialize(item)
                }
            } else {
                result["\(field)|@"] = try serialize(value)
            }
        }
        return result
    }

    static func applying(_ changes: [String: AspireSyncChange], to current: AspireData) throws -> AspireData {
        var result = try jsonDictionary(from: current)
        for key in changes.keys.sorted() {
            guard let change = changes[key],
                  let separator = key.firstIndex(of: "|") else { continue }
            let field = String(key[..<separator])
            let identifier = String(key[key.index(after: separator)...])
            if recordArrays.contains(field), identifier != "@" {
                var array = result[field] as? [[String: Any]] ?? []
                array.removeAll { ($0["id"] as? String) == identifier }
                if !change.removed {
                    guard let raw = change.jsonValue,
                          let object = try JSONSerialization.jsonObject(
                            with: Data(raw.utf8), options: [.fragmentsAllowed]
                          ) as? [String: Any],
                          object["id"] as? String == identifier else {
                        throw AspireSyncError.invalidData
                    }
                    array.append(object)
                }
                result[field] = array
            } else if identifier == "@" {
                if change.removed {
                    result.removeValue(forKey: field)
                } else {
                    guard let raw = change.jsonValue else { throw AspireSyncError.invalidData }
                    result[field] = try JSONSerialization.jsonObject(
                        with: Data(raw.utf8), options: [.fragmentsAllowed]
                    )
                }
            }
        }
        let encoded = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AspireData.self, from: encoded)
    }

    private static func serialize(_ value: Any) throws -> String {
        let bytes = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        guard let text = String(data: bytes, encoding: .utf8) else { throw AspireSyncError.invalidData }
        return text
    }
}

enum AspireSyncError: LocalizedError {
    case unavailable
    case invalidData
    case stillGathering

    var errorDescription: String? {
        switch self {
        case .unavailable: return "iCloud Drive is not available for this app."
        case .invalidData: return "A sync file could not be decoded safely."
        case .stillGathering: return "Waiting for iCloud to list your device files."
        }
    }
}

struct AspireSyncScan {
    var documents: [AspireSyncJournal]
    var downloadsPending: Bool
}

final class AspireDeviceSyncService {
    static let shared = AspireDeviceSyncService()
    private let fileManager = FileManager.default
    private let containerID = "iCloud.com.aspiregroup.maintenance"
    private let queue = DispatchQueue(label: "com.aspiregroup.maintenance.devicesync.io", qos: .utility)
    private var query: NSMetadataQuery?
    private var tokens: [NSObjectProtocol] = []
    private var readHandler: ((Result<AspireSyncScan, Error>) -> Void)?

    private init() {}

    // NSMetadataQuery must run on a thread with an active run loop (main).
    func start(_ onRead: @escaping (Result<AspireSyncScan, Error>) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopOnMain()
            self.readHandler = onRead
            guard self.fileManager.ubiquityIdentityToken != nil,
                  self.fileManager.url(forUbiquityContainerIdentifier: self.containerID) != nil else {
                onRead(.failure(AspireSyncError.unavailable))
                return
            }
            let search = NSMetadataQuery()
            search.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            search.predicate = NSPredicate(format: "%K ENDSWITH %@", NSMetadataItemFSNameKey, ".json")
            search.notificationBatchingInterval = 1
            let center = NotificationCenter.default
            self.tokens.append(center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: search, queue: .main
            ) { [weak self] _ in self?.readIndexedFiles() })
            self.tokens.append(center.addObserver(
                forName: .NSMetadataQueryDidUpdate, object: search, queue: .main
            ) { [weak self] _ in self?.readIndexedFiles() })
            self.query = search
            if !search.start() {
                self.stopOnMain()
                onRead(.failure(AspireSyncError.stillGathering))
            }
        }
    }

    func refresh() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let query = self.query, query.isGathering {
                self.readHandler?(.failure(AspireSyncError.stillGathering))
            } else {
                self.readIndexedFiles()
            }
        }
    }

    func stop() { DispatchQueue.main.async { [weak self] in self?.stopOnMain() } }

    private func stopOnMain() {
        query?.stop()
        query = nil
        let center = NotificationCenter.default
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
        readHandler = nil
    }

    private func readIndexedFiles() {
        guard let search = query, !search.isGathering else { return }
        search.disableUpdates()
        let urls = search.results.compactMap { item -> URL? in
            (item as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL
        }.filter {
            $0.path.contains("/Aspire Maintenance/Sync/devices/") &&
            $0.pathExtension.lowercased() == "json"
        }
        search.enableUpdates()
        queue.async { [weak self] in
            guard let self else { return }
            var documents: [AspireSyncJournal] = []
            var pending = false
            for url in urls {
                do {
                    let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if values.ubiquitousItemDownloadingStatus != URLUbiquitousItemDownloadingStatus.current {
                        try? self.fileManager.startDownloadingUbiquitousItem(at: url)
                        pending = true
                        continue
                    }
                    var coordinationError: NSError?
                    var readError: Error?
                    var content: Data?
                    let coordinator = NSFileCoordinator(filePresenter: nil)
                    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
                        do { content = try Data(contentsOf: coordinatedURL) }
                        catch { readError = error }
                    }
                    if let error = coordinationError ?? (readError as NSError?) { throw error }
                    guard let content else { throw AspireSyncError.invalidData }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let doc = try decoder.decode(AspireSyncJournal.self, from: content)
                    guard doc.format == 1 else { throw AspireSyncError.invalidData }
                    documents.append(doc)
                } catch {
                    // Do not import partial or malformed remote data as an empty database.
                    DispatchQueue.main.async { [weak self] in self?.readHandler?(.failure(error)) }
                    return
                }
            }
            let scan = AspireSyncScan(documents: documents, downloadsPending: pending)
            DispatchQueue.main.async { [weak self] in self?.readHandler?(.success(scan)) }
        }
    }

    func publish(_ journal: AspireSyncJournal, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                guard self.fileManager.ubiquityIdentityToken != nil,
                      let root = self.fileManager.url(forUbiquityContainerIdentifier: self.containerID) else {
                    throw AspireSyncError.unavailable
                }
                let directory = root
                    .appendingPathComponent("Documents", isDirectory: true)
                    .appendingPathComponent("Aspire Maintenance", isDirectory: true)
                    .appendingPathComponent("Sync", isDirectory: true)
                    .appendingPathComponent("devices", isDirectory: true)
                try self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = directory.appendingPathComponent(journal.deviceID + ".json")
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                let bytes = try encoder.encode(journal)
                var coordinationError: NSError?
                var writeError: Error?
                let coordinator = NSFileCoordinator(filePresenter: nil)
                let options: NSFileCoordinator.WritingOptions = self.fileManager.fileExists(atPath: target.path)
                    ? [.forReplacing] : []
                coordinator.coordinate(writingItemAt: target, options: options, error: &coordinationError) { url in
                    do { try bytes.write(to: url, options: .atomic) }
                    catch { writeError = error }
                }
                if let error = coordinationError ?? (writeError as NSError?) { throw error }
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
