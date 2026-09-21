import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import GRDB
import ZIPFoundation

@main
struct AccountantsMobileApp: App {
    @StateObject private var store = MobileStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store) }
    }
}

struct EntityRow: Identifiable, Hashable { let id: Int64; let name: String; let code: String; let currency: String }
struct TBRow: Identifiable { let id = UUID(); let code: String; let name: String; let type: String; let balance: Double }
struct PaymentRow: Identifiable { let id: Int64; let number: String; let date: String; let party: String; let amount: Double; let currency: String; let purpose: String; let kind: String }
struct EmployeeRow: Identifiable { let id: Int64; let no: String; let name: String; let position: String; let department: String; let active: Bool }
struct LeaveRow: Identifiable { let id: Int64; let recordId: String; let employee: String; let start: String; let end: String; let days: Double; let net: Double; let remaining: Double; let status: String }
struct CostRow: Identifiable { let id: Int64; let category: String; let item: String; let cost: Double?; let method: String; let reporting: String; let supplier: String; let active: Bool }
struct CompanyDocRow: Identifiable { let id: Int64; let type: String; let number: String; let legalName: String; let expiry: String; let path: String }
struct AuditLineRow: Identifiable { let id: Int64; let statement: String; let label: String; let note: String; let rowType: String }
struct FileRow: Identifiable { let id = UUID(); let url: URL; let relative: String; let size: Int64 }
struct SearchHit: Identifiable { let id = UUID(); let module: String; let title: String; let detail: String }

@MainActor
final class MobileStore: ObservableObject {
    @Published var snapshotName = "No backup loaded"
    @Published var snapshotImportedAt = ""
    @Published var lastError = ""
    @Published var isBusy = false
    @Published var entities: [EntityRow] = []
    @Published var selectedEntityID: Int64 = 0
    @Published var selectedMonth: Int = Calendar.current.component(.month, from: Date())
    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @Published var latestTBDate = ""
    @Published var latestTBAccountCount = 0
    @Published var latestTBUnmapped = 0
    @Published var latestTBBalanced = false
    @Published var tbRows: [TBRow] = []
    @Published var payments: [PaymentRow] = []
    @Published var receipts: [PaymentRow] = []
    @Published var employees: [EmployeeRow] = []
    @Published var leaves: [LeaveRow] = []
    @Published var costs: [CostRow] = []
    @Published var companyDocs: [CompanyDocRow] = []
    @Published var auditLines: [AuditLineRow] = []
    @Published var files: [FileRow] = []
    @Published var currentDatabaseURL: URL?

    private var database: DatabaseQueue?
    private let fm = FileManager.default

    init() { Task { await restoreCurrentSnapshot() } }

