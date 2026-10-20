import Combine
import Foundation

/// Separate from rotating backups: each device owns one iCloud Documents
/// snapshot, so an older phone never overwrites another phone's backup.
/// Version 1 is intentionally additive; matching IDs with different content
/// are conflicts, not permission to delete or overwrite financial records.
private struct LedgerDeviceSnapshot: Codable {
    let schema: Int
    let deviceID: UUID
    let writtenAt: Date
    let ledger: LedgerData
}

private struct DeviceSyncPullResult {
    var transactions: [LedgerTransaction] = []
    var accounts: [LedgerAccount] = []
    var initialSettings: LedgerSettings?
    var initialBudget: MonthlyFixedBudget?
    var conflicts = 0
    var pendingDownloads = 0
    var remoteDevices = 0
}

/// Same Apple ID, same explicit CloudDocuments container, independent device
/// files and non-destructive union by transaction/account UUID.
final class DeviceSyncService: NSObject, ObservableObject {
    static let shared = DeviceSyncService()
    static let enabledKey = "DailyLedgerDeviceSyncEnabled"
    private static let containerID = "iCloud.com.nextsolution.dailyledger"

    @Published private(set) var status = "Device sync is off. Your existing iCloud backups are unchanged."
    @Published private(set) var lastSuccessfulPull: Date?
    @Published private(set) var remoteDeviceCount = 0
    @Published private(set) var conflictCount = 0
    @Published private(set) var lastAddedTransactions = 0
    @Published private(set) var lastAddedAccounts = 0

    private weak var store: LedgerStore?
    private let queue = DispatchQueue(label: "com.nextsolution.dailyledger.device-sync", qos: .utility)
    private var query: NSMetadataQuery?
    private var writeWork: DispatchWorkItem?
    private var lastPublishedData: Data?

    private lazy var deviceID: UUID = {
        let key = "DailyLedgerDeviceSyncIdentity"
        if let raw = UserDefaults.standard.string(forKey: key),
           let value = UUID(uuidString: raw) { return value }
        let created = UUID()
        UserDefaults.standard.set(created.uuidString, forKey: key)
        return created
    }()

    private override init() { super.init() }

    /// Called on the main thread when the application/scene becomes active.
    func start(store: LedgerStore) {
        self.store = store
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else {
            stopQuery()
            status = "Device sync is off. iCloud backup remains available."
            return
        }
        startQueryIfNeeded()
        syncNow()
    }

