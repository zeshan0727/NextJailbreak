import SwiftUI

struct SMSImportConsoleView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var configuration = SMSImportConfiguration()
    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var installerDiagnostic = ""
    @State private var approvedSendersText = "Cb SMS"
    @State private var draftCount = 0
    @State private var reviewCount = 0
    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false
    @State private var localManualScan = false
    @State private var manualScanRequestedAt: Date?
    @State private var aiProcessing = false
    @State private var aiProcessedCount = 0
    @State private var notice: String?
    @State private var loadingConfiguration = true

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                Toggle("SMS Detection", isOn: $configuration.enabled)
                Toggle("Auto Record", isOn: $configuration.autoRecord)
                Toggle("Realtime SMS Capture", isOn: $configuration.realtimeCaptureEnabled)
                NavigationLink {
                    SMSAccountMappingView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.blue)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Account Mapping")
                                .font(.body.weight(.semibold))
                            Text("Cards, current account, cash and approved senders")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Stepper(value: $configuration.automaticScanIntervalHours, in: 1...168) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Scheduled SMS Scan Interval")
                        Text("Every \(configuration.automaticScanIntervalHours) hour\(configuration.automaticScanIntervalHours == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if configuration.realtimeCaptureEnabled {
                    Text("Realtime mode is ON: the daemon may inspect approved-bank SMS every few seconds and Auto Record may post immediately. Turn this OFF to obey the scheduled interval.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Scheduled mode: Messages are not scanned continuously. Automatic detection and Auto Record run only at the selected interval. Collect Latest 15 wakes the daemon immediately for a manual review scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    SMSDraftInboxView()
                } label: {
                    HStack {
                        Label("SMS Drafts", systemImage: "tray.full.fill")
                        Spacer()
                        Text("\(draftCount)")
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    saveConfiguration(requestScan: false)
                } label: {
                    Label("Save Import Settings", systemImage: "checkmark.circle.fill")
                }
                Button {
                    startManualScan()
                } label: {
                    Label(effectiveManualScanActive ? "Fetching Latest SMS…" : "Fetch Latest 15 SMS", systemImage: "arrow.clockwise.circle.fill")
                }
                .disabled(effectiveManualScanActive)

                if effectiveManualScanActive {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: scanProgress)
                        HStack {
                            Text(snapshot.scanPhase ?? "Waiting for daemon…")
                            Spacer()
                            Text("\(scanProgressPercent)%")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else if snapshot.scanInProgress == true {
                    Text("Previous scan status is stale. You can start a new Latest 15 scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    SMSLatest15ReviewView()
                } label: {
                    HStack {
                        Label("Review Fetched SMS", systemImage: "text.bubble.fill")
                        Spacer()
                        Text("\(reviewCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(reviewCount == 0)

                if reviewCount == 0 && !effectiveManualScanActive {
                    Text("No fetched SMS are stored. Tap Fetch Latest 15 SMS to load a fresh review list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("SMS AI Helper", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(OpenAIService.shared.hasAPIKey ? "Ready" : "API required")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(OpenAIService.shared.hasAPIKey ? AppTheme.green : .secondary)
                    }
                    Text("AI starts with the latest 10 pending review messages. Clearing here removes the fetched review list and SMS AI results only; it does not delete phone messages or ledger data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        clearSMSAIHelperResults()
                    } label: {
                        Label("Clear Fetched SMS & AI", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 4)

                Button {
                    restoreRejectedForReview()
                } label: {
                    Label("Restore Rejected SMS for Review", systemImage: "arrow.uturn.backward.circle.fill")
                }
            } header: {
                Label("SMS Import & Review", systemImage: "message.fill")
            } footer: {
                Text(configuration.autoRecord
                    ? (configuration.realtimeCaptureEnabled
                        ? "Auto Record is enabled with Realtime Capture, so recognized SMS can post immediately."
                        : "Auto Record is enabled, but recognized SMS can post only when the scheduled scan runs. Manual Latest 15 review never auto-posts.")
                    : "Auto Record is off. New recognized SMS become drafts/review items and are not written to the ledger until you approve them.")
            }

            Section {
                NavigationLink {
                    SMSInstallerDiagnosticView()
                } label: {
                    Label("Installer Diagnostics", systemImage: "wrench.and.screwdriver.fill")
                }
            }

            Section("Live Status") {
                statusRow(
                    title: "Daemon",
                    value: daemonStatus,
                    icon: snapshot.daemonRunning ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                statusRow(title: "Last Heartbeat", value: formatted(snapshot.lastHeartbeat), icon: "waveform.path.ecg")
                statusRow(title: "Last Scan", value: formatted(snapshot.lastScanDate), icon: "message.badge")
                statusRow(title: "Last Import", value: formatted(snapshot.lastImportDate), icon: "tray.and.arrow.down.fill")
                LabeledContent("Imported", value: "\(snapshot.totalImported)")
                LabeledContent("Duplicates", value: "\(snapshot.totalDuplicates)")
                LabeledContent("Parse Failures", value: "\(snapshot.totalParseFailures)")
                LabeledContent("Pending Queue", value: "\(snapshot.pendingCount)")
                Text(snapshot.lastResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Section {
                NavigationLink {
                    SMSImportLogsView()
                } label: {
                    HStack {
                        Label("Logs", systemImage: "doc.text.magnifyingglass")
                        Spacer()
                        Text("\(snapshot.logs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("SMS Import Console")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadingConfiguration = true
            configuration = SMSImportConsoleService.loadConfiguration()
            approvedSendersText = configuration.approvedSenders.joined(separator: ", ")
            applySuggestedMappings()
            loadingConfiguration = false
            persistConfigurationSilently()
            refresh()
        }
        .onChange(of: configuration) { _ in
            guard !loadingConfiguration else { return }
            persistConfigurationSilently()
        }
        .onReceive(timer) { _ in refresh() }
        .alert("SMS Import", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var activeAccounts: [LedgerAccount] {
        store.activeAccounts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func accountPicker(
        title: String,
        selection: Binding<String?>,
        suggestedWords: [String]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Not Set").tag(String?.none)
            ForEach(activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id.uuidString))
            }
        }
    }

    private func cardBinding(_ ending: String) -> Binding<String?> {
        optionalBinding(
            get: { configuration.cardAccountIDs[ending] },
            set: { value in
                if let value {
                    configuration.cardAccountIDs[ending] = value
                } else {
                    configuration.cardAccountIDs.removeValue(forKey: ending)
                }
            }
        )
    }

    private func optionalBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String?> {
        Binding(get: get, set: set)
    }

    private func applySuggestedMappings() {
        if configuration.cardAccountIDs["6760"] == nil,
           let account = suggestedAccount(words: ["credit", "6760"]) {
            configuration.cardAccountIDs["6760"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["0023"] == nil,
           let account = suggestedAccount(words: ["debit", "0023"]) {
            configuration.cardAccountIDs["0023"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["364001"] == nil,
           let account = suggestedAccount(words: ["364001", "current", "cbq"]) {
            configuration.cardAccountIDs["364001"] = account.id.uuidString
        }
        if configuration.cashAccountID == nil,
           let account = suggestedAccount(words: ["cash"]) {
            configuration.cashAccountID = account.id.uuidString
        }
    }

    private func suggestedAccount(words: [String]) -> LedgerAccount? {
        activeAccounts.first { account in
            let name = account.name.lowercased()
            return words.contains { name.contains($0) }
        }
    }

    private var customEndingBinding: Binding<String> {
        Binding(
            get: { configuration.customEnding },
            set: { value in
                configuration.customEnding = String(value.filter(\.isNumber).suffix(8))
            }
        )
    }

    private func persistConfigurationSilently() {
        try? SMSImportConsoleService.saveConfiguration(configuration)
    }

    private func saveConfiguration(requestScan: Bool) {
        configuration.approvedSenders = approvedSendersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if configuration.approvedSenders.isEmpty { configuration.approvedSenders = ["Cb SMS"] }
        configuration.automaticScanIntervalHours = min(max(configuration.automaticScanIntervalHours, 1), 168)
        if requestScan { configuration.scanRequestID += 1 }
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = requestScan ? nil : "SMS import settings were saved."
            refresh()
        } catch {
            notice = "Settings could not be saved: \(error.localizedDescription)"
        }
    }

    private func restoreRejectedForReview() {
        do {
            let recordedIDs = Set(store.transactions.map(\.id))
            let restored = try SMSImportConsoleService.restoreRejectedForReview(
                recordedTransactionIDs: recordedIDs
            )
            guard restored > 0 else {
                notice = "No rejected SMS IDs were found. Approved transactions and current drafts were left unchanged."
                return
            }
            configuration.scanRequestID += 1
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = "Restored \(restored) rejected SMS item\(restored == 1 ? "" : "s") for review. Collect Latest 15 again if you also want a fresh database review list."
            refresh()
        } catch {
            notice = "Rejected SMS could not be restored: \(error.localizedDescription)"
        }
    }

    private func startManualScan() {
        localManualScan = true
        manualScanRequestedAt = Date()
        saveConfiguration(requestScan: true)
        refresh()
    }

    private var effectiveManualScanActive: Bool {
        if let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) <= 45,
           localManualScan || snapshot.scanInProgress == true {
            return true
        }
        return false
    }

    private var scanProgress: Double {
        let total = max(snapshot.scanProgressTotal ?? 15, 1)
        let current = min(max(snapshot.scanProgressCurrent ?? 0, 0), total)
        return Double(current) / Double(total)
    }

    private var scanProgressPercent: Int {
        Int((scanProgress * 100).rounded())
    }

    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
        installerDiagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
        draftCount = SMSImportConsoleService.loadDrafts().count
        reviewCount = SMSLatest15ReviewService.load().count

        if localManualScan,
           snapshot.scanInProgress != true,
           let requested = manualScanRequestedAt,
           let completed = snapshot.lastScanDate,
           completed >= requested.addingTimeInterval(-1) {
            localManualScan = false
            reviewCount = SMSLatest15ReviewService.load().count
            notice = reviewCount > 0
                ? "Fetched \(reviewCount) SMS for review. Open Review Fetched SMS to inspect them."
                : "The fetch completed, but no SMS review records were returned. Check Messages database access and Installer Diagnostics."
        }
        if localManualScan,
           let requested = manualScanRequestedAt,
           Date().timeIntervalSince(requested) > 45 {
            localManualScan = false
            notice = "The SMS fetch did not complete. Check Daemon status and Installer Diagnostics, then try again."
        }
    }

    private func clearSMSAIHelperResults() {
        let removed = SMSLatest15ReviewService.clearFetchedReview()
        SMSAIRecognitionService.clearAllCachedResults()
        aiProcessedCount = 0
        reviewCount = 0
        notice = removed > 0
            ? "Cleared \(removed) fetched SMS review record\(removed == 1 ? "" : "s") and SMS AI results. Messages on the iPhone, drafts, accounts, and ledger transactions were not deleted."
            : "No fetched SMS review records were stored. SMS AI results were cleared."
        refresh()
    }

    private func startAIRecognitionIfNeeded() {
        guard OpenAIService.shared.hasAPIKey, !aiProcessing, SMSAIRecognitionService.isAvailable else { return }
        let databaseCandidates = SMSImportConsoleService.loadAICandidates()
        let drafts = SMSImportConsoleService.loadDrafts().filter {
            $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
        }
        guard !databaseCandidates.isEmpty || !drafts.isEmpty else { return }
        aiProcessing = true
        Task {
            var completed = 0

            // Database recovery is highest priority. One source row is sent once;
            // successful ignore/transaction results are marked processed atomically.
            for candidate in databaseCandidates.prefix(10) {
                do {
                    let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
                    try SMSImportConsoleService.applyAIRecovery(result, to: candidate)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                    // Keep the candidate queued so a network/API failure can retry.
                    break
                }
            }

            // Refresh after recovery so newly created AI drafts are not immediately
            // sent through a redundant second request.
            let remainingDrafts = SMSImportConsoleService.loadDrafts().filter {
                $0.kind.hasPrefix("review") && SMSAIRecognitionService.cachedResult(for: $0.id) == nil
            }
            for draft in remainingDrafts.prefix(10) {
                do {
                    _ = try await SMSAIRecognitionService.analyze(draft: draft)
                    completed += 1
                } catch {
                    SMSAIRecognitionService.recordFailure(error)
                    break
                }
            }
            await MainActor.run {
                aiProcessedCount += completed
                aiProcessing = false
                refresh()
            }
        }
    }

    private var daemonStatus: String {
        guard snapshot.daemonRunning, let heartbeat = snapshot.lastHeartbeat else {
            return "Not detected"
        }
        return Date().timeIntervalSince(heartbeat) < 15 ? "Running" : "Heartbeat stale"
    }

    private func formatted(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Never"
    }

    private func statusRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct SMSAccountMappingView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var configuration = SMSImportConfiguration()
    @State private var approvedSendersText = "Cb SMS"
    @State private var loading = true
    @State private var savedStatus = ""

    var body: some View {
        List {
            Section {
                mappingPicker("Credit Card **6760", selection: cardBinding("6760"))
                mappingPicker("Debit Card **0023", selection: cardBinding("0023"))
                mappingPicker("Current Account xxx364001", selection: cardBinding("364001"))
                mappingPicker(
                    "Cash Account",
                    selection: optionalBinding(
                        get: { configuration.cashAccountID },
                        set: { configuration.cashAccountID = $0 }
                    )
                )
            } header: {
                Label("Known Accounts", systemImage: "creditcard.and.123")
            } footer: {
                Text("Choose the ledger account that belongs to each bank/card ending. These mappings are used when SMS drafts are prepared.")
            }

            Section {
                TextField("Custom card/account ending", text: customEndingBinding)
                    .keyboardType(.numberPad)
                mappingPicker(
                    "Custom Account",
                    selection: optionalBinding(
                        get: { configuration.customAccountID },
                        set: { configuration.customAccountID = $0 }
                    )
                )
            } header: {
                Label("Custom Mapping", systemImage: "plus.rectangle.on.rectangle")
            }

            Section {
                TextField("Approved senders, comma separated", text: $approvedSendersText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Only SMS from these sender names are considered for the automatic bank-SMS pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Approved Senders", systemImage: "person.crop.circle.badge.checkmark")
            }

            Section {
                Button {
                    persist(showStatus: true)
                    dismiss()
                } label: {
                    Label("Save Account Mapping", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.borderedProminent)

                if !savedStatus.isEmpty {
                    Text(savedStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Account Mapping")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loading = true
            configuration = SMSImportConsoleService.loadConfiguration()
            approvedSendersText = configuration.approvedSenders.joined(separator: ", ")
            applySuggestedMappings()
            loading = false
        }
        .onChange(of: configuration) { _ in
            guard !loading else { return }
            persist(showStatus: false)
        }
        .onChange(of: approvedSendersText) { _ in
            guard !loading else { return }
            persist(showStatus: false)
        }
    }

    private var activeAccounts: [LedgerAccount] {
        store.activeAccounts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @ViewBuilder
    private func mappingPicker(_ title: String, selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Not Set").tag(String?.none)
            ForEach(activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id.uuidString))
            }
        }
    }

    private func cardBinding(_ ending: String) -> Binding<String?> {
        optionalBinding(
            get: { configuration.cardAccountIDs[ending] },
            set: { value in
                if let value {
                    configuration.cardAccountIDs[ending] = value
                } else {
                    configuration.cardAccountIDs.removeValue(forKey: ending)
                }
            }
        )
    }

    private func optionalBinding(
        get: @escaping () -> String?,
        set: @escaping (String?) -> Void
    ) -> Binding<String?> {
        Binding(get: get, set: set)
    }

    private var customEndingBinding: Binding<String> {
        Binding(
            get: { configuration.customEnding },
            set: { value in
                configuration.customEnding = String(value.filter(\.isNumber).suffix(8))
            }
        )
    }

    private func applySuggestedMappings() {
        if configuration.cardAccountIDs["6760"] == nil,
           let account = suggestedAccount(words: ["credit", "6760"]) {
            configuration.cardAccountIDs["6760"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["0023"] == nil,
           let account = suggestedAccount(words: ["debit", "0023"]) {
            configuration.cardAccountIDs["0023"] = account.id.uuidString
        }
        if configuration.cardAccountIDs["364001"] == nil,
           let account = suggestedAccount(words: ["364001", "current", "cbq"]) {
            configuration.cardAccountIDs["364001"] = account.id.uuidString
        }
        if configuration.cashAccountID == nil,
           let account = suggestedAccount(words: ["cash"]) {
            configuration.cashAccountID = account.id.uuidString
        }
    }

    private func suggestedAccount(words: [String]) -> LedgerAccount? {
        activeAccounts.first { account in
            let name = account.name.lowercased()
            return words.contains { name.contains($0) }
        }
    }

    private func persist(showStatus: Bool) {
        configuration.approvedSenders = approvedSendersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if configuration.approvedSenders.isEmpty {
            configuration.approvedSenders = ["Cb SMS"]
        }
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            if showStatus { savedStatus = "Saved" }
        } catch {
            if showStatus { savedStatus = "Could not save: \(error.localizedDescription)" }
        }
    }
}

private struct SMSImportLogsView: View {
    @State private var snapshot = SMSImportConsoleSnapshot()
    @State private var notice: String?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if snapshot.logs.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        Text("No logs")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            } else {
                Section {
                    ForEach(snapshot.logs.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.level.uppercased())
                                    .font(.caption2.bold())
                                Spacer()
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Section {
                Button("Clear Logs", role: .destructive) {
                    clearLogs()
                }
            }
        }
        .navigationTitle("SMS Logs")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .alert("SMS Logs", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private func refresh() {
        snapshot = SMSImportConsoleService.loadSnapshot()
    }

    private func clearLogs() {
        var configuration = SMSImportConsoleService.loadConfiguration()
        configuration.clearLogsRequestID += 1
        do {
            try SMSImportConsoleService.saveConfiguration(configuration)
            notice = "Log cleanup requested."
        } catch {
            notice = "Logs could not be cleared."
        }
    }
}

private struct SMSInstallerDiagnosticView: View {
    @State private var diagnostic = ""

    var body: some View {
        List {
            Section("Installer Diagnostic") {
                if diagnostic.isEmpty {
                    Text("No installer diagnostic is available yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(diagnostic)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section {
                Button("Refresh") { reload() }
            }
        }
        .navigationTitle("Installer Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
    }

    private func reload() {
        diagnostic = SMSImportConsoleService.loadInstallerDiagnostic()
    }
}

private struct SMSAIRecognitionStatusView: View {
    @State private var testing = false
    @State private var message: String?
    @State private var refreshToken = UUID()

    private var provider: String {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastProviderV1") ?? "None yet"
    }

    private var confidence: String {
        _ = refreshToken
        let value = UserDefaults.standard.integer(forKey: "SMSAILastConfidenceV1")
        return UserDefaults.standard.object(forKey: "SMSAILastConfidenceV1") == nil ? "—" : "\(value)%"
    }

    private var lastType: String {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastTypeV1") ?? "—"
    }

    private var lastSuccess: String {
        _ = refreshToken
        let raw = UserDefaults.standard.double(forKey: "SMSAILastSuccessV1")
        guard raw > 0 else { return "Never" }
        return Date(timeIntervalSince1970: raw).formatted(date: .abbreviated, time: .standard)
    }

    private var lastError: String? {
        _ = refreshToken
        return UserDefaults.standard.string(forKey: "SMSAILastErrorV1")
    }

    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("AI available", value: SMSAIRecognitionService.isAvailable ? "Yes" : "No API key")
                LabeledContent("Last provider", value: provider)
                LabeledContent("Last successful call", value: lastSuccess)
            }
            Section("Last AI Result") {
                LabeledContent("Type", value: lastType.capitalized)
                LabeledContent("Confidence", value: confidence)
                if let lastError, !lastError.isEmpty {
                    Text("Last error: \(lastError)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    Task { await runTest() }
                } label: {
                    Label(testing ? "Testing AI…" : "Test AI on Latest Review Draft", systemImage: "checkmark.shield.fill")
                }
                .disabled(testing || !SMSAIRecognitionService.isAvailable)
                if testing { ProgressView() }
            } footer: {
                Text("A successful test must display the actual provider, returned type and confidence. The original SMS stays a review draft; this test never records a transaction.")
            }
        }
        .navigationTitle("AI Recognition")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(NotificationCenter.default.publisher(for: SMSAIRecognitionService.statusChanged)) { _ in
            refreshToken = UUID()
        }
    }

    @MainActor
    private func runTest() async {
        let candidates = SMSImportConsoleService.loadAICandidates()
        let drafts = SMSImportConsoleService.loadDrafts().filter { $0.kind.hasPrefix("review") }
        guard let candidate = candidates.first ?? drafts.first.map({ draft in
            SMSAICandidate(id: draft.id, sourceKey: draft.sourceKey, sender: draft.sender, rowID: draft.rowID, date: draft.date, details: draft.details, queuedAt: draft.queuedAt)
        }) else {
            message = "No unresolved database SMS is available. Run Manual Scan first."
            return
        }
        testing = true
        defer { testing = false }
        do {
            SMSAIRecognitionService.clearCache(for: candidate.id)
            let result = try await SMSAIRecognitionService.analyze(candidate: candidate)
            message = "Verified database → \(result.provider ?? "AI"): \(result.transactionType.capitalized), \(Int((result.confidence * 100).rounded()))% confidence. Test does not record or remove the queue item."
            refreshToken = UUID()
        } catch {
            SMSAIRecognitionService.recordFailure(error)
            message = "AI test failed: \(error.localizedDescription)"
            refreshToken = UUID()
        }
    }
}

