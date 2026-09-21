import Foundation
import SQLite3
import ZIPFoundation

private let SQLITE_TRANSIENT_MOBILE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct MobileEntity: Identifiable, Hashable {
    let id: Int64
    let name: String
}

struct SyncedFile: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let relativePath: String
    let size: Int64
}

struct SyncResult {
    let databaseURL: URL
    let snapshotRoot: URL
    let sourceURL: URL
    let sourceModified: Date?
    let sourceName: String
}

final class SQLiteReadStore {
    private var db: OpaquePointer?
    let url: URL

    init(url: URL) throws {
        self.url = url
        var ptr: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &ptr, flags, nil) == SQLITE_OK, let opened = ptr else {
            let message = ptr.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unable to open database"
            if let ptr { sqlite3_close(ptr) }
            throw NSError(domain: "AccountantsMobile.SQLite", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        db = opened
        sqlite3_busy_timeout(opened, 4000)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func tableExists(_ name: String) -> Bool {
        (try? scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?;", [name])) != "0"
    }

    func scalar(_ sql: String, _ args: [String] = []) throws -> String {
        let rows = try query(sql, args)
        guard let first = rows.first, let value = first.values.first else { return "" }
        return value
    }

    func query(_ sql: String, _ args: [String] = []) throws -> [[String: String]] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw sqliteError(db)
        }
        defer { sqlite3_finalize(stmt) }

        for (index, value) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), value, -1, SQLITE_TRANSIENT_MOBILE)
        }

        var result: [[String: String]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw sqliteError(db) }

            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let key = sqlite3_column_name(stmt, i).map { String(cString: $0) } ?? "Column"
                let type = sqlite3_column_type(stmt, i)
                switch type {
                case SQLITE_INTEGER:
                    row[key] = String(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[key] = String(format: "%.2f", sqlite3_column_double(stmt, i))
                case SQLITE_TEXT:
                    row[key] = sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? ""
                case SQLITE_NULL:
                    row[key] = ""
                default:
                    if let blob = sqlite3_column_blob(stmt, i) {
                        row[key] = "<\(sqlite3_column_bytes(stmt, i)) bytes @ \(blob)>"
                    } else {
                        row[key] = ""
                    }
                }
            }
            result.append(row)
        }
        return result
    }

    private func sqliteError(_ db: OpaquePointer) -> NSError {
        let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "SQLite error"
        return NSError(domain: "AccountantsMobile.SQLite", code: Int(sqlite3_errcode(db)), userInfo: [NSLocalizedDescriptionKey: message])
    }
}

enum BackupSyncService {
    static let fullBackupPrefix = "Accountants5_FULL_"

    static func sync(from cloudFolder: URL) throws -> SyncResult {
        let fm = FileManager.default
        let candidates = findBackups(in: cloudFolder)
        guard let newest = candidates.sorted(by: backupSort).first else {
            throw NSError(
                domain: "AccountantsMobile.Sync",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No Accountants5_FULL_*.zip backup was found in the selected cloud folder."]
            )
        }

        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("AccountantsMobile", isDirectory: true)
        try fm.createDirectory(at: support, withIntermediateDirectories: true)

        let fingerprint = backupFingerprint(newest)
        let snapshot = support.appendingPathComponent("Snapshot-\(fingerprint)", isDirectory: true)
        let dbURL = snapshot.appendingPathComponent("Data/AccountantsNext.db")

        if !fm.fileExists(atPath: dbURL.path) {
            let stagingZip = support.appendingPathComponent("incoming-\(UUID().uuidString).zip")
            defer { try? fm.removeItem(at: stagingZip) }

            var coordinationError: NSError?
            var copyError: Error?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            coordinator.coordinate(readingItemAt: newest, options: [], error: &coordinationError) { coordinatedURL in
                do {
                    if fm.fileExists(atPath: stagingZip.path) { try fm.removeItem(at: stagingZip) }
                    try fm.copyItem(at: coordinatedURL, to: stagingZip)
                } catch {
                    copyError = error
                }
            }
            if let coordinationError { throw coordinationError }
            if let copyError { throw copyError }

            let temp = support.appendingPathComponent("Extract-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            do {
                try fm.unzipItem(at: stagingZip, to: temp)
                guard fm.fileExists(atPath: temp.appendingPathComponent("Data/AccountantsNext.db").path) else {
                    throw NSError(
                        domain: "AccountantsMobile.Sync",
                        code: 422,
                        userInfo: [NSLocalizedDescriptionKey: "The selected backup does not contain Data/AccountantsNext.db."]
                    )
                }
                if fm.fileExists(atPath: snapshot.path) { try fm.removeItem(at: snapshot) }
                try fm.moveItem(at: temp, to: snapshot)
            } catch {
                try? fm.removeItem(at: temp)
                throw error
            }

            pruneSnapshots(in: support, keeping: 3)
        }

        let values = try? newest.resourceValues(forKeys: [.contentModificationDateKey])
        return SyncResult(
            databaseURL: dbURL,
            snapshotRoot: snapshot,
            sourceURL: newest,
            sourceModified: values?.contentModificationDate,
            sourceName: newest.lastPathComponent
        )
    }