    var selectedEntity: EntityRow? { entities.first(where: { $0.id == selectedEntityID }) }
    var monthName: String { DateFormatter().monthSymbols[max(0, min(11, selectedMonth - 1))] }
    var periodTitle: String { "\(monthName) \(selectedYear)" }
    var snapshotRoot: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("AccountantsMobile/Snapshots/Current", isDirectory: true)
    }
    var documentsRoot: URL { fm.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    func restoreCurrentSnapshot() async {
        do {
            let db = snapshotRoot.appendingPathComponent("Data/AccountantsNext.db")
            if fm.fileExists(atPath: db.path) {
                try openDatabase(db)
                snapshotName = UserDefaults.standard.string(forKey: "snapshotName") ?? "Local backup"
                snapshotImportedAt = UserDefaults.standard.string(forKey: "snapshotImportedAt") ?? ""
                await reloadAll()
            }
        } catch { lastError = error.localizedDescription }
    }

    func importBackup(from source: URL) async {
        isBusy = true
        lastError = ""
        defer { isBusy = false }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do { try await importLocalFile(source) }
        catch { lastError = error.localizedDescription }
    }

    func scanDocumentsForBackup() async {
        isBusy = true
        lastError = ""
        defer { isBusy = false }
        do {
            let candidates = try fm.contentsOfDirectory(
                at: documentsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter {
                ["zip", "db", "sqlite", "sqlite3"].contains($0.pathExtension.lowercased())
                || $0.lastPathComponent == "AccountantsNext.db"
            }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
            guard let newest = candidates.first else {
                throw NSError(
                    domain: "AccountantsMobile",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No .zip or AccountantsNext.db backup was found in the app Documents folder."]
                )
            }
            try await importLocalFile(newest)
        } catch { lastError = error.localizedDescription }
    }

    private func importLocalFile(_ source: URL) async throws {
        let stagingBase = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackupImport", isDirectory: true)
        try? fm.removeItem(at: stagingBase)
        try fm.createDirectory(at: stagingBase, withIntermediateDirectories: true)

        let ext = source.pathExtension.lowercased()
        var extractedRoot = stagingBase

        if ext == "zip" {
            let localZip = stagingBase.appendingPathComponent("backup.zip")
            try fm.copyItem(at: source, to: localZip)
            extractedRoot = stagingBase.appendingPathComponent("Extracted", isDirectory: true)
            try fm.createDirectory(at: extractedRoot, withIntermediateDirectories: true)
            try fm.unzipItem(at: localZip, to: extractedRoot)
        } else {
            let dataDir = stagingBase.appendingPathComponent("Data", isDirectory: true)
            try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: dataDir.appendingPathComponent("AccountantsNext.db"))
        }

        guard let dbURL = findDatabase(under: extractedRoot) else {
            throw NSError(
                domain: "AccountantsMobile",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "The selected backup does not contain Data/AccountantsNext.db."]
            )
        }

        _ = try DatabaseQueue(path: dbURL.path)

        let parent = snapshotRoot.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        let incoming = parent.appendingPathComponent("Incoming", isDirectory: true)
        try? fm.removeItem(at: incoming)
        try fm.createDirectory(at: incoming, withIntermediateDirectories: true)

        if ext == "zip" {
            let candidateRoot = rootContainingData(for: dbURL, stopAt: extractedRoot)
            try copyDirectoryContents(from: candidateRoot, to: incoming)
        } else {
            try fm.createDirectory(at: incoming.appendingPathComponent("Data"), withIntermediateDirectories: true)
            try fm.copyItem(at: dbURL, to: incoming.appendingPathComponent("Data/AccountantsNext.db"))
        }

        guard fm.fileExists(atPath: incoming.appendingPathComponent("Data/AccountantsNext.db").path) else {
            throw NSError(
                domain: "AccountantsMobile",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Backup import could not normalize Data/AccountantsNext.db."]
            )
        }

        let previous = parent.appendingPathComponent("Previous", isDirectory: true)
        try? fm.removeItem(at: previous)
        if fm.fileExists(atPath: snapshotRoot.path) { try fm.moveItem(at: snapshotRoot, to: previous) }
        try fm.moveItem(at: incoming, to: snapshotRoot)

        let finalDB = snapshotRoot.appendingPathComponent("Data/AccountantsNext.db")
        try openDatabase(finalDB)
        snapshotName = source.lastPathComponent
        snapshotImportedAt = ISO8601DateFormatter().string(from: Date())
        UserDefaults.standard.set(snapshotName, forKey: "snapshotName")
        UserDefaults.standard.set(snapshotImportedAt, forKey: "snapshotImportedAt")
        await reloadAll()
    }

    private func rootContainingData(for dbURL: URL, stopAt: URL) -> URL {
        var cursor = dbURL.deletingLastPathComponent()
        while cursor.path != stopAt.path && cursor.path.count >= stopAt.path.count {
            if cursor.lastPathComponent == "Data" { return cursor.deletingLastPathComponent() }
            cursor.deleteLastPathComponent()
        }
        return stopAt
    }

    private func copyDirectoryContents(from src: URL, to dst: URL) throws {
        let items = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        for item in items {
            let target = dst.appendingPathComponent(item.lastPathComponent, isDirectory: item.hasDirectoryPath)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: item, to: target)
        }
    }

    private func findDatabase(under root: URL) -> URL? {
        if root.lastPathComponent == "AccountantsNext.db" { return root }
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let file as URL in en where file.lastPathComponent == "AccountantsNext.db" { return file }
        return nil
    }

    private func openDatabase(_ url: URL) throws {
        database = try DatabaseQueue(path: url.path)
        currentDatabaseURL = url
    }

    func reloadAll() async {
        guard let dbq = database else { return }
        do {
            let newEntities: [EntityRow] = try dbq.read { db in
                guard try tableExists(db, "Entities") else { return [] }
                return try Row.fetchAll(
                    db,
                    sql: "SELECT Id,Name,Code,Currency FROM Entities WHERE IsActive=1 ORDER BY Name"
                ).map { row in
                    EntityRow(
                        id: int64(row, "Id"),
                        name: string(row, "Name"),
                        code: string(row, "Code"),
                        currency: string(row, "Currency")
                    )
                }
            }
            entities = newEntities
            if selectedEntityID == 0 || !newEntities.contains(where: { $0.id == selectedEntityID }) {
                selectedEntityID = newEntities.first?.id ?? 0
            }
            await refreshEntityData()
            refreshFileIndex()
        } catch { lastError = error.localizedDescription }
    }

    func refreshEntityData() async {
        guard let dbq = database, let entity = selectedEntity else { return }
        do {
            let endDate = String(format: "%04d-%02d-31", selectedYear, selectedMonth)
            let result = try dbq.read {
                db -> (String, Int, Int, Bool, [TBRow], [PaymentRow], [PaymentRow], [EmployeeRow], [LeaveRow], [CostRow], [CompanyDocRow], [AuditLineRow]) in

                var tbDate = ""
                var acctCount = 0
                var unmapped = 0
                var balanced = false
                var tb: [TBRow] = []

                if try tableExists(db, "ManagerReportTbSnapshotsV6A")
                    && tableExists(db, "ManagerReportAccountsV6A") {
                    if let snap = try Row.fetchOne(
                        db,
                        sql: "SELECT SnapshotId,SnapshotDate,AccountCount,UnmappedCount,Balanced FROM ManagerReportTbSnapshotsV6A WHERE lower(Company)=lower(?) AND SnapshotDate<=? AND Active=1 ORDER BY SnapshotDate DESC, Version DESC LIMIT 1",
                        arguments: [entity.name, endDate]
                    ) {
                        let sid = string(snap, "SnapshotId")
                        tbDate = string(snap, "SnapshotDate")
                        acctCount = int(snap, "AccountCount")
                        unmapped = int(snap, "UnmappedCount")
                        balanced = int(snap, "Balanced") != 0
                        tb = try Row.fetchAll(
                            db,
                            sql: "SELECT AccountCode,AccountName,AccountType,CurrentBalance FROM ManagerReportAccountsV6A WHERE SnapshotId=? ORDER BY AccountName",
                            arguments: [sid]
                        ).map { r in
                            TBRow(
                                code: string(r, "AccountCode"),
                                name: string(r, "AccountName"),
                                type: string(r, "AccountType"),
                                balance: double(r, "CurrentBalance")
                            )
                        }
                    }
                }

                let yearMonth = String(format: "%04d-%02d", selectedYear, selectedMonth)

                var pvs: [PaymentRow] = []
                if try tableExists(db, "PaymentVouchers") {
                    pvs = try Row.fetchAll(
                        db,
                        sql: "SELECT Id,VoucherNo,VoucherDate,Payee,Amount,Currency,Purpose FROM PaymentVouchers WHERE EntityId=? AND substr(COALESCE(VoucherDate,''),1,7)=? ORDER BY VoucherDate DESC,Id DESC",
                        arguments: [entity.id, yearMonth]
                    ).map { r in
                        PaymentRow(
                            id: int64(r, "Id"),
                            number: string(r, "VoucherNo"),
                            date: string(r, "VoucherDate"),
                            party: string(r, "Payee"),
                            amount: double(r, "Amount"),
                            currency: string(r, "Currency"),
                            purpose: string(r, "Purpose"),
                            kind: "Payment"
                        )
                    }
                }

                var rvs: [PaymentRow] = []
                if try tableExists(db, "ReceiptVouchers") {
                    rvs = try Row.fetchAll(
                        db,
                        sql: "SELECT Id,ReceiptNo,ReceiptDate,ReceivedFrom,Amount,Currency,Purpose,ReceiptType FROM ReceiptVouchers WHERE EntityId=? AND substr(COALESCE(ReceiptDate,''),1,7)=? ORDER BY ReceiptDate DESC,Id DESC",
                        arguments: [entity.id, yearMonth]
                    ).map { r in
                        PaymentRow(
                            id: int64(r, "Id"),
                            number: string(r, "ReceiptNo"),
                            date: string(r, "ReceiptDate"),
                            party: string(r, "ReceivedFrom"),
                            amount: double(r, "Amount"),
                            currency: string(r, "Currency"),
                            purpose: string(r, "Purpose"),
                            kind: string(r, "ReceiptType")
                        )
                    }
                }

                var emps: [EmployeeRow] = []
                if try tableExists(db, "Employees") {
                    emps = try Row.fetchAll(
                        db,
                        sql: "SELECT Id,EmployeeNo,Name,Position,Department,IsActive FROM Employees WHERE EntityId=? ORDER BY IsActive DESC,Name",
                        arguments: [entity.id]
                    ).map { r in
                        EmployeeRow(
                            id: int64(r, "Id"),
                            no: string(r, "EmployeeNo"),
                            name: string(r, "Name"),
                            position: string(r, "Position"),
                            department: string(r, "Department"),
                            active: int(r, "IsActive") != 0
                        )
                    }
                }

                var lvs: [LeaveRow] = []
                if try tableExists(db, "LeaveSettlementRecords") {
                    lvs = try Row.fetchAll(
                        db,
                        sql: "SELECT Id,RecordId,EmployeeName,LeaveStart,LeaveEnd,LeaveDays,NetPayable,TotalPayable,LeaveBalanceRemaining,Status FROM LeaveSettlementRecords WHERE EntityId=? ORDER BY COALESCE(UpdatedAt,CreatedAt) DESC,Id DESC LIMIT 250",
                        arguments: [entity.id]
                    ).map { r in
                        let netPayable = double(r, "NetPayable")
                        return LeaveRow(
                            id: int64(r, "Id"),
                            recordId: string(r, "RecordId"),
                            employee: string(r, "EmployeeName"),
                            start: string(r, "LeaveStart"),
                            end: string(r, "LeaveEnd"),
                            days: double(r, "LeaveDays"),
                            net: netPayable != 0 ? netPayable : double(r, "TotalPayable"),
                            remaining: double(r, "LeaveBalanceRemaining"),
                            status: string(r, "Status")
                        )
                    }
                }

                var cs: [CostRow] = []
                if try tableExists(db, "CostItems") {
                    cs = try Row.fetchAll(
                        db,
                        sql: "SELECT Id,Category,ItemName,Cost,CostMethod,ReportingCategory,Supplier,IsActive FROM CostItems WHERE EntityId=? ORDER BY IsActive DESC,ItemName",
                        arguments: [entity.id]
                    ).map { r in
                        CostRow(
                            id: int64(r, "Id"),
                            category: string(r, "Category"),
                            item: string(r, "ItemName"),
                            cost: optionalDouble(r, "Cost"),
                            method: string(r, "CostMethod"),
                            reporting: string(r, "ReportingCategory"),
                            supplier: string(r, "Supplier"),
                            active: int(r, "IsActive") != 0
                        )
                    }
                }

                var docs: [CompanyDocRow] = []
                if try tableExists(db, "CompanyDocuments") {
                    docs = try Row.fetchAll(
                        db,
                        sql: "SELECT Id,DocType,DocumentNumber,LegalName,ExpiryDate,AttachmentPath FROM CompanyDocuments WHERE EntityId=? ORDER BY DocType,DocumentNumber",
                        arguments: [entity.id]
                    ).map { r in
                        CompanyDocRow(
                            id: int64(r, "Id"),
                            type: string(r, "DocType"),
                            number: string(r, "DocumentNumber"),
                            legalName: string(r, "LegalName"),
                            expiry: string(r, "ExpiryDate"),
                            path: string(r, "AttachmentPath")
                        )
                    }
                }

                var audit: [AuditLineRow] = []
                if try tableExists(db, "AuditStatementTemplateLines") {
                    audit = try Row.fetchAll(
                        db,
                        sql: "SELECT a.Id,a.StatementType,a.LineLabel,a.NoteNo,a.RowType FROM AuditStatementTemplateLines a JOIN Entities e ON e.Id=a.ReportingEntityId WHERE e.Id=? AND a.IsActive=1 ORDER BY a.StatementType,a.SortOrder",
                        arguments: [entity.id]
                    ).map { r in
                        AuditLineRow(
                            id: int64(r, "Id"),
                            statement: string(r, "StatementType"),
                            label: string(r, "LineLabel"),
                            note: string(r, "NoteNo"),
                            rowType: string(r, "RowType")
                        )
                    }
                }

                return (tbDate, acctCount, unmapped, balanced, tb, pvs, rvs, emps, lvs, cs, docs, audit)
            }

            latestTBDate = result.0
            latestTBAccountCount = result.1
            latestTBUnmapped = result.2
            latestTBBalanced = result.3
            tbRows = result.4
            payments = result.5
            receipts = result.6
            employees = result.7
            leaves = result.8
            costs = result.9
            companyDocs = result.10
            auditLines = result.11
        } catch { lastError = error.localizedDescription }
    }

    private func refreshFileIndex() {
        guard fm.fileExists(atPath: snapshotRoot.path),
              let en = fm.enumerator(
                at: snapshotRoot,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else {
            files = []
            return
        }

        var out: [FileRow] = []
        for case let u as URL in en {
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true {
                let rel = u.path.replacingOccurrences(of: snapshotRoot.path + "/", with: "")
                out.append(FileRow(url: u, relative: rel, size: Int64(v?.fileSize ?? 0)))
            }
        }
        files = out.sorted {
            $0.relative.localizedCaseInsensitiveCompare($1.relative) == .orderedAscending
        }
    }

    func searchSnapshot(_ query: String) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []

        for p in payments where (p.number + p.party + p.purpose).lowercased().contains(q) {
            hits.append(SearchHit(
                module: "Payments",
                title: p.number,
                detail: "\(p.party) • \(money(p.amount, p.currency)) • \(p.purpose)"
            ))
        }
        for r in receipts where (r.number + r.party + r.purpose).lowercased().contains(q) {
            hits.append(SearchHit(
                module: "Receipts",
                title: r.number,
                detail: "\(r.party) • \(money(r.amount, r.currency)) • \(r.purpose)"
            ))
        }
        for e in employees where (e.no + e.name + e.position + e.department).lowercased().contains(q) {
            hits.append(SearchHit(module: "HR", title: "\(e.no) • \(e.name)", detail: "\(e.position) • \(e.department)"))
        }
        for c in costs where (c.category + c.item + c.reporting + c.supplier).lowercased().contains(q) {
            hits.append(SearchHit(
                module: "Cost",
                title: c.item,
                detail: "\(c.category) • \(c.cost.map { String(format: "%.2f", $0) } ?? "N/A")"
            ))
        }
        for d in companyDocs where (d.type + d.number + d.legalName).lowercased().contains(q) {
            hits.append(SearchHit(module: "Company", title: d.type, detail: "\(d.number) • \(d.legalName)"))
        }
        for f in files where f.relative.lowercased().contains(q) {
            hits.append(SearchHit(module: "Files", title: (f.relative as NSString).lastPathComponent, detail: f.relative))
        }
        return Array(hits.prefix(100))
    }
}

