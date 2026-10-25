import SwiftUI
import UniformTypeIdentifiers

struct MobileCaptureComposer: View {
    @EnvironmentObject private var workspace: MobileStore
    @EnvironmentObject private var captureInbox: CaptureInbox
    @Environment(\.dismiss) private var dismiss

    let initialKind: CaptureKind

    @State private var kind: CaptureKind = .payment
    @State private var receiptType: CaptureReceiptType = .bank
    @State private var paymentMode: CapturePaymentMode = .manual
    @State private var paymentMethod = "Bank Transfer"
    @State private var paymentCategory = "Operating Expense"
    @State private var party = ""
    @State private var receivedBy = ""
    @State private var amount = ""
    @State private var currency = "QAR"
    @State private var date = Date()
    @State private var reference = ""
    @State private var against = "Other"
    @State private var bankDetails = ""
    @State private var purpose = ""
    @State private var notes = ""
    @State private var scannedPages: [UIImage] = []
    @State private var importedFile: URL?
    @State private var extracted = ""
    @State private var scannerVisible = false
    @State private var importerVisible = false
    @State private var detectingText = false
    @State private var showScanText = false
    @State private var message = ""
    @State private var saved = false

    init(initialKind: CaptureKind) {
        self.initialKind = initialKind
        _kind = State(initialValue: initialKind)
    }

