import SwiftUI

enum SMSDraftReviewType: String, CaseIterable, Identifiable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"

    var id: String { rawValue }

    var transactionType: TransactionType {
        switch self {
        case .income: return .income
        case .expense: return .expense
        case .transfer: return .transfer
        }
    }
}

struct SMSDraftInboxView: View {
    @State private var drafts: [SMSImportDraft] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if drafts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No SMS Drafts")
                        .font(.headline)
                    Text("Only new, never-reviewed bank SMS will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ForEach(drafts) { draft in
                    NavigationLink {
                        SMSDraftReviewView(draft: draft)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(draft.cleanedVendor.isEmpty ? "Unknown Vendor" : draft.cleanedVendor)
                                    .font(.headline)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(draft.currency) \(draft.amount.formatted())")
                                    .font(.headline)
                            }
                            HStack {
                                Label(draft.displayType, systemImage: draft.transactionType == .transfer ? "arrow.left.arrow.right.circle.fill" : (draft.transactionType == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill"))
                                Spacer()
                                Text(draft.date.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text("Tap to review type, accounts, category and all transaction details")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .navigationTitle("SMS Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    private func reload() {
        drafts = SMSImportConsoleService.loadDrafts().sorted {
            if $0.rowID != $1.rowID { return $0.rowID > $1.rowID }
            return $0.queuedAt > $1.queuedAt
        }
    }
}

struct SMSDraftReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let draft: SMSImportDraft

    @State private var initialized = false
    @State private var reviewType: SMSDraftReviewType = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var vendor = ""
    @State private var category = ""
    @State private var details = ""
    @State private var accountID: UUID?
    @State private var destinationAccountID: UUID?
    @AppStorage("SMSAIRecognitionEnabledV1") private var aiRecognitionEnabled = false
    @State private var aiAnalyzing = false
    @State private var aiRecognitionNote: String?
    @State private var notice: String?

    var body: some View {
        Form {
            Section("Transaction") {
                Picker("Type", selection: $reviewType) {
                    ForEach(SMSDraftReviewType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Text(draft.currency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("Date", selection: $date)
                TextField("Vendor / Counterparty", text: $vendor)
                TextField("Category", text: $category)
            }

            Section(reviewType == .transfer ? "Transfer Accounts" : "Account") {
                accountPicker(
                    title: reviewType == .transfer ? "From Account" : "Account",
                    selection: $accountID
                )
                if reviewType == .transfer {
                    accountPicker(title: "To Account", selection: $destinationAccountID)
                }
            }

            if draft.kind.hasPrefix("review") {
                Section("AI Recognition") {
                    if aiRecognitionEnabled {
                        Button {
                            Task { await analyzeWithAI(force: true) }
                        } label: {
                            Label(aiAnalyzing ? "Analyzing SMS…" : "Analyze with AI", systemImage: "sparkles")
                        }
                        .disabled(aiAnalyzing || !SMSAIRecognitionService.isAvailable)

                        if aiAnalyzing { ProgressView() }
                        if let aiRecognitionNote {
                            Text(aiRecognitionNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !SMSAIRecognitionService.isAvailable {
                            Text("Add an OpenAI or DeepSeek API key in Settings to use AI recognition.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("AI Recognition is off. Enable it in the SMS Import Console if you want AI to classify messages the local parser cannot recognize confidently.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Description") {
                TextEditor(text: $details)
                    .frame(minHeight: 130)
                Text("The complete original SMS is retained as the description. You may correct it before approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    approve()
                } label: {
                    Label("Approve and Record", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    reject()
                } label: {
                    Label("Reject Draft", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Review SMS Draft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepareDefaults)
        .task {
            if aiRecognitionEnabled && draft.kind.hasPrefix("review") {
                await analyzeWithAI(force: false)
            }
        }
        .onChange(of: reviewType) { newValue in
            if newValue == .transfer && category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                category = "Transfer"
            }
        }
        .alert("SMS Draft", isPresented: Binding(
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

    private func accountPicker(title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Select Account").tag(UUID?.none)
            ForEach(activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id))
            }
        }
    }

    private func prepareDefaults() {
        guard !initialized else { return }
        initialized = true
        amountText = NSDecimalNumber(decimal: draft.amount).stringValue
        date = draft.date
        vendor = draft.cleanedVendor
        details = draft.cleanedDescription
        category = store.smsDraftCategory(for: draft)

        switch draft.transactionType {
        case .income: reviewType = .income
        case .expense: reviewType = .expense
        case .transfer: reviewType = .transfer
        }

        let configuration = SMSImportConsoleService.loadConfiguration()
        let mapped = configuration.cardAccountIDs[draft.cardEnding].flatMap(UUID.init(uuidString:))
        switch draft.kind {
        case "incomingTransfer":
            destinationAccountID = mapped
        case "withdrawal":
            accountID = mapped
            destinationAccountID = configuration.cashAccountID.flatMap(UUID.init(uuidString:))
        case "billPayment":
            accountID = mapped
            destinationAccountID = (nil as String?).flatMap(UUID.init(uuidString:))
        default:
            accountID = mapped
        }
        if reviewType == .transfer { category = "Transfer" }
        if let cached = SMSAIRecognitionService.cachedResult(for: draft.id) {
            applyAIRecognition(cached)
        }
    }

    private func analyzeWithAI(force: Bool) async {
        guard draft.kind.hasPrefix("review"), aiRecognitionEnabled else { return }
        if !force, let cached = SMSAIRecognitionService.cachedResult(for: draft.id) {
            applyAIRecognition(cached)
            return
        }
        guard SMSAIRecognitionService.isAvailable else { return }
        aiAnalyzing = true
        defer { aiAnalyzing = false }
        do {
            if force { SMSAIRecognitionService.clearCache(for: draft.id) }
            let result = try await SMSAIRecognitionService.analyze(draft: draft)
            applyAIRecognition(result)
        } catch {
            SMSAIRecognitionService.recordFailure(error)
            aiRecognitionNote = error.localizedDescription
        }
    }

    private func applyAIRecognition(_ result: SMSAIRecognitionResult) {
        if result.transactionType == "ignore" {
            let confidence = Int((result.confidence * 100).rounded())
            aiRecognitionNote = "\(result.provider ?? "AI") says this is not a ledger transaction (\(confidence)% confidence)."
            return
        }
        switch result.transactionType {
        case "income": reviewType = .income
        case "transfer": reviewType = .transfer
        default: reviewType = .expense
        }
        if let amount = result.amount?.replacingOccurrences(of: ",", with: ""),
           Decimal(string: amount) != nil {
            amountText = amount
        }
        if let value = result.vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            vendor = value
        }
        if let value = result.category?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            category = reviewType == .transfer ? "Transfer" : value
        }
        if reviewType == .transfer { category = "Transfer" }

        if accountID == nil,
           let alias = result.accountAlias?.lowercased(), !alias.isEmpty,
           let account = activeAccounts.first(where: { $0.name.lowercased().contains(alias) }) {
            accountID = account.id
        }
        let confidence = Int((result.confidence * 100).rounded())
        let provider = result.provider ?? "AI"
        let reason = result.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        aiRecognitionNote = reason.isEmpty
            ? "\(provider) confidence: \(confidence)%"
            : "\(provider) confidence: \(confidence)% · \(reason)"
    }

    private func approve() {
        let normalized = amountText.replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: normalized), amount > 0 else {
            notice = "Enter a valid amount greater than zero."
            return
        }
        guard let accountID else {
            notice = reviewType == .transfer ? "Choose the From Account." : "Choose an account."
            return
        }
        if reviewType == .transfer && destinationAccountID == nil {
            notice = "Choose the To Account."
            return
        }

        guard store.approveReviewedSMSDraft(
            draft,
            transactionType: reviewType.transactionType,
            amount: amount,
            date: date,
            category: category,
            vendor: vendor,
            details: details,
            accountID: accountID,
            destinationAccountID: destinationAccountID
        ) else {
            notice = store.errorMessage ?? "This reviewed draft could not be recorded."
            return
        }

        do {
            try SMSImportConsoleService.completeDraft(draft)
            dismiss()
        } catch {
            notice = "The transaction was recorded, but the draft status could not be saved. Approving it again is safe because the transaction ID is duplicate-protected."
        }
    }

    private func reject() {
        do {
            try SMSImportConsoleService.completeDraft(draft)
            dismiss()
        } catch {
            notice = "The draft could not be rejected: \(error.localizedDescription)"
        }
    }
}
