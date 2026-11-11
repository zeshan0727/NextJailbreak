import Foundation
import Darwin

final class LedgerDiskStore {
    static let shared = LedgerDiskStore()

    private let queue = DispatchQueue(label: "com.nextsolution.dailyledger.storage")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> LedgerData {
        queue.sync {
            withFileLock {
                loadUnlocked()
            }
        }
    }

    /// Export the authoritative ledger.json bytes. Never substitute the empty
    /// default LedgerData() on an unreadable file or missing storage.
    func verifiedBackupData() throws -> (data: Data, transactions: Int, accounts: Int) {
        try queue.sync {
            try withFileLock {
                let data = try Data(contentsOf: fileURL)
                let ledger = try decoder.decode(LedgerData.self, from: data)
                guard !ledger.transactions.isEmpty else {
                    throw BackupExportError.noTransactions
                }
                return (data, ledger.transactions.count, ledger.accounts.count)
            }
        }
    }

    func save(_ ledger: LedgerData) throws {
        try queue.sync {
            try withFileLock { try saveUnlocked(ledger) }
        }
    }

    @discardableResult
    func mutate(_ changes: (inout LedgerData) -> Void) throws -> LedgerData {
        try queue.sync {
            try withFileLock {
                var ledger = try loadForMutationUnlocked()
                changes(&ledger)
                ledger.normalize()
                try saveUnlocked(ledger)
                return ledger
            }
        }
    }

    @discardableResult
    func add(_ transaction: LedgerTransaction) throws -> LedgerData {
        try queue.sync {
            try withFileLock {
                var ledger = try loadForMutationUnlocked()
                guard !ledger.transactions.contains(where: { $0.id == transaction.id }) else {
                    return ledger
                }
                ledger.transactions.append(transaction)
                ledger.normalize()
                try saveUnlocked(ledger)
                return ledger
            }
        }
    }

    @discardableResult
    func merge(
        _ incoming: [LedgerTransaction],
        accounts incomingAccounts: [LedgerAccount] = [],
        restoring settings: LedgerSettings? = nil,
        fixedBudget: MonthlyFixedBudget? = nil
    ) throws -> LedgerData {
        try queue.sync {
            try withFileLock {
                var ledger = try loadForMutationUnlocked()
                if !incomingAccounts.isEmpty,
                   ledger.transactions.isEmpty,
                   ledger.accounts.count == 1,
                   ledger.accounts[0].id == LedgerAccount.legacyMainID {
                    ledger.accounts = []
                    ledger.settings.defaultAccountID = nil
                }
                let existingAccountIDs = Set(ledger.accounts.map(\.id))
                ledger.accounts.append(contentsOf: incomingAccounts.filter {
                    !existingAccountIDs.contains($0.id)
                })
                let existingIDs = Set(ledger.transactions.map(\.id))
                ledger.transactions.append(contentsOf: incoming.filter { !existingIDs.contains($0.id) })
                if let settings {
                    ledger.settings = settings
                }
                if let fixedBudget { ledger.fixedBudget = fixedBudget }
                ledger.normalize()
                try saveUnlocked(ledger)
                return ledger
            }
        }
    }

    private func withFileLock<T>(_ work: () throws -> T) rethrows -> T {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return try work() }
        setFileLock(descriptor, type: Int16(F_WRLCK), blocking: true)
        defer {
            setFileLock(descriptor, type: Int16(F_UNLCK), blocking: false)
            Darwin.close(descriptor)
        }
        return try work()
    }

    private func setFileLock(_ descriptor: Int32, type: Int16, blocking: Bool) {
        var lock = Darwin.flock()
        lock.l_type = type
        lock.l_whence = Int16(SEEK_SET)
        lock.l_start = 0
        lock.l_len = 0
        _ = Darwin.fcntl(descriptor, blocking ? F_SETLKW : F_SETLK, &lock)
    }

    private func loadUnlocked() -> LedgerData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(LedgerData.self, from: data) else {
            return LedgerData()
        }
        if data.range(of: Data("\"chartOfAccountsMigrationVersion\"".utf8)) == nil {
            try? saveUnlocked(decoded)
        }
        return decoded
    }

    // Never erase financial history merely because the ledger is unreadable.
    private func loadForMutationUnlocked() throws -> LedgerData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return LedgerData() }
        return try decoder.decode(LedgerData.self, from: Data(contentsOf: fileURL))
    }

    private func saveUnlocked(_ ledger: LedgerData) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        let data = try encoder.encode(ledger)
        try data.write(to: fileURL, options: .atomic)
        BackupSyncService.shared.ledgerDidSave(data)
        DispatchQueue.main.async {
            DeviceSyncService.shared.ledgerDidSave()
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private var fileURL: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root
            .appendingPathComponent("DailyLedger", isDirectory: true)
            .appendingPathComponent("ledger.json")
    }

    private var lockURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("ledger.lock")
    }
}

enum BackupExportError: LocalizedError {
    case noTransactions

    var errorDescription: String? {
        switch self {
        case .noTransactions:
            return "Your saved ledger has no transactions. Existing backups were preserved. Nothing was exported."
        }
    }
}
