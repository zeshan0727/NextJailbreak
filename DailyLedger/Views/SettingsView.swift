import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct SettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private enum ImportSource {
    case files
    case googleDrive
}

struct SettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @StateObject private var backupSync = BackupSyncService.shared
    @AppStorage("DailyLedgerICloudSync") private var iCloudSyncEnabled = false
    @State private var selectedCurrency = "QAR"
    @State private var exportingBackup = false
    @State private var exportingCSV = false
    @State private var showingImporter = false
    @State private var importSource = ImportSource.files
    @State private var exportingGoogleDrive = false
    @State private var notice: SettingsNotice?
    @State private var deepSeekAPIKey = ""
    @State private var deepSeekConnected = DeepSeekService.shared.hasAPIKey
    @State private var testingDeepSeek = false
    @State private var openAIAPIKey = ""
    @State private var openAIConnected = OpenAIService.shared.hasAPIKey
    @State private var testingOpenAI = false
    @AppStorage("OpenAIModel") private var openAIModel = "gpt-4.1-nano"
    @AppStorage("DeepSeekModel") private var deepSeekModel = "deepseek-v4-flash"
    @AppStorage("DailyLedgerAppearance") private var appearance = AppAppearance.system.rawValue
    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue
    @State private var showingSMSStatus = true

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Reporting Currency", selection: $selectedCurrency) {
                        ForEach(currencies, id: \.self) { code in
                            Text(currencyLabel(code)).tag(code)
                        }
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.rawValue).tag(option.rawValue)
                        }
                    }
                    Picker("App Theme", selection: $visualTheme) {
                        ForEach(AppVisualTheme.allCases) { theme in
                            Text(theme.rawValue).tag(theme.rawValue)
                        }
                    }
                } header: {
                    Label("Display", systemImage: "circle.lefthalf.filled")
                } footer: {
                    Text("Reporting Currency controls Home and Reports totals. Account balances remain in each account's own currency.")
                }

                Section {
                    Button {
                        exportingCSV = true
                    } label: {
                        SettingsRow(
                            title: "Export CSV",
                            subtitle: "Use with Excel, Numbers, or other apps",
                            icon: "tablecells.fill",
                            color: AppTheme.green
                        )
                    }

                    Button {
                        exportingBackup = true
                    } label: {
                        SettingsRow(
                            title: "Export JSON Backup",
                            subtitle: "Complete Next Ledger backup",
                            icon: "externaldrive.fill",
                            color: AppTheme.blue
                        )
                    }

                    Button {
                        importSource = .files
                        showingImporter = true
                    } label: {
                        SettingsRow(
                            title: "Import Data",
                            subtitle: "Merge a CSV or JSON file",
                            icon: "square.and.arrow.down.fill",
                            color: AppTheme.orange
                        )
                    }
                } header: {
                    Label("Import & Export", systemImage: "arrow.left.arrow.right")
                } footer: {
                    Text("Imported records are merged by their unique ID, helping prevent duplicate entries.")
                }

                Section {
                    Toggle("iCloud Drive Sync", isOn: $iCloudSyncEnabled)
                    Button {
                        store.syncBackupNow()
                    } label: {
                        Label("Back Up Now", systemImage: "icloud.and.arrow.up.fill")
                    }
                    Button {
                        store.restoreLatestICloudBackup()
                    } label: {
                        Label("Restore Latest iCloud Backup", systemImage: "icloud.and.arrow.down.fill")
                    }
                    Button {
                        exportingGoogleDrive = true
                    } label: {
                        Label("Back Up to Google Drive", systemImage: "externaldrive.badge.icloud")
                    }
                    Button {
                        importSource = .googleDrive
                        showingImporter = true
                    } label: {
                        Label("Restore from Google Drive", systemImage: "arrow.down.doc.fill")
                    }
                    LabeledContent("Last Backup") {
                        Text(backupSync.lastBackupDate?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                    }
                    Text(backupSync.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Label("Backup & Sync", systemImage: "icloud.fill")
                } footer: {
                    Text("For Google Drive, install its app and enable Google Drive in Files. Choose Google Drive when the save or restore picker opens. iOS requires you to approve each Drive file operation.")
                }

                Section {
                    HStack {
                        Label(
                            deepSeekConnected ? "Connected" : "Not Connected",
                            systemImage: deepSeekConnected ? "checkmark.shield.fill" : "shield.slash.fill"
                        )
                        .foregroundStyle(deepSeekConnected ? AppTheme.green : .secondary)
                        Spacer()
                        if testingDeepSeek { ProgressView() }
                    }

                    SecureField(
                        deepSeekConnected ? "Enter a replacement API key" : "DeepSeek API key",
                        text: $deepSeekAPIKey
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Picker("Model", selection: $deepSeekModel) {
                        Text("V4 Flash · Faster").tag("deepseek-v4-flash")
                        Text("V4 Pro · Deeper").tag("deepseek-v4-pro")
                    }

                    LabeledContent("Local Ledger Search", value: "Enabled")

                    Button("Save API Key") {
                        saveDeepSeekKey()
                    }
                    .disabled(deepSeekAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Test DeepSeek Connection") {
                        testDeepSeekConnection()
                    }
                    .disabled(!deepSeekConnected || testingDeepSeek)

                    if deepSeekConnected {
                        Button("Disconnect DeepSeek", role: .destructive) {
                            DeepSeekService.shared.deleteAPIKey()
                            deepSeekAPIKey = ""
                            deepSeekConnected = false
                        }
                    }
                } header: {
                    Label("DeepSeek AI", systemImage: "sparkles")
                } footer: {
                    Text("The key is stored only in this iPhone's Keychain and is excluded from exports and backups. Ledger Lookup searches locally and uses no API tokens. Requests are manual, thinking mode is disabled, and output is capped.")
                }

                Section {
                    Label(openAIConnected ? "Connected" : "Not Connected",
                          systemImage: openAIConnected ? "checkmark.shield.fill" : "shield.slash.fill")
                        .foregroundStyle(openAIConnected ? AppTheme.green : .secondary)
                    SecureField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Picker("Text Model", selection: $openAIModel) {
                        ForEach(OpenAIService.selectableModels, id: \.self) { model in
                            Text(modelLabel(model)).tag(model)
                        }
                    }
                    Button("Save OpenAI API Key", action: saveOpenAIKey)
                        .disabled(openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Test OpenAI Connection", action: testOpenAIConnection)
                        .disabled(!openAIConnected || testingOpenAI)
                    if testingOpenAI { ProgressView() }
                    if openAIConnected {
                        Button("Disconnect OpenAI", role: .destructive) {
                            OpenAIService.shared.deleteAPIKey()
                            openAIConnected = false
                        }
                    }
                } header: {
                    Label("OpenAI Chat", systemImage: "bubble.left.and.bubble.right.fill")
                } footer: {
                    Text("GPT-5 models are included, but OpenAI currently does not support them on the API Free tier. Your API project controls availability and billing. Next Ledger caps each answer to control tokens.")
                }

                Section {
                    SettingsRow(
                        title: "Add Expense",
                        subtitle: "Save an expense without opening the app",
                        icon: "minus.circle.fill",
                        color: AppTheme.red
                    )
                    SettingsRow(
                        title: "Add Income",
                        subtitle: "Save income without opening the app",
                        icon: "plus.circle.fill",
                        color: AppTheme.green
                    )
                    Link(destination: URL(string: "shortcuts://")!) {
                        SettingsRow(
                            title: "Open Shortcuts App",
                            subtitle: "Build personal automations",
                            icon: "square.stack.3d.up.fill",
                            color: AppTheme.purple
                        )
                    }
                } header: {
                    Label("Shortcuts", systemImage: "wand.and.stars")
                } footer: {
                    Text("In Shortcuts, search for Next Ledger actions. You can pass an amount, category, description, and date from another action.")
                }

                Section {
                    if showingSMSStatus, let result = store.settings.smsImporterLastResult, !result.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Latest bank message", systemImage: "message.badge.filled.fill")
                                .font(.headline)
                            Text(result)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                            HStack {
                                Button("Record Transaction") {
                                    store.requestSMSRescan()
                                    notice = SettingsNotice(title: "Import Requested", message: "Next Ledger asked the SMS importer to record the latest matching message.")
                                }
                                .buttonStyle(.borderedProminent)
                                Button("Cancel") { showingSMSStatus = false }
                                    .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 5)
                    }

                    NavigationLink {
                        SMSImportPreferencesView()
                    } label: {
                        SettingsRow(
                            title: "SMS Import Preferences",
                            subtitle: "Match text, destination account, and status",
                            icon: "message.fill",
                            color: AppTheme.teal
                        )
                    }

                    NavigationLink {
                        VendorRulesView()
                    } label: {
                        SettingsRow(
                            title: "Vendor Category Rules",
                            subtitle: "Match vendor words to categories",
                            icon: "tag.fill",
                            color: AppTheme.purple
                        )
                    }
                } header: {
                    Label("Bank SMS", systemImage: "bolt.shield.fill")
                } footer: {
                    Text("Shows the latest importer result and lets you record the latest matching bank message or cancel the prompt.")
                }

                Section {
                    Button {
                        let summary = store.automaticallyCategorizeTransactions()
                        notice = SettingsNotice(
                            title: "Categorization Complete",
                            message: "Categorized \(summary.categorizedCount) transactions. \(summary.reviewCount) still need your review."
                        )
                    } label: {
                        SettingsRow(
                            title: "Auto-Categorize Transactions",
                            subtitle: "Z-iP-14PM-16.0 transactions from the last 30 days",
                            icon: "wand.and.stars.inverse",
                            color: AppTheme.orange
                        )
                    }
                    .disabled(store.uncategorizedTransactions.isEmpty)

                    NavigationLink {
                        UncategorizedReviewView()
                    } label: {
                        SettingsRow(
                            title: "Review Uncategorized",
                            subtitle: "\(store.uncategorizedTransactions.count) recent Z-iP transactions remaining",
                            icon: "checklist",
                            color: AppTheme.blue
                        )
                    }
                    .disabled(store.uncategorizedTransactions.isEmpty)

                } header: {
                    Label("Categorization", systemImage: "tag.fill")
                } footer: {
                    Text("Review only recent transactions that could not be categorized automatically.")
                }

                Section {
                    LabeledContent("Version", value: "1.3.33")
                    LabeledContent("Author", value: "Next Jailbreak – Zeeshan Barvi")
                } header: {
                    Label("About", systemImage: "info.circle.fill")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                selectedCurrency = store.currencyCode
            }
            .onChange(of: selectedCurrency) { store.updateCurrency($0) }
            .fileExporter(
                isPresented: $exportingBackup,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "DailyLedger-Backup"
            ) { result in
                showExportResult(result, format: "backup")
            }
            .fileExporter(
                isPresented: $exportingCSV,
                document: csvDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "DailyLedger-Transactions"
            ) { result in
                showExportResult(result, format: "CSV file")
            }
            .fileExporter(
                isPresented: $exportingGoogleDrive,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "DailyLedger-GoogleDrive-Backup"
            ) { result in
                showExportResult(result, format: "Google Drive backup")
            }
            .sheet(isPresented: $showingImporter) {
                ImportDocumentPicker { result in
                    showingImporter = false
                    importFile(result, source: importSource)
                }
            }
            .alert(item: $notice) { notice in
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var backupDocument: BackupDocument {
        BackupDocument(data: ImportExportCodec.backupData(
            transactions: store.transactions,
            accounts: store.accounts,
            settings: store.settings,
            fixedBudget: store.fixedBudget
        ))
    }

    private var csvDocument: CSVDocument {
        CSVDocument(data: ImportExportCodec.csvData(
            transactions: store.transactions,
            accounts: store.accounts
        ))
    }

    private func currencyLabel(_ code: String) -> String {
        let names: [String: String] = [
            "QAR": "Qatari Riyal", "USD": "US Dollar", "GBP": "British Pound",
            "EUR": "Euro", "AED": "UAE Dirham", "SAR": "Saudi Riyal",
            "PKR": "Pakistani Rupee", "INR": "Indian Rupee"
        ]
        return "\(code) – \(names[code] ?? code)"
    }

    private func modelLabel(_ model: String) -> String {
        switch model {
        case "gpt-5-nano": return "GPT-5 Nano · Lowest-cost GPT-5"
        case "gpt-5-mini": return "GPT-5 Mini · Balanced"
        case "gpt-5.6-sol": return "GPT-5.6 Sol · Frontier"
        default: return model
        }
    }

    private func saveDeepSeekKey() {
        do {
            try DeepSeekService.shared.saveAPIKey(deepSeekAPIKey)
            deepSeekAPIKey = ""
            deepSeekConnected = true
            notice = SettingsNotice(title: "DeepSeek Connected", message: "The API key was saved securely in this iPhone's Keychain.")
        } catch {
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }

    private func testDeepSeekConnection() {
        testingDeepSeek = true
        Task {
            do {
                _ = try await DeepSeekService.shared.request(
                    messages: [DeepSeekMessage(role: "user", content: "Reply with exactly: Connected")],
                    model: deepSeekModel,
                    maxTokens: 20
                )
                await MainActor.run {
                    testingDeepSeek = false
                    notice = SettingsNotice(title: "Connection Successful", message: "Next Ledger can reach DeepSeek.")
                }
            } catch {
                await MainActor.run {
                    testingDeepSeek = false
                    notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func saveOpenAIKey() {
        do {
            try OpenAIService.shared.saveAPIKey(openAIAPIKey)
            openAIAPIKey = ""
            openAIConnected = true
            notice = SettingsNotice(title: "OpenAI Connected", message: "The API key was saved securely in this iPhone's Keychain.")
        } catch {
            notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
        }
    }

    private func testOpenAIConnection() {
        testingOpenAI = true
        Task {
            do {
                _ = try await OpenAIService.shared.request(
                    messages: [OpenAIMessage(role: "user", content: "Reply with exactly: Connected")],
                    model: openAIModel, maxTokens: 20
                )
                await MainActor.run {
                    testingOpenAI = false
                    notice = SettingsNotice(title: "Connection Successful", message: "Next Ledger can reach OpenAI.")
                }
            } catch {
                await MainActor.run {
                    testingOpenAI = false
                    notice = SettingsNotice(title: "Connection Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func showExportResult(_ result: Result<URL, Error>, format: String) {
        switch result {
        case .success:
            notice = SettingsNotice(title: "Export Complete", message: "Your \(format) is ready.")
        case .failure(let error):
            notice = SettingsNotice(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importFile(_ result: Result<URL, Error>, source: ImportSource) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try coordinatedData(from: url)
            let summary = try store.importData(data)
            let transactionText = summary.transactionCount == 1
                ? "1 transaction"
                : "\(summary.transactionCount) transactions"
            let accountText = summary.accountCount == 1
                ? "1 account"
                : "\(summary.accountCount) accounts"
            notice = SettingsNotice(
                title: source == .googleDrive ? "Restore Complete" : "Import Complete",
                message: "Added \(transactionText) and \(accountText)."
            )
        } catch {
            notice = SettingsNotice(
                title: source == .googleDrive ? "Restore Failed" : "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    private func coordinatedData(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var readResult: Result<Data, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL, options: .mappedIfSafe)
            }
        }
        if let coordinatorError { throw coordinatorError }
        guard let readResult else {
            throw CocoaError(.fileReadUnknown)
        }
        return try readResult.get()
    }
}

private struct ImportDocumentPicker: UIViewControllerRepresentable {
    let completion: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .commaSeparatedText, .plainText, .data, .item],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (Result<URL, Error>) -> Void

        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let url = urls.first else {
                completion(.failure(CocoaError(.fileReadNoSuchFile)))
                return
            }
            completion(.success(url))
        }
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