    private var parsedAmount: Decimal? {
        Decimal(string: amount.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US"))
    }
    private var canSave: Bool {
        guard let n = parsedAmount else { return false }
        return n > 0 && n < Decimal(1_000_000_000_000) &&
            !party.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (kind == .payment || !receivedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
            workspace.selectedEntityID > 0 &&
            (!scannedPages.isEmpty || importedFile != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "viewfinder")
                            .font(.title2).foregroundStyle(MobilePalette.accent)
                            .frame(width: 50, height: 50)
                            .background(MobilePalette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Scan to prepare a voucher").font(.headline)
                            Text("On-device recognition • your review required")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        scannerVisible = true
                    } label: { Label("Scan Document", systemImage: "doc.viewfinder") }
                        .disabled(detectingText)
                    Button { importerVisible = true } label: {
                        Label("Attach Existing Document", systemImage: "paperclip")
                    }
                    if !scannedPages.isEmpty {
                        Label("\(scannedPages.count) scanned page(s)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if let importedFile {
                        Label(importedFile.lastPathComponent, systemImage: "doc")
                            .lineLimit(2)
                    }
                    if detectingText {
                        ProgressView("Reading document on device…")
                    }
                } header: { Text("Supporting evidence") } footer: {
                    Text("Nothing is sent to OpenAI, Xero or a server. Captured images remain in protected iPhone storage.")
                }

                Section("Voucher type") {
                    Picker("Create", selection: $kind) {
                        ForEach(CaptureKind.allCases) { type in Text(type.rawValue).tag(type) }
                    }.pickerStyle(.segmented)
                    if kind == .payment {
                        Picker("PC voucher mode", selection: $paymentMode) {
                            ForEach(CapturePaymentMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Picker("Payment method", selection: $paymentMethod) {
                            ForEach(["Bank Transfer", "Cash", "Cheque", "Credit Card", "Pay Card", "Other"], id: \.self) { value in Text(value) }
                        }
                        Picker("PV category", selection: $paymentCategory) {
                            ForEach(["Operating Expense", "Capital Expense", "Advance Expense/Advance", "Employee Advance", "Supplier Advance", "Withdrawal", "Asset", "Liability", "Owner/Capital", "Prepayment", "Deposit", "Loan/Borrowing", "Refund/Reimbursement", "Marketing", "General", "Other"], id: \.self) { value in Text(value) }
                        }
                        Text("Electronic PV approval evidence and prepared-by signature must be verified and applied by the Windows service, never fabricated on iPhone.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Receipt type", selection: $receiptType) {
                            ForEach(CaptureReceiptType.allCases) { type in Text(type.rawValue).tag(type) }
                        }
                    }
                }
                Section("Company") {
                    Text(workspace.selectedEntity?.name ?? "Import a Windows backup first")
                    if workspace.selectedEntity == nil {
                        Label("No company loaded", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    DatePicker("Transaction date", selection: $date, displayedComponents: .date)
                }
                Section("Review extracted / entered details") {
                    TextField(kind == .payment ? "Payee / Supplier" : "Received From", text: $party)
                        .textInputAutocapitalization(.words)
                    if kind == .receipt {
                        TextField("Received By", text: $receivedBy).textInputAutocapitalization(.words)
                    }
                    HStack {
                        Picker("Currency", selection: $currency) {
                            ForEach(["QAR", "USD", "EUR", "GBP", "SAR", "AED"], id: \.self) { code in Text(code).tag(code) }
                        }.labelsHidden()
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if !extracted.isEmpty && !OnDeviceDocumentOCR.amounts(in: extracted).isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("OCR amount suggestions — tap one to use")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(OnDeviceDocumentOCR.amounts(in: extracted), id: \.self) { candidate in
                                        Button(candidate) { amount = candidate }
                                            .font(.caption.monospacedDigit())
                                            .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                    }
                    TextField("Purpose / Particulars", text: $purpose, axis: .vertical)
                        .lineLimit(2...4)
                    if kind == .receipt {
                        Picker("Receipt Against", selection: $against) {
                            ForEach(["Customer Receipt", "Advance Received", "Refund Received", "Deposit", "Owner / Capital", "Loan / Borrowing", "Intercompany", "Other"], id: \.self) { value in Text(value) }
                        }
                    } else {
                        TextField("Invoice / Payment Against", text: $against)
                    }
                    TextField("Reference / Cheque No.", text: $reference)
                    TextField("Bank / Transfer details", text: $bankDetails, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Internal notes", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
                if !extracted.isEmpty {
                    Section("Scanned text — verify carefully") {
                        Button(showScanText ? "Hide recognized text" : "View recognized text") {
                            withAnimation { showScanText.toggle() }
                        }
                        if showScanText {
                            Text(extracted)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(45)
                        }
                        Label("OCR may misread dates, beneficiary names and amounts.", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Saving creates a local PC-submission request, not an official voucher. No posting or voucher number occurs until the Windows system validates, approves and creates the entry.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(action: saveDraft) {
                        Label("Save Reviewed Request", systemImage: "checkmark.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave || detectingText)
                }
            }
            .navigationTitle(kind == .payment ? "New Payment Voucher" : "New Receipt")
            .onAppear {
                let value = workspace.selectedEntity?.currency ?? "QAR"
                currency = ["QAR", "USD", "EUR", "GBP", "SAR", "AED"].contains(value) ? value : "QAR"
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $scannerVisible) {
                DocumentScanner(
                    onScan: { pages in
                        scannerVisible = false
                        guard !pages.isEmpty else { return }
                        guard pages.count <= 12 else {
                            message = CaptureProblem.tooManyPages.localizedDescription
                            return
                        }
                        scannedPages = pages
                        detect(pages)
                    },
                    onFailure: { error in
                        scannerVisible = false
                        message = error
                    }
                )
            }
            .fileImporter(isPresented: $importerVisible, allowedContentTypes: [.pdf, .image, .data], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): importedFile = urls.first
                case .failure(let error): message = error.localizedDescription
                }
            }
            .alert("Document capture", isPresented: Binding(
                get: { !message.isEmpty },
                set: { if !$0 { message = "" } }
            )) { Button("OK", role: .cancel) {} } message: { Text(message) }
        }
    }

    private func detect(_ pages: [UIImage]) {
        detectingText = true
        OnDeviceDocumentOCR.recognize(pages) { result in
            detectingText = false
            switch result {
            case .success(let text): extracted = text
            case .failure(let error): message = "Unable to read text: \(error.localizedDescription). You can still enter all fields manually."
            }
        }
    }

    private func saveDraft() {
        guard canSave, let company = workspace.selectedEntity, let value = parsedAmount else { return }
        let captured = CaptureRequest(
            id: UUID(), schemaVersion: 1, createdAt: Date(),
            companyID: company.id, companyCode: company.code, companyName: company.name,
            kind: kind, receiptType: receiptType, paymentMode: paymentMode,
            paymentMethod: paymentMethod, paymentCategory: paymentCategory,
            party: party.trimmingCharacters(in: .whitespacesAndNewlines),
            receivedBy: receivedBy.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: value, currency: currency,
            transactionDate: date,
            reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
            against: against.trimmingCharacters(in: .whitespacesAndNewlines),
            bankDetails: bankDetails.trimmingCharacters(in: .whitespacesAndNewlines),
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            evidence: [],
            extractedText: extracted,
            reviewedOnMobile: true,
            state: "localDraft"
        )
        do {
            try captureInbox.save(captured, newPages: scannedPages, importedFile: importedFile)
            saved = true
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

struct MobileCaptureQueue: View {
    @EnvironmentObject private var captureInbox: CaptureInbox
    @EnvironmentObject private var workspace: MobileStore
    @State private var exportURL: URL?
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 12) {
            if !captureInbox.loadError.isEmpty {
                MobileEmpty(title: "Review stored requests", detail: "Saved mobile records could not be decoded, so new saves are blocked. Existing files have not been overwritten.", symbol: "exclamationmark.triangle")
            }
            let pending = captureInbox.requests.filter { $0.companyID == workspace.selectedEntityID }
            if pending.isEmpty {
                MobileEmpty(title: "No scanned requests yet", detail: "Scan a PV or receipt to create a validated mobile submission package for your Windows system.", symbol: "doc.viewfinder")
            } else {
                ForEach(pending) { item in
                    MobileCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.kind.rawValue).font(.subheadline.weight(.bold))
                                Text(item.party).font(.subheadline)
                                Text(item.companyName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 10)
                            Text("\(item.currency) \(item.amount.description)")
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        Label("Awaiting Windows import — not posted", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("\(item.evidence.count) supporting file(s)")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                do { exportURL = try captureInbox.exportPCRequest(item) }
                                catch { errorMessage = error.localizedDescription }
                            } label: {
                                Label("Export PC request", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(MobilePalette.accent)
                        }
                    }
                }
            }
            Text("The export is a request package containing checked supporting files and a unique ID. Windows ingestion must be connected before it can create and acknowledge official records.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: Binding(
            get: { exportURL != nil },
            set: { if !$0 { exportURL = nil } }
        )) {
            if let file = exportURL { PCSubmissionShare(file: file) }
        }
        .alert("Export failed", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage) }
    }
}