private func tableExists(_ db: Database, _ name: String) throws -> Bool {
    (try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
        arguments: [name]
    ) ?? 0) > 0
}
private func string(_ row: Row, _ c: String) -> String { let v: String? = row[c]; return v ?? "" }
private func int64(_ row: Row, _ c: String) -> Int64 { let v: Int64? = row[c]; return v ?? 0 }
private func int(_ row: Row, _ c: String) -> Int { let v: Int? = row[c]; return v ?? 0 }
private func double(_ row: Row, _ c: String) -> Double { let v: Double? = row[c]; return v ?? 0 }
private func optionalDouble(_ row: Row, _ c: String) -> Double? { let v: Double? = row[c]; return v }
private func money(_ value: Double, _ currency: String) -> String {
    "\(currency.isEmpty ? "QAR" : currency) \(String(format: "%.2f", value))"
}

struct RootView: View {
    @EnvironmentObject var store: MobileStore
    @State private var showImporter = false

    var body: some View {
        Group {
            if store.currentDatabaseURL == nil {
                WelcomeView(showImporter: $showImporter)
            } else {
                MainTabs(showImporter: $showImporter)
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.zip, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let u = urls.first {
                Task { await store.importBackup(from: u) }
            }
            if case .failure(let e) = result { store.lastError = e.localizedDescription }
        }
        .overlay(alignment: .bottom) {
            if store.isBusy {
                ProgressView("Importing backup…")
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding()
            }
        }
        .alert(
            "Accountants Mobile",
            isPresented: Binding(
                get: { !store.lastError.isEmpty },
                set: { if !$0 { store.lastError = "" } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.lastError)
        }
    }
}

struct WelcomeView: View {
    @EnvironmentObject var store: MobileStore
    @Binding var showImporter: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer()
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(.tint)
                Text("Accountants Mobile")
                    .font(.largeTitle.bold())
                Text("Local Backup Edition • v0.1.0")
                    .foregroundStyle(.secondary)
                Text("For this first build the cloud connector is intentionally disabled. Import the full backup ZIP generated by Accountants 5.0, or copy it into this app's Documents folder and scan it locally.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button { showImporter = true } label: {
                    Label("Import Backup File", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button { Task { await store.scanDocumentsForBackup() } } label: {
                    Label("Scan App Documents", systemImage: "folder.badge.gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Text("Expected backup: Accountants5_FULL_…zip or AccountantsNext.db")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle("Accountants")
        }
    }
}

struct MainTabs: View {
    @Binding var showImporter: Bool
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            ReportingView()
                .tabItem { Label("Reporting", systemImage: "chart.bar.doc.horizontal") }
            HRView()
                .tabItem { Label("HR", systemImage: "person.2.fill") }
            PaymentsView()
                .tabItem { Label("Payments", systemImage: "banknote.fill") }
            MoreView(showImporter: $showImporter)
                .tabItem { Label("More", systemImage: "square.grid.2x2.fill") }
        }
    }
}

struct WorkspaceHeader: View {
    @EnvironmentObject var store: MobileStore

    var body: some View {
        VStack(spacing: 10) {
            Picker("Entity", selection: $store.selectedEntityID) {
                ForEach(store.entities) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)

            HStack {
                Picker("Month", selection: $store.selectedMonth) {
                    ForEach(1...12, id: .self) {
                        Text(DateFormatter().monthSymbols[$0 - 1]).tag($0)
                    }
                }
                .pickerStyle(.menu)

                Picker("Year", selection: $store.selectedYear) {
                    ForEach((2024...2032).map { $0 }, id: .self) {
                        Text(String($0)).tag($0)
                    }
                }
                .pickerStyle(.menu)

                Spacer()
                Button { Task { await store.refreshEntityData() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onChange(of: store.selectedEntityID) { _ in Task { await store.refreshEntityData() } }
        .onChange(of: store.selectedMonth) { _ in Task { await store.refreshEntityData() } }
        .onChange(of: store.selectedYear) { _ in Task { await store.refreshEntityData() } }
    }
}

struct DashboardView: View {
    @EnvironmentObject var store: MobileStore

    var body: some View {
        NavigationStack {
            List {
                Section { WorkspaceHeader() }

                Section("Snapshot") {
                    LabeledContent("Backup", value: store.snapshotName)
                    LabeledContent("Imported", value: store.snapshotImportedAt.isEmpty ? "—" : store.snapshotImportedAt)
                    LabeledContent("Mode", value: "Read-only local snapshot")
                }

                Section("\(store.selectedEntity?.name ?? "Entity") • \(store.periodTitle)") {
                    MetricRow(title: "Latest TB", value: store.latestTBDate.isEmpty ? "No TB" : store.latestTBDate, icon: "doc.text.magnifyingglass")
                    MetricRow(title: "TB Accounts", value: String(store.latestTBAccountCount), icon: "list.number")
                    MetricRow(title: "Unmapped", value: String(store.latestTBUnmapped), icon: "exclamationmark.triangle")
                    MetricRow(title: "Balance Check", value: store.latestTBBalanced ? "Balanced" : "Review", icon: store.latestTBBalanced ? "checkmark.seal.fill" : "exclamationmark.circle")
                    MetricRow(
                        title: "Payments",
                        value: "\(store.payments.count) • \(money(store.payments.reduce(0) { $0 + $1.amount }, store.selectedEntity?.currency ?? "QAR"))",
                        icon: "arrow.up.right"
                    )
                    MetricRow(
                        title: "Receipts",
                        value: "\(store.receipts.count) • \(money(store.receipts.reduce(0) { $0 + $1.amount }, store.selectedEntity?.currency ?? "QAR"))",
                        icon: "arrow.down.left"
                    )
                    MetricRow(title: "Employees", value: String(store.employees.filter { $0.active }.count), icon: "person.2")
                }
            }
            .navigationTitle("Accountants")
        }
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(.tint)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct ReportingView: View {
    @EnvironmentObject var store: MobileStore
    @State private var search = ""

    var filtered: [TBRow] {
        search.isEmpty
        ? store.tbRows
        : store.tbRows.filter { ($0.code + $0.name + $0.type).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { WorkspaceHeader() }
                Section("Trial Balance • \(store.latestTBDate.isEmpty ? store.periodTitle : store.latestTBDate)") {
                    ForEach(filtered) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(r.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(r.name)
                                Spacer()
                                Text(String(format: "%.2f", r.balance)).monospacedDigit()
                            }
                            Text(r.type).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search TB accounts")
            .navigationTitle("Manager Reporting")
        }
    }
}

struct HRView: View {
    @EnvironmentObject var store: MobileStore
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkspaceHeader()
                    Picker("HR", selection: $segment) {
                        Text("Employees").tag(0)
                        Text("Leave Settlements").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                if segment == 0 {
                    ForEach(store.employees) { e in
                        VStack(alignment: .leading) {
                            HStack {
                                Text(e.name).font(.headline)
                                Spacer()
                                Text(e.no).font(.caption.monospaced())
                            }
                            Text([e.position, e.department].filter { !$0.isEmpty }.joined(separator: " • "))
                                .foregroundStyle(.secondary)
                            if !e.active {
                                Text("Inactive").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                } else {
                    ForEach(store.leaves) { l in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(l.employee).font(.headline)
                                Spacer()
                                Text(money(l.net, store.selectedEntity?.currency ?? "QAR")).monospacedDigit()
                            }
                            Text("\(l.recordId) • \(l.start) → \(l.end) • \(String(format: "%.3f", l.days)) days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Remaining: \(String(format: "%.3f", l.remaining)) • \(l.status)")
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("HR")
        }
    }
}

struct PaymentsView: View {
    @EnvironmentObject var store: MobileStore
    @State private var segment = 0
    var rows: [PaymentRow] { segment == 0 ? store.payments : store.receipts }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WorkspaceHeader()
                    Picker("Type", selection: $segment) {
                        Text("Payment Vouchers").tag(0)
                        Text("Receipts").tag(1)
                    }
                    .pickerStyle(.segmented)
                }

                ForEach(rows) { p in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(p.number).font(.headline.monospaced())
                            Spacer()
                            Text(money(p.amount, p.currency)).bold().monospacedDigit()
                        }
                        Text(p.party)
                        Text("\(p.date) • \(p.kind)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !p.purpose.isEmpty { Text(p.purpose).font(.caption) }
                    }
                }
            }
            .navigationTitle(segment == 0 ? "Payments" : "Receipts")
        }
    }
}

struct MoreView: View {
    @Binding var showImporter: Bool

    var body: some View {
        NavigationStack {
            List {
                NavigationLink { AuditView() } label: { Label("Audit", systemImage: "checkmark.seal") }
                NavigationLink { CostView() } label: { Label("Cost Calculator", systemImage: "calculator") }
                NavigationLink { CompanyView() } label: { Label("Company Information", systemImage: "building.2") }
                NavigationLink { LocalZEEView() } label: { Label("ZEE", systemImage: "sparkles") }
                NavigationLink { FilesView() } label: { Label("Files", systemImage: "folder") }
                NavigationLink { MobileSettingsView(showImporter: $showImporter) } label: {
                    Label("Settings & Backup", systemImage: "gearshape")
                }
            }
            .navigationTitle("More")
        }
    }
}

struct AuditView: View {
    @EnvironmentObject var store: MobileStore

    var body: some View {
        List {
            Section("Financial Statement Template") {
                ForEach(store.auditLines) { a in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(a.label)
                            Text(a.statement).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !a.note.isEmpty {
                            Text("Note \(a.note)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("FAR / Audit Files") {
                ForEach(store.files.filter { $0.relative.localizedCaseInsensitiveContains("Audit") }.prefix(100)) { f in
                    FileLinkRow(file: f)
                }
            }
        }
        .navigationTitle("Audit")
    }
}

struct CostView: View {
    @EnvironmentObject var store: MobileStore
    @State private var search = ""

    var body: some View {
        List(
            store.costs.filter {
                search.isEmpty || ($0.item + $0.category + $0.reporting + $0.supplier)
                    .localizedCaseInsensitiveContains(search)
            }
        ) { c in
            VStack(alignment: .leading) {
                HStack {
                    Text(c.item).font(.headline)
                    Spacer()
                    Text(c.cost.map { String(format: "%.4f", $0) } ?? "N/A").monospacedDigit()
                }
                Text([c.category, c.reporting, c.supplier].filter { !$0.isEmpty }.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $search)
        .navigationTitle("Cost Master")
    }
}

struct CompanyView: View {
    @EnvironmentObject var store: MobileStore

    var body: some View {
        List(store.companyDocs) { d in
            VStack(alignment: .leading) {
                HStack {
                    Text(d.type).font(.headline)
                    Spacer()
                    Text(d.number).font(.caption.monospaced())
                }
                if !d.legalName.isEmpty { Text(d.legalName) }
                if !d.expiry.isEmpty {
                    Text("Expiry: \(d.expiry)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Company Information")
    }
}

struct LocalZEEView: View {
    @EnvironmentObject var store: MobileStore
    @State private var q = ""
    @State private var hits: [SearchHit] = []

    var body: some View {
        List {
            Section {
                TextField("Search the local Accountants snapshot", text: $q)
                    .textInputAutocapitalization(.never)
                Button("Search Snapshot") { hits = store.searchSnapshot(q) }
            }

            Section("Local Results") {
                ForEach(hits) { h in
                    VStack(alignment: .leading) {
                        Text(h.title).font(.headline)
                        Text(h.module).font(.caption).foregroundStyle(.tint)
                        Text(h.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Managed ZEE actions are intentionally read-only in this first mobile build. After local module parity is validated, the managed Agent and reviewed write/sync layer can be enabled without risking divergence from the Windows source.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("ZEE")
    }
}

struct FilesView: View {
    @EnvironmentObject var store: MobileStore
    @State private var search = ""

    var body: some View {
        List(
            store.files.filter {
                search.isEmpty || $0.relative.localizedCaseInsensitiveContains(search)
            }
        ) { f in
            FileLinkRow(file: f)
        }
        .searchable(text: $search, prompt: "Search files")
        .navigationTitle("Backup Files")
    }
}

struct FileLinkRow: View {
    let file: FileRow
    @State private var preview = false

    var body: some View {
        Button { preview = true } label: {
            HStack {
                Image(systemName: "doc")
                VStack(alignment: .leading) {
                    Text((file.relative as NSString).lastPathComponent).foregroundStyle(.primary)
                    Text(file.relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $preview) {
            QuickLookView(url: file.url).ignoresSafeArea()
        }
    }
}

struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let c = QLPreviewController()
        c.dataSource = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct MobileSettingsView: View {
    @EnvironmentObject var store: MobileStore
    @Binding var showImporter: Bool

    var body: some View {
        List {
            Section("Local Backup") {
                Button { showImporter = true } label: {
                    Label("Import Backup File", systemImage: "square.and.arrow.down")
                }
                Button { Task { await store.scanDocumentsForBackup() } } label: {
                    Label("Scan App Documents", systemImage: "folder.badge.gearshape")
                }
                LabeledContent("Current", value: store.snapshotName)
                LabeledContent("Imported", value: store.snapshotImportedAt.isEmpty ? "—" : store.snapshotImportedAt)
                Text("You can copy the full Accountants backup ZIP into the app's Documents folder with Files/Filza, then tap Scan App Documents.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Cloud Sync — later") {
                Button("Connect Google Drive") {}.disabled(true)
                Button("Connect Dropbox") {}.disabled(true)
                Button("Connect OneDrive / Outlook") {}.disabled(true)
                Button("Connect MEGA") {}.disabled(true)
                Text("Connectors are deliberately disabled in v0.1.0. We will enable them after local backup import and all modules are validated, so cloud sync cannot corrupt or diverge from the Windows data source.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Safety") {
                LabeledContent("Data mode", value: "Read-only")
                LabeledContent("Windows database", value: "Never modified")
                LabeledContent("App version", value: "0.1.0 (1)")
            }
        }
        .navigationTitle("Settings")
    }
}
