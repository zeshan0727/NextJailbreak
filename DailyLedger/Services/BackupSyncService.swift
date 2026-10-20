import BackgroundTasks
import Combine
import Foundation
import UIKit

/// Versioned backups; old populated snapshots are never overwritten by an empty ledger.
/// A complete off-device backup requires a valid cloud entitlement or linked provider.
final class BackupSyncService: ObservableObject {
    static let shared = BackupSyncService()
    static let taskIdentifier = "com.nextsolution.dailyledger.backup-refresh"
    static let maxBackupFiles = 10

    @Published private(set) var status = "Automatic backup is ready."
    @Published private(set) var lastBackupDate: Date?
    @Published private(set) var lastCloudBackupDate: Date?
    @Published private(set) var cloudDiagnostic = "iCloud connection not checked."

    private let backupQueue = DispatchQueue(
        label: "com.nextsolution.dailyledger.backup", qos: .utility
    )
    private var pendingBackup: DispatchWorkItem?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        lastBackupDate = UserDefaults.standard.object(forKey: "DailyLedgerLastBackupDate") as? Date
        lastCloudBackupDate = UserDefaults.standard.object(forKey: "DailyLedgerLastCloudBackupDate") as? Date
    }

    /// Called after every persisted ledger write (including SMS imports).
    /// Coalesces rapid changes; snapshots are never written before ledger.json.
    func ledgerDidSave(_ data: Data) {
        pendingBackup?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveSnapshot(data, includeICloud: UserDefaults.standard.bool(
                forKey: "DailyLedgerICloudSync"
            ))
        }
        pendingBackup = work
        backupQueue.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Back up the actual on-disk data, not LedgerDiskStore.load()'s empty fallback
    /// if ledger decoding fails. This avoids reproducing the original data-loss bug.
    /// Check account availability separately from local backup completion.
    /// An Apple-provisioned container is mandatory for automatic iCloud backups.
    func refreshCloudDiagnostics() {
        backupQueue.async { [weak self] in
            guard let self else { return }
            let manager = FileManager.default
            let status: String
            if manager.ubiquityIdentityToken == nil {
                status = "iCloud is unavailable to this app. Sign into iCloud, enable iCloud Drive, and verify the signed app's iCloud entitlement."
            } else if manager.url(forUbiquityContainerIdentifier:
                                    "iCloud.com.nextsolution.dailyledger") == nil {
                status = "iCloud account detected, but Next Ledger's container is inaccessible. Verify the IPA's final signed CloudDocuments entitlement and matching provisioning profile."
            } else {
                status = "iCloud Documents container accessible. File creation can proceed; remote upload is not yet verified."
            }
            DispatchQueue.main.async {
                self.cloudDiagnostic = status
            }
        }
    }

    func backupOnAppOpen() {
        backupQueue.async { [weak self] in
            guard let self else { return }
            let url = FileManager.default.urls(for: .applicationSupportDirectory,
                                                in: .userDomainMask)[0]
                .appendingPathComponent("DailyLedger/ledger.json")
            guard let data = try? Data(contentsOf: url) else { return }
            self.saveSnapshot(data, includeICloud: UserDefaults.standard.bool(
                forKey: "DailyLedgerICloudSync"
            ))
        }
    }

    func syncNow(ledger: LedgerData) {
        do {
            let data = try encoder.encode(ledger)
            backupQueue.async { [weak self] in
                self?.saveSnapshot(data, includeICloud: true)
            }
        } catch {
            publishBackupStatus("Backup could not be encoded: \(error.localizedDescription)",
                                localDate: nil, cloudDate: nil)
        }
    }

    /// Keep the existing Restore Latest flow working. A legacy one-file backup
    /// remains readable even before the first rotating snapshot.
    func restoreLatestICloudBackup() throws -> LedgerData {
        guard let url = iCloudBackupURL,
              FileManager.default.fileExists(atPath: url.path) else {
            throw BackupSyncError.iCloudBackupUnavailable
        }
        return try decoder.decode(LedgerData.self, from: Data(contentsOf: url))
    }

    func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func handleDidEnterBackground(ledger: LedgerData) {
        var taskID = UIBackgroundTaskIdentifier.invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "DailyLedgerBackup") {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
                taskID = .invalid
            }
        }
        syncNow(ledger: ledger)
        scheduleBackgroundRefresh()
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) {
            [weak self] task in
            guard let self, let refresh = task as? BGAppRefreshTask else { return }
            // Read actual JSON so a decoder error never creates a blank backup.
            self.backupOnAppOpen()
            refresh.setTaskCompleted(success: true)
            self.scheduleBackgroundRefresh()
        }
    }

    private func saveSnapshot(_ data: Data, includeICloud: Bool) {
        let ledger: LedgerData
        do {
            ledger = try decoder.decode(LedgerData.self, from: data)
        } catch {
            publishBackupStatus("Automatic backup refused: ledger JSON is unreadable.",
                                localDate: nil, cloudDate: nil)
            return
        }
        // Protect history. Do not roll off good snapshots with an accidental
        // empty restore or fresh-app placeholder; zero transactions are not backed up.
        guard !ledger.transactions.isEmpty else {
            publishBackupStatus("No transactions: existing backups were preserved.",
                                localDate: nil, cloudDate: nil)
            return
        }

        let now = Date()
        do {
            try rotateAndWrite(data, in: localBackupURL.deletingLastPathComponent())
            UserDefaults.standard.set(now, forKey: "DailyLedgerLastBackupDate")
        } catch {
            publishBackupStatus("Local backup failed: \(error.localizedDescription)",
                                localDate: nil, cloudDate: nil)
            return
        }

        guard includeICloud else {
            publishBackupStatus("Saved locally (10-backup history). Link a cloud destination for off-device copies.",
                                localDate: now, cloudDate: nil)
            return
        }
        guard let url = iCloudBackupURL else {
            publishBackupStatus(
                "10 local backups retained. iCloud unavailable: Apple-provisioned CloudDocuments entitlement is required.",
                localDate: now, cloudDate: nil
            )
            return
        }
        do {
            try rotateAndWrite(data, in: url.deletingLastPathComponent())
            UserDefaults.standard.set(now, forKey: "DailyLedgerLastCloudBackupDate")
            publishBackupStatus(
                "Saved locally and submitted to iCloud Drive (up to 10 backup files each). iCloud transfer may still be pending.",
                localDate: now, cloudDate: now
            )
        } catch {
            publishBackupStatus("Local backup saved; iCloud write failed: \(error.localizedDescription)",
                                localDate: now, cloudDate: nil)
        }
    }

    /// At most one Latest + nine previous versions per destination.
    /// Pruning happens only AFTER the new Latest passes a read/decoding check.
    private func rotateAndWrite(_ data: Data, in directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let latest = directory.appendingPathComponent("Latest-DailyLedger-Backup.json")
        let previous = try? Data(contentsOf: latest)
        if let old = previous, old != data,
           let oldLedger = try? decoder.decode(LedgerData.self, from: old),
           !oldLedger.transactions.isEmpty {
            let archiveName = "DailyLedger-History-" +
                ISO8601DateFormatter().string(from: Date())
                    .replacingOccurrences(of: ":", with: "-") +
                "-" + String(UUID().uuidString.prefix(8)) + ".json"
            try old.write(to: directory.appendingPathComponent(archiveName), options: .atomic)
        }
        try data.write(to: latest, options: .atomic)
        // Ensure the newest file exists and is readable before any deletion.
        let verified = try decoder.decode(LedgerData.self, from: Data(contentsOf: latest))
        guard !verified.transactions.isEmpty else {
            throw BackupSyncError.invalidBackup
        }
        let histories = try fm.contentsOfDirectory(at: directory,
                                                   includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("DailyLedger-History-") &&
                      $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in histories.dropFirst(Self.maxBackupFiles - 1) {
            try fm.removeItem(at: old)
        }
    }

    private func publishBackupStatus(_ message: String, localDate: Date?, cloudDate: Date?) {
        DispatchQueue.main.async {
            self.status = message
            if let localDate { self.lastBackupDate = localDate }
            if let cloudDate { self.lastCloudBackupDate = cloudDate }
        }
    }

    private var localBackupURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DailyLedger/Backups/Latest-DailyLedger-Backup.json")
    }

    private var iCloudBackupURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.nextsolution.dailyledger")?
            .appendingPathComponent("Documents/DailyLedger/Latest-DailyLedger-Backup.json")
    }
}

enum BackupSyncError: LocalizedError {
    case iCloudBackupUnavailable
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .iCloudBackupUnavailable:
            return "iCloud Drive backup is missing or this signed build lacks an iCloud entitlement."
        case .invalidBackup:
            return "Backup failed integrity validation; older snapshots were not deleted."
        }
    }
}
