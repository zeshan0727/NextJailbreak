import SwiftUI
import UniformTypeIdentifiers
import QuickLook
import UIKit

@main
struct AccountantsMobileApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear {
                    if model.cloudFolderURL != nil {
                        Task { await model.syncNow(force: false) }
                    }
                }
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .active:
                        model.sceneBecameActive()
                    default:
                        model.sceneBecameInactive()
                    }
                }
        }
    }
}

enum MobileModule: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case manager = "Manager Reporting"
    case audit = "Audit"
    case far = "FAR"
    case hr = "HR"
    case payments = "Payments"
    case receipts = "Receipts"
    case cost = "Cost Calculator"
    case company = "Company Information"
    case files = "Files & Reports"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .manager: return "chart.bar.doc.horizontal"
        case .audit: return "checkmark.seal"
        case .far: return "building.2.crop.circle"
        case .hr: return "person.2"
        case .payments: return "creditcard"
        case .receipts: return "doc.text"
        case .cost: return "calculator"
        case .company: return "building.2"
        case .files: return "folder"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Workspace summary and sync status"
        case .manager: return "Trial balance accounts and mappings"
        case .audit: return "Audit P&L / BS presentation and notes"
        case .far: return "Fixed asset schedules and movement files"
        case .hr: return "Employees and leave settlements"
        case .payments: return "Payment voucher register"
        case .receipts: return "Cash, cheque and transfer receipts"
        case .cost: return "Cost master"
        case .company: return "Company records and documents"
        case .files: return "Synced cloud backup files and reports"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.databaseURL == nil {
                    ConnectionView()
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            SyncCard()
                            WorkspaceCard()
                            ModuleGrid()
                        }
                        .padding()
                    }
                    .refreshable {
                        await model.syncNow(force: true)
                    }
                }
            }
            .navigationTitle("Accountants")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            Task { await model.syncNow(force: true) }
                        } label: {
                            Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            model.showFolderPicker = true
                        } label: {
                            Label("Change Cloud Folder", systemImage: "folder.badge.gearshape")
                        }
                        Button(role: .destructive) {
                            model.disconnectCloudFolder()
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(model.cloudFolderURL == nil)
                }
            }
            .sheet(isPresented: $model.showFolderPicker) {
                CloudFolderPicker { url in
                    model.showFolderPicker = false
                    model.setCloudFolder(url)
                } onCancel: {
                    model.showFolderPicker = false
                }
            }
            .alert("Cloud Sync", isPresented: Binding(
                get: { model.syncError != nil },
                set: { if !$0 { model.syncError = nil } }
            )) {
                Button("OK", role: .cancel) { model.syncError = nil }
            } message: {
                Text(model.syncError ?? "")
            }
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 58))
                    .foregroundStyle(.tint)
                    .padding(.top, 48)

                VStack(spacing: 8) {
                    Text("Connect Accountants Cloud Backup")
                        .font(.title2.bold())
                    Text("Choose the Accountants 5.0 Backups folder from Files. Google Drive, Dropbox, OneDrive and MEGA work through their iOS File Provider.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Sign in to your cloud provider once in its iPhone app.", systemImage: "1.circle.fill")
                    Label("Enable the provider in the iOS Files app.", systemImage: "2.circle.fill")
                    Label("Select your Accountants 5.0 Backups folder here.", systemImage: "3.circle.fill")
                    Label("The app checks for newer backups every 30 seconds while open.", systemImage: "4.circle.fill")
                }
                .font(.subheadline)
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    model.showFolderPicker = true
                } label: {
                    Label("Choose Cloud Backup Folder", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)

                if model.isSyncing {
                    ProgressView(model.syncStatus)
                } else {
                    Text(model.syncStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
    }
}

struct SyncCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
                .foregroundStyle(model.isSyncing ? .orange : .green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.isSyncing ? "Syncing" : "Cloud Connected")
                    .font(.headline)
                Text(model.syncStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let date = model.lastSyncDate {
                    Text("Last checked \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Button {
                Task { await model.syncNow(force: true) }
            } label: {
                if model.isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(model.isSyncing)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct WorkspaceCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace").font(.headline)

            Picker("Entity", selection: $model.selectedEntity) {
                ForEach(model.entities) { entity in
                    Text(entity.name).tag(entity.name)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Picker("Month", selection: $model.selectedMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(DateFormatter().monthSymbols[month - 1]).tag(month)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                Picker("Year", selection: $model.selectedYear) {
                    ForEach((2024...2032).reversed(), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.menu)
            }

            if model.managerSnapshotId() == nil {
                Label("No Manager Reporting TB snapshot for this exact period.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ModuleGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(MobileModule.allCases) { module in
                NavigationLink(value: module) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: module.icon)
                            .font(.title2)
                        Text(module.rawValue)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                        Text(module.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: MobileModule.self) { module in
            ModuleView(module: module)
        }
    }
}

struct ModuleView: View {
    let module: MobileModule

    var body: some View {
        switch module {
        case .dashboard: DashboardView()
        case .manager: ManagerReportingView()
        case .audit: AuditView()
        case .far: FARView()
        case .hr: HRView()
        case .payments: SimpleRowsView(title: "Payments", icon: "creditcard", rowsProvider: { $0.paymentRows() })
        case .receipts: SimpleRowsView(title: "Receipts", icon: "doc.text", rowsProvider: { $0.receiptRows() })
        case .cost: CostView()
        case .company: SimpleRowsView(title: "Company Information", icon: "building.2", rowsProvider: { $0.companyDocumentRows() })
        case .files: FilesView()
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !model.lastSyncedBackup.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Synced backup", systemImage: "icloud.and.arrow.down")
                            .font(.headline)
                        Text(model.lastSyncedBackup)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(model.dashboardCounts(), id: \.0) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.1)
                                .font(.title.bold())
                            Text(item.0)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}

struct ManagerReportingView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $search, prompt: "Account code or name")
            let rows = model.managerRows(search: search)
            if rows.isEmpty {
                EmptyState(title: "No TB data", icon: "tablecells", message: "Import/sync the selected period on the Windows app, then let the cloud backup refresh.")
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        NavigationLink {
                            RecordDetailView(title: row["Account"] ?? "Account", row: row)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row["Code"] ?? "").font(.caption.monospaced())
                                    Text(row["Account"] ?? "").font(.headline)
                                    Spacer()
                                    Text(money(row["Balance"]))
                                        .font(.subheadline.monospacedDigit())
                                }
                                HStack {
                                    Text(row["Type"] ?? "")
                                    if let mapping = row["Mapping"], !mapping.isEmpty {
                                        Text("• \(mapping)")
                                    }
                                    if let statement = row["Statement"], !statement.isEmpty {
                                        Text("• \(statement)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Manager Reporting")
    }
}

struct HRView: View {
    @EnvironmentObject var model: AppModel
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("HR", selection: $segment) {
                Text("Employees").tag(0)
                Text("Leave").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if segment == 0 {
                RowsList(rows: model.employeeRows(), emptyTitle: "No employees")
            } else {
                RowsList(rows: model.leaveRows(), emptyTitle: "No leave settlements")
            }
        }
        .navigationTitle("HR")
    }
}

struct AuditView: View {
    @EnvironmentObject var model: AppModel
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Statement", selection: $segment) {
                Text("P&L").tag(0)
                Text("BS").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            let type = segment == 0 ? "PL" : "BS"
            let rows = model.auditRows(statement: type)
            if rows.isEmpty {
                EmptyState(title: "No audit template", icon: "checkmark.seal", message: "No audit statement lines were found for this entity.")
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        NavigationLink {
                            RecordDetailView(title: row["Line"] ?? "Audit line", row: row)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row["Line"] ?? "")
                                    if let note = row["Note"], !note.isEmpty {
                                        Text("Note \(note)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let value = row["PriorYear"], !value.isEmpty {
                                    Text(money(value)).font(.caption.monospacedDigit())
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Audit")
    }
}

struct FARView: View {
    @EnvironmentObject var model: AppModel
    @State private var selectedFile: SyncedFile?

    var body: some View {
        let files = model.farFiles()
        Group {
            if files.isEmpty {
                EmptyState(title: "No FAR files", icon: "building.2.crop.circle", message: "FAR files from the Windows backup will appear here after sync.")
            } else {
                List(files) { file in
                    Button {
                        selectedFile = file
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading) {
                                Text(file.url.lastPathComponent)
                                Text(file.relativePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("FAR")
        .sheet(item: $selectedFile) { file in
            TextFilePreview(url: file.url)
        }
    }
}

struct CostView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $search, prompt: "Item, category, supplier")
            RowsList(rows: model.costRows(search: search), emptyTitle: "No cost items")
        }
        .navigationTitle("Cost Calculator")
    }
}

struct FilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var previewURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $search, prompt: "Search synced files")
            let files = model.syncedFiles(filter: search)
            if files.isEmpty {
                EmptyState(title: "No files", icon: "folder", message: "No matching files are present in the latest synced backup.")
            } else {
                List(files) { file in
                    Button {
                        previewURL = file.url
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconForFile(file.url))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.url.lastPathComponent)
                                    .lineLimit(1)
                                Text(file.relativePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Files & Reports")
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL {
                QuickLookPreview(url: previewURL)
                    .ignoresSafeArea()
            }
        }
    }
}

struct SimpleRowsView: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let icon: String
    let rowsProvider: (AppModel) -> [[String: String]]

    var body: some View {
        let rows = rowsProvider(model)
        Group {
            if rows.isEmpty {
EmptyState(title: "No \\(title.lowercased())", icon: icon)
            } else {
                RowsList(rows: rows, emptyTitle: "No records")
            }
        }
        .navigationTitle(title)
    }
}

struct RowsList: View {
    let rows: [[String: String]]
    let emptyTitle: String

    var body: some View {
        if rows.isEmpty {
            EmptyState(title: emptyTitle, icon: "tray")
        } else {
            List {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    NavigationLink {
                        RecordDetailView(title: primaryTitle(row, fallback: "Record \(index + 1)"), row: row)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(primaryTitle(row, fallback: "Record \(index + 1)"))
                                .font(.headline)
                            Text(secondaryLine(row))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

struct EmptyState: View {
    let title: String
    let icon: String
    var message: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            if !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 260)
    }
}

struct RecordDetailView: View {
    let title: String
    let row: [String: String]

    var body: some View {
        List {
            ForEach(row.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row[key] ?? "")
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SearchBar: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct CloudFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onCancel()
                return
            }
            onPick(url)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
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

struct TextFilePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var text = "Loading…"

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done") { dismiss() }
            }
            .task {
                if let data = try? Data(contentsOf: url),
                   let value = String(data: data, encoding: .utf8) {
                    text = value
                } else {
                    text = "This file is not plain text. Open it from Files & Reports for preview."
                }
            }
        }
    }
}

private func money(_ value: String?) -> String {
    guard let value, let number = Double(value) else { return value ?? "" }
    return String(format: "%,.2f", locale: Locale(identifier: "en_US"), number)
}

private func primaryTitle(_ row: [String: String], fallback: String) -> String {
    let keys = ["Name", "Item", "Number", "RecordId", "EmployeeName", "EmployeeNo", "FromParty", "Payee", "Type", "Line"]
    for key in keys {
        if let value = row[key], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
    }
    return fallback
}

private func secondaryLine(_ row: [String: String]) -> String {
    let ignored = Set(["Name", "Item", "Number", "RecordId", "EmployeeName", "EmployeeNo", "FromParty", "Payee", "Line"])
    return row.keys.sorted()
        .filter { !ignored.contains($0) }
        .compactMap { key -> String? in
            guard let value = row[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }
        .prefix(3)
        .joined(separator: " • ")
}

private func iconForFile(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "pdf": return "doc.richtext"
    case "xlsx", "xls", "csv": return "tablecells"
    case "jpg", "jpeg", "png", "heic": return "photo"
    case "zip": return "archivebox"
    case "json": return "curlybraces"
    default: return "doc"
    }
}