    func setEnabled(_ enabled: Bool, store: LedgerStore) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        start(store: store)
    }

    /// LedgerDiskStore dispatches this onto the main queue *after* its own
    /// atomic file save. Merging remote records triggers a coalesced publication.
    func ledgerDidSave() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        writeWork?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.performCycle()
        }
        writeWork = task
        queue.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    func syncNow() {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else {
            status = "Turn on Sync Across Devices first. Automatic iCloud backup is separate."
            return
        }
        status = "Checking this device and other iCloud devices…"
        queue.async { [weak self] in self?.performCycle() }
    }

    private func startQueryIfNeeded() {
        guard query == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        q.predicate = NSPredicate(format: "%K ENDSWITH[c] %@", NSMetadataItemFSNameKey, ".json")
        NotificationCenter.default.addObserver(
            self, selector: #selector(metadataChanged(_:)),
            name: .NSMetadataQueryDidFinishGathering, object: q
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(metadataChanged(_:)),
            name: .NSMetadataQueryDidUpdate, object: q
        )
        query = q
        _ = q.start()
    }

    private func stopQuery() {
        guard let q = query else { return }
        q.stop()
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: q)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: q)
        query = nil
    }

    @objc private func metadataChanged(_ notice: Notification) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        guard let q = query else { return }
        // Collect discovered remote URL values on the query's main thread.
        q.disableUpdates()
        let urls = q.results.compactMap { ($0 as? NSMetadataItem)?
            .value(forAttribute: NSMetadataItemURLKey) as? URL }
            .filter { $0.path.contains("/DailyLedger/DeviceSync/") }
        q.enableUpdates()
        queue.async { [weak self] in self?.performCycle(discovered: urls) }
    }

    private func performCycle(discovered: [URL] = []) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        let fm = FileManager.default
        guard fm.ubiquityIdentityToken != nil,
              let root = fm.url(forUbiquityContainerIdentifier: Self.containerID) else {
            report("This device cannot access the Next Ledger iCloud container. Check the Apple ID, iCloud Drive and final signed CloudDocuments entitlement.")
            return
        }
        let directory = root.appendingPathComponent("Documents/DailyLedger/DeviceSync", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let local = LedgerDiskStore.shared.load()
            // Never upload an empty placeholder, even from a freshly installed device.
            if !local.transactions.isEmpty {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let fingerprint = try encoder.encode(local)
                let destination = directory.appendingPathComponent("device-" + deviceID.uuidString + ".json")
                // The metadata query also sees our own writes. Without
                // content deduplication an own-file notification triggers
                // endless re-uploads and unnecessary battery/network use.
                if lastPublishedData != fingerprint || !fm.fileExists(atPath: destination.path) {
                    let snapshot = LedgerDeviceSnapshot(schema: 1, deviceID: deviceID,
                                                        writtenAt: Date(), ledger: local)
                    let data = try encoder.encode(snapshot)
                    try data.write(to: destination, options: .atomic)
                    lastPublishedData = fingerprint
                }
            }

            let listed = (try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            let urls = Array(Set((listed + discovered).filter {
                $0.pathExtension.lowercased() == "json" &&
                $0.lastPathComponent.hasPrefix("device-") &&
                $0.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
            })).sorted { $0.lastPathComponent < $1.lastPathComponent }

            var snapshots: [LedgerDeviceSnapshot] = []
            var pending = 0
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            for url in urls {
                if url.lastPathComponent == "device-" + deviceID.uuidString + ".json" { continue }
                let values = try? url.resourceValues(forKeys: [
                    .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey
                ])
                if values?.isUbiquitousItem == true,
                   values?.ubiquitousItemDownloadingStatus != .current {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                    pending += 1
                    continue
                }
                // Remote files may be temporarily unavailable while iCloud
                // is downloading. Never treat an unreadable file as empty.
                guard let data = try? Data(contentsOf: url),
                      let snapshot = try? decoder.decode(LedgerDeviceSnapshot.self, from: data),
                      snapshot.schema == 1, snapshot.deviceID != deviceID,
                      !snapshot.ledger.transactions.isEmpty,
                      url.lastPathComponent == "device-" + snapshot.deviceID.uuidString + ".json" else {
                    pending += 1
                    continue
                }
                snapshots.append(snapshot)
            }
            snapshots.sort {
                if $0.writtenAt != $1.writtenAt { return $0.writtenAt > $1.writtenAt }
                return $0.deviceID.uuidString < $1.deviceID.uuidString
            }
            var current = local
            var importedTransactions = 0
            var importedAccounts = 0
            var conflicts = 0
            let peers = Set(snapshots.map(\.deviceID)).count

            for snapshot in snapshots {
                let ownedTransactions = Dictionary(uniqueKeysWithValues: current.transactions.map { ($0.id, $0) })
                let ownedAccounts = Dictionary(uniqueKeysWithValues: current.accounts.map { ($0.id, $0) })
                let incomingTransactions = snapshot.ledger.transactions.filter { item in
                    if let prior = ownedTransactions[item.id] {
                        if prior != item { conflicts += 1 }
                        return false
                    }
                    return true
                }
                let incomingAccounts = snapshot.ledger.accounts.filter { item in
                    if let prior = ownedAccounts[item.id] {
                        if prior != item { conflicts += 1 }
                        return false
                    }
                    return true
                }
                if incomingTransactions.isEmpty && incomingAccounts.isEmpty { continue }

                // Settings / budget are seeded once on a fresh device, never
                // silently overwritten on an already-populated device.
                let isFresh = current.transactions.isEmpty &&
                    current.accounts.count == 1 &&
                    current.accounts[0].id == LedgerAccount.legacyMainID
                let merged = try LedgerDiskStore.shared.merge(
                    incomingTransactions, accounts: incomingAccounts,
                    restoring: isFresh ? snapshot.ledger.settings : nil,
                    fixedBudget: isFresh ? snapshot.ledger.fixedBudget : nil
                )
                importedTransactions += merged.transactions.count - current.transactions.count
                importedAccounts += merged.accounts.count - (isFresh ? 0 : current.accounts.count)
                current = merged
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.remoteDeviceCount = peers
                self.conflictCount = conflicts
                self.lastAddedTransactions = importedTransactions
                self.lastAddedAccounts = max(importedAccounts, 0)
                if importedTransactions > 0 || importedAccounts > 0 {
                    self.store?.reload()
                }
                if peers > 0 { self.lastSuccessfulPull = Date() }
                let conflictsNote = conflicts > 0
                    ? " \(conflicts) different edits share an ID and were NOT overwritten."
                    : ""
                self.status = "Device sync checked: \(peers) peer(s), added \(importedTransactions) transactions and \(max(0, importedAccounts)) accounts." +
                    (pending > 0 ? " Waiting for \(pending) iCloud file(s) to download." : "") +
                    conflictsNote
            }
        } catch {
            report("Device sync could not complete: \(error.localizedDescription). Local records were not erased.")
        }
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.status = message }
    }
}