    private static func findBackups(in root: URL) -> [URL] {
        var result: [URL] = []
        var queue: [URL] = [root]
        var visited = 0
        let fm = FileManager.default

        while let folder = queue.first, visited < 8000 {
            queue.removeFirst()
            visited += 1
            let items = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for item in items {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    queue.append(item)
                } else if item.pathExtension.lowercased() == "zip" &&
                            item.lastPathComponent.hasPrefix(fullBackupPrefix) {
                    result.append(item)
                }
            }
        }
        return result
    }

    private static func backupSort(_ lhs: URL, _ rhs: URL) -> Bool {
        let lk = backupTimestampKey(lhs.lastPathComponent)
        let rk = backupTimestampKey(rhs.lastPathComponent)
        if lk != rk { return lk > rk }
        let ld = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let rd = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        return ld > rd
    }

    private static func backupTimestampKey(_ name: String) -> String {
        let digits = name.filter(\.isNumber)
        return String(digits.suffix(14))
    }

    private static func backupFingerprint(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let time = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        let clean = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "\(clean)-\(size)-\(time)"
    }

    private static func pruneSnapshots(in support: URL, keeping: Int) {
        let fm = FileManager.default
        let folders = ((try? fm.contentsOfDirectory(
            at: support,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []).filter {
            $0.lastPathComponent.hasPrefix("Snapshot-") &&
            ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }.sorted {
            let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return a > b
        }

        for old in folders.dropFirst(keeping) {
            try? fm.removeItem(at: old)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var cloudFolderURL: URL?
    @Published var databaseURL: URL?
    @Published var snapshotRoot: URL?
    @Published var entities: [MobileEntity] = []
    @Published var selectedEntity = ""
    @Published var selectedMonth = Calendar.current.component(.month, from: Date())
    @Published var selectedYear = Calendar.current.component(.year, from: Date())
    @Published var syncStatus = "Choose your Accountants 5.0 cloud backup folder."
    @Published var lastSyncedBackup = ""
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var syncError: String?
    @Published var showFolderPicker = false

    private var autoSyncTask: Task<Void, Never>?
    private var currentSourceFingerprint = ""

    init() {
        restoreCloudFolderBookmark()
    }

    deinit {
        autoSyncTask?.cancel()
    }

    func sceneBecameActive() {
        startAutoSync()
        Task { await syncNow(force: false) }
    }

    func sceneBecameInactive() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    func setCloudFolder(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "AccountantsMobile.CloudFolderBookmark")
            cloudFolderURL = url
            syncError = nil
            syncStatus = "Cloud folder connected. Looking for the latest Accountants backup…"
            Task { await syncNow(force: true) }
        } catch {
            syncError = error.localizedDescription
        }
    }

    func disconnectCloudFolder() {
        UserDefaults.standard.removeObject(forKey: "AccountantsMobile.CloudFolderBookmark")
        cloudFolderURL = nil
        databaseURL = nil
        snapshotRoot = nil
        entities = []
        selectedEntity = ""
        syncStatus = "Cloud folder disconnected."
        lastSyncedBackup = ""
        lastSyncDate = nil
    }

    func syncNow(force: Bool = true) async {
        guard let folder = cloudFolderURL, !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncStatus = "Checking cloud backup…"
        defer { isSyncing = false }

        let accessed = folder.startAccessingSecurityScopedResource()
        defer {
            if accessed { folder.stopAccessingSecurityScopedResource() }
        }

        do {
            let result = try await Task.detached(priority: .utility) {
                try BackupSyncService.sync(from: folder)
            }.value

            let fingerprint = "\(result.sourceName)|\(Int(result.sourceModified?.timeIntervalSince1970 ?? 0))"
            if force || fingerprint != currentSourceFingerprint || databaseURL == nil {
                databaseURL = result.databaseURL
                snapshotRoot = result.snapshotRoot
                currentSourceFingerprint = fingerprint
                loadWorkspace()
            }

            lastSyncedBackup = result.sourceName
            lastSyncDate = Date()
            syncStatus = "Synced from \(result.sourceName)"
        } catch {
            syncError = error.localizedDescription
            syncStatus = "Cloud sync needs attention."
        }
    }

    func store() throws -> SQLiteReadStore {
        guard let databaseURL else {
            throw NSError(domain: "AccountantsMobile", code: 10, userInfo: [NSLocalizedDescriptionKey: "No Accountants database is synced yet."])
        }
        return try SQLiteReadStore(url: databaseURL)
    }

    func entityId() -> Int64? {
        entities.first(where: { $0.name == selectedEntity })?.id
    }

    func selectedPeriodKey() -> String {
        String(format: "%04d-%02d", selectedYear, selectedMonth)
    }

    func managerSnapshotId() -> String? {
        guard !selectedEntity.isEmpty, let db = try? store(), db.tableExists("ManagerReportTbSnapshotsV6A") else { return nil }
        let sql = """
        SELECT SnapshotId
        FROM ManagerReportTbSnapshotsV6A
        WHERE Company=? AND substr(SnapshotDate,1,7)=? AND Active=1
        ORDER BY SnapshotDate DESC, Version DESC
        LIMIT 1;
        """
        return try? db.scalar(sql, [selectedEntity, selectedPeriodKey()])
    }

    func managerRows(search: String = "") -> [[String: String]] {
        guard let sid = managerSnapshotId(), let db = try? store() else { return [] }
        var sql = """
        SELECT
          a.AccountCode AS Code,
          a.AccountName AS Account,
          a.AccountType AS Type,
          a.Element AS Element,
          a.CurrentBalance AS Balance,
          COALESCE((SELECT m.SubMapping FROM ManagerReportMappingsV6A m
                    WHERE m.Company=? AND
                      ((m.AccountCode<>'' AND m.AccountCode=a.AccountCode) OR
                       (m.AccountCode='' AND m.AccountName=a.AccountName))
                    ORDER BY m.TemplateOrder, m.TemplateRow LIMIT 1),'') AS Mapping,
          COALESCE((SELECT m.StatementType FROM ManagerReportMappingsV6A m
                    WHERE m.Company=? AND
                      ((m.AccountCode<>'' AND m.AccountCode=a.AccountCode) OR
                       (m.AccountCode='' AND m.AccountName=a.AccountName))
                    ORDER BY m.TemplateOrder, m.TemplateRow LIMIT 1),'') AS Statement
        FROM ManagerReportAccountsV6A a
        WHERE a.SnapshotId=?
        """
        var args = [selectedEntity, selectedEntity, sid]
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sql += " AND (a.AccountCode LIKE ? OR a.AccountName LIKE ? OR a.AccountType LIKE ?)"
            let q = "%\(search)%"
            args.append(contentsOf: [q, q, q])
        }
        sql += " ORDER BY a.AccountCode, a.AccountName LIMIT 2000;"
        return (try? db.query(sql, args)) ?? []
    }

    func paymentRows() -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("PaymentVouchers") else { return [] }
        return (try? db.query("""
        SELECT VoucherNo AS Number, VoucherDate AS Date, Payee, Amount, Currency,
               Category, PaymentMode AS Mode, Purpose
        FROM PaymentVouchers
        WHERE EntityId=?
        ORDER BY VoucherDate DESC, Id DESC LIMIT 1000;
        """, [String(eid)])) ?? []
    }

    func receiptRows() -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("ReceiptVouchers") else { return [] }
        return (try? db.query("""
        SELECT ReceiptNo AS Number, ReceiptDate AS Date, ReceivedFrom AS FromParty,
               Amount, Currency, ReceiptType AS Type, ReceiptAgainst AS Against,
               ReferenceNo AS Reference, Purpose
        FROM ReceiptVouchers
        WHERE EntityId=?
        ORDER BY ReceiptDate DESC, Id DESC LIMIT 1000;
        """, [String(eid)])) ?? []
    }

    func employeeRows() -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("Employees") else { return [] }
        return (try? db.query("""
        SELECT EmployeeNo AS EmployeeNo, Name, Position, Department,
               CASE WHEN IsActive=1 THEN 'Active' ELSE 'Inactive' END AS Status
        FROM Employees WHERE EntityId=?
        ORDER BY IsActive DESC, Name LIMIT 2000;
        """, [String(eid)])) ?? []
    }

    func leaveRows() -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("LeaveSettlementRecords") else { return [] }
        return (try? db.query("""
        SELECT RecordId, EmployeeNo, EmployeeName, SettlementType,
               LeaveStart, LeaveEnd, LeaveDays, GrossEarnings,
               TotalDeductions, NetPayable, Status
        FROM LeaveSettlementRecords
        WHERE EntityId=?
        ORDER BY UpdatedAt DESC, Id DESC LIMIT 1000;
        """, [String(eid)])) ?? []
    }

    func costRows(search: String = "") -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("CostItems") else { return [] }
        var sql = """
        SELECT Category, ItemName AS Item, CostMethod AS Method,
               COALESCE(CAST(Cost AS TEXT),'N/A') AS Cost,
               ReportingCategory AS Reporting, Supplier,
               CASE WHEN IsActive=1 THEN 'Active' ELSE 'Inactive' END AS Status
        FROM CostItems WHERE EntityId=?
        """
        var args = [String(eid)]
        if !search.isEmpty {
            sql += " AND (ItemName LIKE ? OR Category LIKE ? OR ReportingCategory LIKE ? OR Supplier LIKE ?)"
            let q = "%\(search)%"
            args.append(contentsOf: [q, q, q, q])
        }
        sql += " ORDER BY IsActive DESC, Category, ItemName LIMIT 3000;"
        return (try? db.query(sql, args)) ?? []
    }

    func companyDocumentRows() -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("CompanyDocuments") else { return [] }
        return (try? db.query("""
        SELECT DocType AS Type, DocumentNumber AS Number, LegalName,
               IssueDate, ExpiryDate, CRNumber, LicenseNumber,
               PersonName, SourceFilename
        FROM CompanyDocuments WHERE EntityId=?
        ORDER BY UpdatedAt DESC, Id DESC LIMIT 1000;
        """, [String(eid)])) ?? []
    }

    func auditRows(statement: String) -> [[String: String]] {
        guard let eid = entityId(), let db = try? store(), db.tableExists("AuditStatementTemplateLines") else { return [] }
        return (try? db.query("""
        SELECT LineLabel AS Line, NoteNo AS Note, RowType AS Type,
               AuditedBaseValue AS PriorYear, AuditedBasePeriod AS BasePeriod,
               SourceDocument AS Source
        FROM AuditStatementTemplateLines
        WHERE ReportingEntityId=? AND StatementType=? AND IsActive=1
        ORDER BY SortOrder, Id;
        """, [String(eid), statement])) ?? []
    }

    func dashboardCounts() -> [(String, String)] {
        guard let eid = entityId(), let db = try? store() else { return [] }
        func count(_ table: String, whereClause: String = "EntityId=?") -> String {
            guard db.tableExists(table) else { return "0" }
            return (try? db.scalar("SELECT COUNT(*) FROM \(table) WHERE \(whereClause);", [String(eid)])) ?? "0"
        }
        return [
            ("Employees", count("Employees")),
            ("Payments", count("PaymentVouchers")),
            ("Receipts", count("ReceiptVouchers")),
            ("Cost items", count("CostItems")),
            ("Company docs", count("CompanyDocuments")),
            ("Leave settlements", count("LeaveSettlementRecords"))
        ]
    }

    func syncedFiles(filter: String = "") -> [SyncedFile] {
        guard let root = snapshotRoot else { return [] }
        let fm = FileManager.default
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var items: [SyncedFile] = []
        for case let url as URL in en {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
            if url.lastPathComponent == "AccountantsNext.db" { continue }
            if !filter.isEmpty && !relative.localizedCaseInsensitiveContains(filter) { continue }
            items.append(SyncedFile(url: url, relativePath: relative, size: Int64(values?.fileSize ?? 0)))
            if items.count >= 3000 { break }
        }
        return items.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
    }

    func farFiles() -> [SyncedFile] {
        syncedFiles().filter { $0.relativePath.localizedCaseInsensitiveContains("Audit/FAR") }
    }

    private func loadWorkspace() {
        guard let db = try? store(), db.tableExists("Entities") else {
            entities = []
            return
        }
        let rows = (try? db.query("SELECT Id, Name FROM Entities WHERE IsActive=1 ORDER BY Name;")) ?? []
        entities = rows.compactMap {
            guard let id = Int64($0["Id"] ?? ""), let name = $0["Name"], !name.isEmpty else { return nil }
            return MobileEntity(id: id, name: name)
        }

        if !entities.contains(where: { $0.name == selectedEntity }) {
            selectedEntity = entities.first?.name ?? ""
        }

        if let latest = latestManagerPeriod(db: db, company: selectedEntity) {
            selectedYear = latest.0
            selectedMonth = latest.1
        }
    }

    private func latestManagerPeriod(db: SQLiteReadStore, company: String) -> (Int, Int)? {
        guard !company.isEmpty, db.tableExists("ManagerReportTbSnapshotsV6A") else { return nil }
        let rows = (try? db.query("""
        SELECT SnapshotDate FROM ManagerReportTbSnapshotsV6A
        WHERE Company=? AND Active=1
        ORDER BY SnapshotDate DESC, Version DESC LIMIT 1;
        """, [company])) ?? []
        guard let date = rows.first?["SnapshotDate"], date.count >= 7 else { return nil }
        let parts = date.prefix(7).split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return (year, month)
    }

    private func restoreCloudFolderBookmark() {
        guard let data = UserDefaults.standard.data(forKey: "AccountantsMobile.CloudFolderBookmark") else { return }
        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            cloudFolderURL = url
            if stale {
                let refreshed = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(refreshed, forKey: "AccountantsMobile.CloudFolderBookmark")
            }
            syncStatus = "Cloud folder restored. Checking for updates…"
        } catch {
            UserDefaults.standard.removeObject(forKey: "AccountantsMobile.CloudFolderBookmark")
            syncError = "The saved cloud folder permission expired. Please choose the folder again."
        }
    }

    private func startAutoSync() {
        guard autoSyncTask == nil else { return }
        autoSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await self?.syncNow(force: false)
            }
        }
    }
}
