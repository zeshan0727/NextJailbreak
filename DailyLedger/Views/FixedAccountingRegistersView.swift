import SwiftUI
import UIKit

private enum FixedAssetRegisterFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case sold = "Sold"
    case disposed = "Disposed"
    case all = "All"
    var id: String { rawValue }
}

private struct FixedAssetCurrencySummary: Identifiable {
    let currency: String
    let cost: Decimal
    let accumulated: Decimal
    let nbv: Decimal
    let gainLoss: Decimal
    var id: String { currency }
}

struct FixedAssetRegisterView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: FixedAssetRegisterFilter = .active
    @State private var showingNew = false
    @State private var editingAsset: FixedAssetRecord?
    @State private var disposingAsset: FixedAssetRecord?
    @State private var searchText = ""
    @State private var customAsOfEnabled = false
    @State private var asOfDate = Date()
    @State private var showingExport = false

    var body: some View {
        List {
            Section {
                Toggle("Custom As-of Date", isOn: $customAsOfEnabled)
                if customAsOfEnabled {
                    DatePicker("As of", selection: $asOfDate, displayedComponents: .date)
                }
            } header: {
                Text("Register Date")
            } footer: {
                Text("Depreciation, NBV, Active/Sold/Disposed status and export use this reporting date. Assets purchased after the selected date are excluded.")
            }
            Section {
                Picker("Register", selection: $filter) {
                    ForEach(FixedAssetRegisterFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if summaries.isEmpty {
                Section("Register Summary") {
                    LabeledContent("Original Cost", value: DisplayFormat.currency(0, code: store.currencyCode))
                    LabeledContent("Net Book Value", value: DisplayFormat.currency(0, code: store.currencyCode))
                }
            } else {
                ForEach(summaries) { summary in
                    Section("\(summary.currency) Register Summary") {
                        LabeledContent("Original Cost", value: DisplayFormat.currency(summary.cost, code: summary.currency))
                        LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(summary.accumulated, code: summary.currency))
                        LabeledContent("Net Book Value", value: DisplayFormat.currency(summary.nbv, code: summary.currency))
                        LabeledContent("Disposal Gain / (Loss)", value: DisplayFormat.currency(summary.gainLoss, code: summary.currency))
                            .foregroundStyle(summary.gainLoss >= 0 ? AppTheme.green : AppTheme.red)
                    }
                }
            }

            if filteredAssets.isEmpty {
                Section {
                    EmptyLedgerView(
                        title: "No fixed assets",
                        message: filter == .active
                            ? "Register fixed assets here. Sold and disposed items remain permanently visible in their own tabs."
                            : "No assets match this register view."
                    )
                }
            } else {
                ForEach(groupedCategories, id: \.0) { category, assets in
                    Section(category) {
                        ForEach(assets) { asset in
                            Button { editingAsset = asset } label: {
                                FixedAssetRegisterRow(asset: asset, asOfDate: reportingDate, needsDetails: needsDetails(asset))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editingAsset = asset } label: { Label("Edit Asset", systemImage: "pencil") }
                                if asset.status == .active {
                                    Button { disposingAsset = asset } label: { Label("Sell / Dispose", systemImage: "arrow.uturn.down.square") }
                                }
                                Button(role: .destructive) {
                                    store.deleteFixedAssetRecord(asset.id)
                                } label: { Label("Delete Register Record", systemImage: "trash") }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if asset.status == .active {
                                    Button { disposingAsset = asset } label: { Label("Dispose", systemImage: "arrow.uturn.down.square") }
                                        .tint(AppTheme.orange)
                                }
                                Button { editingAsset = asset } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(AppTheme.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fixed Asset Register")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Asset no., name, category")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showingExport = true } label: {
                    Image(systemName: "square.and.arrow.down.fill")
                }
                .accessibilityLabel("Download fixed asset register")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus.circle.fill") }
                    .accessibilityLabel("Register fixed asset")
            }
        }
        .sheet(isPresented: $showingExport) {
            FixedAssetRegisterExportView(
                assets: filteredAssets,
                asOfDate: reportingDate,
                registerTitle: filter.rawValue
            )
        }
        .sheet(isPresented: $showingNew) {
            FixedAssetEditorView(asset: nil).environmentObject(store)
        }
        .sheet(item: $editingAsset) { asset in
            FixedAssetEditorView(asset: asset).environmentObject(store)
        }
        .sheet(item: $disposingAsset) { asset in
            FixedAssetDisposalView(asset: asset).environmentObject(store)
        }
    }

    private var reportingDate: Date {
        guard customAsOfEnabled else { return Date() }
        let start = Calendar.current.startOfDay(for: asOfDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? asOfDate
    }

    private var allRegisterAssets: [FixedAssetRecord] {
        var records = store.fixedAssetRecords
        let linkedAccountIDs = Set(records.compactMap(\.linkedAccountID))
        let fixedAccounts = store.accounts.filter {
            !$0.isArchived && $0.nature == .fixedAsset && !linkedAccountIDs.contains($0.id)
        }
        for account in fixedAccounts {
            records.append(FixedAssetRecord(
                id: account.id,
                assetNumber: account.chartCode ?? "",
                name: account.name,
                category: "Needs Details",
                currencyCode: account.currencyCode,
                linkedAccountID: account.id,
                purchaseDate: account.createdAt,
                cost: 0,
                residualValue: 0,
                depreciationStartDate: account.createdAt,
                depreciationMethod: .none,
                annualDepreciationRate: 0,
                usefulLifeMonths: 0,
                openingAccumulatedDepreciation: 0,
                status: .active,
                notes: "Created automatically from Chart of Accounts. Complete the FAR details."
            ))
        }
        return records
    }

    private func needsDetails(_ asset: FixedAssetRecord) -> Bool {
        !store.fixedAssetRecords.contains(where: { $0.id == asset.id })
    }

    private func effectiveStatus(_ asset: FixedAssetRecord) -> FixedAssetStatus {
        if let disposalDate = asset.disposalDate,
           disposalDate <= reportingDate,
           asset.status != .active {
            return asset.status
        }
        return .active
    }

    private var filteredAssets: [FixedAssetRecord] {
        allRegisterAssets.filter { asset in
            guard asset.purchaseDate <= reportingDate else { return false }
            let status = effectiveStatus(asset)
            let statusMatches: Bool
            switch filter {
            case .active: statusMatches = status == .active
            case .sold: statusMatches = status == .sold
            case .disposed: statusMatches = status == .disposed
            case .all: statusMatches = true
            }
            guard statusMatches else { return false }
            guard !searchText.isEmpty else { return true }
            return asset.assetNumber.localizedCaseInsensitiveContains(searchText)
                || asset.name.localizedCaseInsensitiveContains(searchText)
                || asset.category.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private var groupedCategories: [(String, [FixedAssetRecord])] {
        Dictionary(grouping: filteredAssets, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private var summaries: [FixedAssetCurrencySummary] {
        let grouped = Dictionary(grouping: filteredAssets, by: \.currencyCode)
        return grouped.map { currency, assets in
            let now = reportingDate
            return FixedAssetCurrencySummary(
                currency: currency,
                cost: assets.reduce(0) { $0 + $1.cost },
                accumulated: assets.reduce(0) { $0 + $1.accumulatedDepreciation(asOf: now) },
                nbv: assets.reduce(0) { $0 + $1.netBookValue(asOf: now) },
                gainLoss: assets.reduce(0) { $0 + ($1.disposalGainLoss ?? 0) }
            )
        }.sorted { $0.currency < $1.currency }
    }
}

private struct FixedAssetRegisterRow: View {
    let asset: FixedAssetRecord
    let asOfDate: Date
    let needsDetails: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: asset.status == .active ? "building.2.fill" : "archivebox.fill")
                .foregroundStyle(statusColor)
                .frame(width: 38, height: 38)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.body.weight(.semibold))
                Text([asset.assetNumber, asset.category].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(asset.status.title)
                    .font(.caption2.bold()).foregroundStyle(statusColor)
                if needsDetails {
                    Text("NEEDS DETAILS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppTheme.orange.opacity(0.12), in: Capsule())
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("NBV " + DisplayFormat.currency(asset.netBookValue(asOf: asOfDate), code: asset.currencyCode))
                    .font(.caption.bold())
                Text("Cost " + DisplayFormat.currency(asset.cost, code: asset.currencyCode))
                    .font(.caption2).foregroundStyle(.secondary)
                if let gainLoss = asset.disposalGainLoss {
                    Text((gainLoss >= 0 ? "Gain " : "Loss ") + DisplayFormat.currency(abs(gainLoss), code: asset.currencyCode))
                        .font(.caption2.bold())
                        .foregroundStyle(gainLoss >= 0 ? AppTheme.green : AppTheme.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch asset.status {
        case .active: return AppTheme.green
        case .sold: return AppTheme.blue
        case .disposed: return AppTheme.orange
        }
    }
}

private struct FixedAssetEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FixedAssetRecord
    @State private var costText: String
    @State private var residualText: String
    @State private var rateText: String
    @State private var lifeText: String
    @State private var openingDepText: String
    private let isNew: Bool
    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]

    init(asset: FixedAssetRecord?) {
        let defaultRate = ERPStorage.decimal(ERPKey.fixedAssetDefaultRate, 15)
        let defaultLife = max(1, ERPStorage.int(ERPKey.fixedAssetDefaultLifeMonths, 60))
        let defaultResidualPercent = max(0, min(100, ERPStorage.decimal(ERPKey.fixedAssetDefaultResidualPercent, 0)))
        let newValue = FixedAssetRecord(
            residualValue: 0,
            annualDepreciationRate: defaultRate,
            usefulLifeMonths: defaultLife,
            notes: defaultResidualPercent > 0 ? "ERP residual-value default: \(NSDecimalNumber(decimal: defaultResidualPercent).stringValue)% of cost." : ""
        )
        let value = asset ?? newValue
        _draft = State(initialValue: value)
        _costText = State(initialValue: NSDecimalNumber(decimal: value.cost).stringValue)
        _residualText = State(initialValue: NSDecimalNumber(decimal: value.residualValue).stringValue)
        _rateText = State(initialValue: NSDecimalNumber(decimal: value.annualDepreciationRate).stringValue)
        _lifeText = State(initialValue: String(value.usefulLifeMonths))
        _openingDepText = State(initialValue: NSDecimalNumber(decimal: value.openingAccumulatedDepreciation).stringValue)
        isNew = asset == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset Identity") {
                    TextField("Asset number / tag", text: $draft.assetNumber)
                    TextField("Asset name", text: $draft.name)
                    Menu {
                        ForEach(store.fixedAssetCategories, id: \.self) { category in
                            Button(category) { draft.category = category }
                        }
                    } label: {
                        LabeledContent("Choose Category", value: draft.category)
                    }
                    TextField("Category", text: $draft.category)
                    Picker("Currency", selection: $draft.currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Linked Fixed Asset Account", selection: $draft.linkedAccountID) {
                        Text("Not Linked").tag(Optional<UUID>.none)
                        ForEach(linkableAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }

                Section("Acquisition") {
                    DatePicker("Purchase Date", selection: $draft.purchaseDate, displayedComponents: .date)
                    TextField("Original Cost", text: $costText).keyboardType(.numbersAndPunctuation)
                    TextField("Residual Value", text: $residualText).keyboardType(.numbersAndPunctuation)
                }

                Section("Depreciation") {
                    Picker("Method", selection: $draft.depreciationMethod) {
                        ForEach(FixedAssetDepreciationMethod.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Depreciation Start", selection: $draft.depreciationStartDate, displayedComponents: .date)
                    if draft.depreciationMethod == .straightLineRate {
                        TextField("Annual Rate %", text: $rateText).keyboardType(.decimalPad)
                    } else if draft.depreciationMethod == .straightLineLife {
                        TextField("Useful Life (Months)", text: $lifeText).keyboardType(.numberPad)
                    }
                    TextField("Opening Accumulated Depreciation", text: $openingDepText)
                        .keyboardType(.numbersAndPunctuation)
                    Text("Full-month straight-line convention is used from the depreciation start month.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Current Register Preview") {
                    LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(preview.accumulatedDepreciation(asOf: Date()), code: preview.currencyCode))
                    LabeledContent("Net Book Value", value: DisplayFormat.currency(preview.netBookValue(asOf: Date()), code: preview.currencyCode))
                    LabeledContent("Status", value: preview.status.title)
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 90)
                }
            }
            .navigationTitle(isNew ? "Register Fixed Asset" : "Edit Fixed Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private var linkableAccounts: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.nature == .asset || $0.nature == .fixedAsset || $0.group == .assets
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }

    private var preview: FixedAssetRecord {
        var value = draft
        value.cost = decimal(costText) ?? 0
        value.residualValue = decimal(residualText) ?? 0
        value.annualDepreciationRate = decimal(rateText) ?? 0
        value.usefulLifeMonths = Int(lifeText) ?? 0
        value.openingAccumulatedDepreciation = decimal(openingDepText) ?? 0
        return value
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (decimal(costText) ?? 0) > 0
            && (decimal(residualText) ?? 0) >= 0
            && (decimal(openingDepText) ?? 0) >= 0
            && (draft.depreciationMethod != .straightLineLife || (Int(lifeText) ?? 0) > 0)
    }

    private func save() {
        var value = preview
        if isNew, ERPAccountingEngine.isEnabled, value.residualValue == 0 {
            let residualPercent = max(0, min(100, ERPStorage.decimal(ERPKey.fixedAssetDefaultResidualPercent, 0)))
            if residualPercent > 0 {
                value.residualValue = ERPAccountingEngine.round(
                    value.cost * residualPercent / 100,
                    scale: max(0, min(6, ERPStorage.int(ERPKey.fixedAssetDepreciationDecimals, 2)))
                )
            }
        }
        if value.assetNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.assetNumber = String(format: "FA-%04d", store.fixedAssetRecords.count + 1)
        }
        store.saveFixedAssetRecord(value)
        dismiss()
    }
}

private struct FixedAssetDisposalView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let asset: FixedAssetRecord
    @State private var status: FixedAssetStatus
    @State private var disposalDate: Date
    @State private var proceedsText: String
    @State private var reason: String

    init(asset: FixedAssetRecord) {
        self.asset = asset
        _status = State(initialValue: asset.status == .active ? .sold : asset.status)
        _disposalDate = State(initialValue: asset.disposalDate ?? Date())
        _proceedsText = State(initialValue: NSDecimalNumber(decimal: asset.disposalProceeds ?? 0).stringValue)
        _reason = State(initialValue: asset.disposalReason)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset") {
                    LabeledContent("Asset", value: asset.name)
                    LabeledContent("Asset No.", value: asset.assetNumber)
                    LabeledContent("Original Cost", value: DisplayFormat.currency(asset.cost, code: asset.currencyCode))
                }
                Section("Sale / Disposal") {
                    Picker("Type", selection: $status) {
                        Text("Sold").tag(FixedAssetStatus.sold)
                        Text("Disposed").tag(FixedAssetStatus.disposed)
                    }
                    DatePicker("Date", selection: $disposalDate, displayedComponents: .date)
                    TextField("Sale / Disposal Proceeds", text: $proceedsText).keyboardType(.numbersAndPunctuation)
                    TextField("Reason / Reference", text: $reason)
                }
                Section("Accounting Result") {
                    LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(asset.accumulatedDepreciation(asOf: disposalDate), code: asset.currencyCode))
                    LabeledContent("NBV at Disposal", value: DisplayFormat.currency(asset.netBookValue(asOf: disposalDate), code: asset.currencyCode))
                    LabeledContent("Proceeds", value: DisplayFormat.currency(proceeds, code: asset.currencyCode))
                    LabeledContent("Gain / (Loss)", value: DisplayFormat.currency(gainLoss, code: asset.currencyCode))
                        .foregroundStyle(gainLoss >= 0 ? AppTheme.green : AppTheme.red)
                }
            }
            .navigationTitle("Sell / Dispose Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Post to Register", action: save) }
            }
        }
    }

    private var proceeds: Decimal {
        Decimal(string: proceedsText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
    private var gainLoss: Decimal { proceeds - asset.netBookValue(asOf: disposalDate) }

    private func save() {
        var value = asset
        value.status = status
        value.disposalDate = disposalDate
        value.disposalProceeds = proceeds
        value.disposalReason = reason
        store.saveFixedAssetRecord(value)
        dismiss()
    }
}

private enum FixedLiabilityFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case settled = "Settled"
    case all = "All"
    var id: String { rawValue }
}

struct FixedLiabilityRegisterView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: FixedLiabilityFilter = .active
    @State private var showingNew = false
    @State private var editing: FixedLiabilityRecord?
    @State private var searchText = ""

    var body: some View {
        List {
            filterSection
            summarySections
            liabilitySections
        }
        .navigationTitle("Fixed Liabilities")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Liability, lender, category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Register fixed liability")
            }
        }
        .sheet(isPresented: $showingNew) {
            FixedLiabilityEditorView(record: nil)
                .environmentObject(store)
        }
        .sheet(item: $editing) { record in
            FixedLiabilityEditorView(record: record)
                .environmentObject(store)
        }
    }

    private var filterSection: some View {
        Section {
            Picker("Register", selection: $filter) {
                ForEach(FixedLiabilityFilter.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text("Linked liabilities use the account ledger only. No manual principal is added. Liability → Bank/Account records loan taken; Bank/Account → Liability records installments. Liability → Liability is internal refinancing.")
        }
    }

    @ViewBuilder
    private var summarySections: some View {
        ForEach(currencySummaries) { summary in
            FixedLiabilitySummarySectionView(
                summary: summary,
                loanTransactions: increaseTransactions(for: summary.currency),
                installmentTransactions: repaymentTransactions(for: summary.currency),
                allTransactions: allTransactions(for: summary.currency),
                liabilityAccountIDs: liabilityAccountIDs(for: summary.currency)
            )
            .environmentObject(store)
        }
    }

    @ViewBuilder
    private var liabilitySections: some View {
        if filtered.isEmpty {
            Section {
                EmptyLedgerView(title: emptyTitle, message: emptyMessage)
            }
        } else {
            ForEach(groupedCategories, id: \.0) { category, items in
                Section(category) {
                    ForEach(items) { item in
                        liabilityButton(item)
                    }
                }
            }
        }
    }

    private func liabilityButton(_ item: FixedLiabilityRecord) -> some View {
        NavigationLink {
            FixedLiabilityTransactionDrilldownView(
                title: item.name,
                transactions: store.fixedLiabilityAllTransactions(item),
                liabilityAccountIDs: Set(item.linkedAccountID.map { [$0] } ?? []),
                openingAmount: store.fixedLiabilitySnapshot(item).originalPrincipal,
                currencyCode: item.currencyCode
            )
            .environmentObject(store)
        } label: {
            FixedLiabilityRegisterRow(
                item: item,
                snapshot: store.fixedLiabilitySnapshot(item),
                needsDetails: needsDetails(item)
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editing = item
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.blue)
        }
    }

    private var emptyTitle: String {
        filter == .settled ? "No settled liabilities" : "No fixed liabilities"
    }

    private var emptyMessage: String {
        if filter == .settled {
            return "A linked liability moves here automatically when repayments reduce its outstanding amount to zero."
        }
        return "Register long-term loans, lease liabilities and other fixed liabilities here."
    }

    private var allRegisterLiabilities: [FixedLiabilityRecord] {
        var records = store.fixedLiabilityRecords
        let linked = Set(records.compactMap(\.linkedAccountID))
        let accounts = store.accounts.filter {
            !$0.isArchived && $0.nature == .fixedLiability && !linked.contains($0.id)
        }
        for account in accounts {
            let principal = store.fixedLiabilitySuggestedPrincipal(for: account)
            records.append(FixedLiabilityRecord(
                id: account.id,
                reference: account.chartCode ?? "",
                name: account.name,
                category: "Needs Details",
                lender: "",
                currencyCode: account.currencyCode,
                linkedAccountID: account.id,
                startDate: account.createdAt,
                originalPrincipal: principal,
                notes: "Created automatically from Chart of Accounts. Complete the liability register details."
            ))
        }
        return records
    }

    private func needsDetails(_ item: FixedLiabilityRecord) -> Bool {
        !store.fixedLiabilityRecords.contains { $0.id == item.id }
    }

    private var filtered: [FixedLiabilityRecord] {
        allRegisterLiabilities.filter { item in
            let effectiveStatus = store.fixedLiabilitySnapshot(item).status
            let statusMatches: Bool
            switch filter {
            case .active:
                statusMatches = effectiveStatus == .active
            case .settled:
                statusMatches = effectiveStatus == .settled
            case .all:
                statusMatches = true
            }
            guard statusMatches else { return false }
            if searchText.isEmpty { return true }
            return item.name.localizedCaseInsensitiveContains(searchText)
                || item.lender.localizedCaseInsensitiveContains(searchText)
                || item.category.localizedCaseInsensitiveContains(searchText)
                || item.reference.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.startDate > $1.startDate }
    }

    private var groupedCategories: [(String, [FixedLiabilityRecord])] {
        let grouped = Dictionary(grouping: filtered, by: \.category)
        return grouped.map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func records(for currency: String) -> [FixedLiabilityRecord] {
        filtered.filter { $0.currencyCode == currency }
    }

    private func increaseTransactions(for currency: String) -> [LedgerTransaction] {
        uniqueTransactions(records(for: currency).flatMap { store.fixedLiabilityIncreaseTransactions($0) })
    }

    private func repaymentTransactions(for currency: String) -> [LedgerTransaction] {
        uniqueTransactions(records(for: currency).flatMap { store.fixedLiabilityRepaymentTransactions($0) })
    }

    private func allTransactions(for currency: String) -> [LedgerTransaction] {
        uniqueTransactions(records(for: currency).flatMap { store.fixedLiabilityAllTransactions($0) })
    }

    private func liabilityAccountIDs(for currency: String) -> Set<UUID> {
        Set(records(for: currency).compactMap(\.linkedAccountID))
    }

    private func uniqueTransactions(_ values: [LedgerTransaction]) -> [LedgerTransaction] {
        var seen = Set<UUID>()
        return values
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
    }

    private var currencySummaries: [FixedLiabilityCurrencySummary] {
        let grouped = Dictionary(grouping: filtered, by: \.currencyCode)
        var output: [FixedLiabilityCurrencySummary] = []
        for currency in grouped.keys.sorted() {
            let values = grouped[currency] ?? []
            var original: Decimal = 0
            var increases: Decimal = 0
            var repayments: Decimal = 0
            var outstanding: Decimal = 0
            var currentPortion: Decimal = 0
            for item in values {
                let ledger = store.fixedLiabilitySnapshot(item)
                original += ledger.originalPrincipal
                increases += ledger.increases
                repayments += ledger.repayments
                outstanding += ledger.outstanding
                currentPortion += min(max(0, item.currentPortion), ledger.outstanding)
            }
            output.append(FixedLiabilityCurrencySummary(
                currency: currency,
                originalPrincipal: original,
                increases: increases,
                repayments: repayments,
                outstanding: outstanding,
                currentPortion: currentPortion
            ))
        }
        return output
    }
}

private struct FixedLiabilitySummarySectionView: View {
    @EnvironmentObject private var store: LedgerStore
    let summary: FixedLiabilityCurrencySummary
    let loanTransactions: [LedgerTransaction]
    let installmentTransactions: [LedgerTransaction]
    let allTransactions: [LedgerTransaction]
    let liabilityAccountIDs: Set<UUID>

    var body: some View {
        Section {
            NavigationLink {
                drilldown(
                    title: "Loan Recorded · \(summary.currency)",
                    transactions: loanTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow("Loan Recorded", summary.originalPrincipal + summary.increases)
            }

            NavigationLink {
                drilldown(
                    title: "Installments Paid · \(summary.currency)",
                    transactions: installmentTransactions,
                    openingAmount: 0
                )
            } label: {
                valueRow("Installments Paid", summary.repayments, green: true)
            }

            NavigationLink {
                drilldown(
                    title: "Outstanding Liability · \(summary.currency)",
                    transactions: allTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow("Outstanding Liability", summary.outstanding, bold: true)
            }

            NavigationLink {
                drilldown(
                    title: "Current Portion · \(summary.currency)",
                    transactions: allTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow("Current Portion", summary.currentPortion)
            }

            NavigationLink {
                drilldown(
                    title: "Long-Term Portion · \(summary.currency)",
                    transactions: allTransactions,
                    openingAmount: summary.originalPrincipal
                )
            } label: {
                valueRow(
                    "Long-Term Portion",
                    max(0, summary.outstanding - summary.currentPortion)
                )
            }
        } header: {
            Text("\(summary.currency) Summary")
        } footer: {
            Text("Tap any figure to open the real liability-account transactions behind it.")
        }
    }

    private func drilldown(
        title: String,
        transactions: [LedgerTransaction],
        openingAmount: Decimal
    ) -> some View {
        FixedLiabilityTransactionDrilldownView(
            title: title,
            transactions: transactions,
            liabilityAccountIDs: liabilityAccountIDs,
            openingAmount: openingAmount,
            currencyCode: summary.currency
        )
        .environmentObject(store)
    }

    @ViewBuilder
    private func valueRow(
        _ title: String,
        _ value: Decimal,
        green: Bool = false,
        bold: Bool = false
    ) -> some View {
        LabeledContent(title, value: DisplayFormat.currency(value, code: summary.currency))
            .font(bold ? .body.bold() : .body)
            .foregroundStyle(green ? AppTheme.green : .primary)
    }
}

private struct FixedLiabilityCurrencySummary: Identifiable {
    let currency: String
    let originalPrincipal: Decimal
    let increases: Decimal
    let repayments: Decimal
    let outstanding: Decimal
    let currentPortion: Decimal
    var id: String { currency }
}

private struct FixedLiabilityRegisterRow: View {
    let item: FixedLiabilityRecord
    let snapshot: FixedLiabilityLedgerSnapshot
    let needsDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: snapshot.status == .settled ? "checkmark.seal.fill" : "calendar.badge.clock")
                    .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
                    .frame(width: 38, height: 38)
                    .background(
                        (snapshot.status == .settled ? AppTheme.green : AppTheme.orange).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.body.weight(.semibold))
                    Text([item.reference, item.lender].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(snapshot.status.title.uppercased())
                            .font(.caption2.bold())
                            .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
                        if needsDetails {
                            Text("NEEDS DETAILS")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.orange)
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Outstanding " + DisplayFormat.currency(snapshot.outstanding, code: item.currencyCode))
                        .font(.caption.bold())
                    Text("Repaid " + DisplayFormat.currency(snapshot.repayments, code: item.currencyCode))
                        .font(.caption2.bold())
                        .foregroundStyle(AppTheme.green)
                    if let date = snapshot.settledDate, snapshot.status == .settled {
                        Text("Settled " + date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ProgressView(value: snapshot.repaymentProgress)
                .tint(snapshot.status == .settled ? AppTheme.green : AppTheme.blue)
            HStack {
                Text("Loan Recorded " + DisplayFormat.currency(
                    snapshot.originalPrincipal + snapshot.increases,
                    code: item.currencyCode
                ))
                Spacer()
                Text("Installments " + DisplayFormat.currency(snapshot.repayments, code: item.currencyCode))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

private struct FixedLiabilityTransactionDrilldownView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let transactions: [LedgerTransaction]
    let liabilityAccountIDs: Set<UUID>
    let openingAmount: Decimal
    let currencyCode: String

    var body: some View {
        List {
            if openingAmount > 0 {
                Section("Opening Liability") {
                    LabeledContent(
                        "Opening Balance",
                        value: DisplayFormat.currency(openingAmount, code: currencyCode)
                    )
                    Text("Opening balance is counted once. It is not a transaction and is never added again as manual principal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if transactions.isEmpty {
                    Text("No posted transaction is behind this amount yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { transaction in
                        NavigationLink {
                            TransactionSnapshotView(transaction: transaction)
                                .environmentObject(store)
                        } label: {
                            TransactionRow(
                                transaction: transaction,
                                accountID: relevantLiabilityAccountID(transaction)
                            )
                        }
                    }
                }
            } header: {
                Text("Related Transactions")
            } footer: {
                Text("\(transactions.count) real transaction\(transactions.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func relevantLiabilityAccountID(_ transaction: LedgerTransaction) -> UUID? {
        if let source = transaction.accountID, liabilityAccountIDs.contains(source) {
            return source
        }
        if let destination = transaction.destinationAccountID,
           liabilityAccountIDs.contains(destination) {
            return destination
        }
        return transaction.accountID
    }
}

private struct FixedLiabilityEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FixedLiabilityRecord
    @State private var principalText: String
    @State private var rateText: String
    @State private var currentPortionText: String
    @State private var hasMaturity: Bool
    private let isNew: Bool
    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]

    init(record: FixedLiabilityRecord?) {
        let value = record ?? FixedLiabilityRecord()
        _draft = State(initialValue: value)
        _principalText = State(initialValue: NSDecimalNumber(decimal: value.originalPrincipal).stringValue)
        _rateText = State(initialValue: NSDecimalNumber(decimal: value.annualInterestRate).stringValue)
        _currentPortionText = State(initialValue: NSDecimalNumber(decimal: value.currentPortion).stringValue)
        _hasMaturity = State(initialValue: value.maturityDate != nil)
        isNew = record == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                liabilitySection
                termsSection
                settlementContent
                notesSection
                deleteContent
            }
            .navigationTitle(isNew ? "Register Fixed Liability" : "Edit Fixed Liability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
            .onChange(of: draft.linkedAccountID) { value in
                linkedAccountChanged(value)
            }
        }
    }

    private var liabilitySection: some View {
        FixedLiabilityIdentityEditorSection(
            reference: $draft.reference,
            name: $draft.name,
            lender: $draft.lender,
            category: $draft.category,
            currencyCode: $draft.currencyCode,
            linkedAccountID: $draft.linkedAccountID,
            categories: store.fixedLiabilityCategories,
            currencies: currencies,
            accounts: linkableAccounts
        )
    }

    private var termsSection: some View {
        FixedLiabilityTermsEditorSection(
            startDate: $draft.startDate,
            hasMaturity: $hasMaturity,
            maturityDate: maturityBinding,
            principalText: $principalText,
            usesLinkedLedger: draft.linkedAccountID != nil,
            rateText: $rateText,
            currentPortionText: $currentPortionText
        )
    }

    @ViewBuilder
    private var settlementContent: some View {
        if draft.linkedAccountID != nil {
            FixedLiabilitySettlementEditorSection(
                snapshot: ledgerPreview,
                currencyCode: draft.currencyCode
            )
            FixedLiabilityRepaymentsEditorSection(
                transactions: recentRepayments,
                currencyCode: draft.currencyCode
            )
            .environmentObject(store)
        } else {
            FixedLiabilityManualStatusEditorSection(
                status: $draft.status,
                settledDate: settledDateBinding
            )
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextEditor(text: $draft.notes)
                .frame(minHeight: 90)
        }
    }

    @ViewBuilder
    private var deleteContent: some View {
        if !isNew {
            Section {
                Button("Delete Register Record", role: .destructive) {
                    store.deleteFixedLiabilityRecord(draft.id)
                    dismiss()
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save", action: save)
                .disabled(!canSave)
        }
    }

    private var linkableAccounts: [LedgerAccount] {
        store.activeAccounts.filter { account in
            account.nature == .loan || account.nature == .fixedLiability || account.group == .payments
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var maturityBinding: Binding<Date> {
        Binding(
            get: { draft.maturityDate ?? Date() },
            set: { draft.maturityDate = $0 }
        )
    }

    private var settledDateBinding: Binding<Date> {
        Binding(
            get: { draft.settledDate ?? Date() },
            set: { draft.settledDate = $0 }
        )
    }

    private func decimal(_ text: String) -> Decimal? {
        Decimal(
            string: text.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private var previewRecord: FixedLiabilityRecord {
        var value = draft
        value.originalPrincipal = decimal(principalText) ?? 0
        value.annualInterestRate = decimal(rateText) ?? 0
        value.currentPortion = decimal(currentPortionText) ?? 0
        return value
    }

    private var ledgerPreview: FixedLiabilityLedgerSnapshot {
        store.fixedLiabilitySnapshot(previewRecord)
    }

    private var recentRepayments: [LedgerTransaction] {
        Array(store.fixedLiabilityRepaymentTransactions(previewRecord).prefix(15))
    }

    private var canSave: Bool {
        let nameOK = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let categoryOK = !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let principalOK = draft.linkedAccountID != nil || (decimal(principalText) ?? 0) > 0
        return nameOK && categoryOK && principalOK
    }

    private func linkedAccountChanged(_ value: UUID?) {
        guard let account = store.account(withID: value) else { return }
        draft.currencyCode = account.currencyCode
    }

    private func save() {
        draft.originalPrincipal = decimal(principalText) ?? 0
        draft.annualInterestRate = decimal(rateText) ?? 0
        let enteredCurrentPortion = max(0, decimal(currentPortionText) ?? 0)
        draft.currentPortion = enteredCurrentPortion
        if !hasMaturity {
            draft.maturityDate = nil
        }
        if draft.linkedAccountID != nil {
            let calculated = store.fixedLiabilitySnapshot(draft)
            draft.currentPortion = min(enteredCurrentPortion, calculated.outstanding)
            draft.status = calculated.status
            draft.settledDate = calculated.settledDate
        } else {
            draft.currentPortion = min(enteredCurrentPortion, max(0, draft.originalPrincipal))
            if draft.status == .active {
                draft.settledDate = nil
            }
        }
        if draft.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.reference = String(format: "FL-%04d", store.fixedLiabilityRecords.count + 1)
        }
        store.saveFixedLiabilityRecord(draft)
        dismiss()
    }
}

private struct FixedLiabilityIdentityEditorSection: View {
    @Binding var reference: String
    @Binding var name: String
    @Binding var lender: String
    @Binding var category: String
    @Binding var currencyCode: String
    @Binding var linkedAccountID: UUID?
    let categories: [String]
    let currencies: [String]
    let accounts: [LedgerAccount]

    var body: some View {
        Section("Liability") {
            TextField("Reference", text: $reference)
            TextField("Name", text: $name)
            TextField("Lender / Counterparty", text: $lender)
            Picker("Category", selection: $category) {
                if !categories.contains(category) && !category.isEmpty {
                    Text(category).tag(category)
                }
                ForEach(categories, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            TextField("Custom Category", text: $category)
            Picker("Currency", selection: $currencyCode) {
                ForEach(currencies, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            Picker("Linked Liability Account", selection: $linkedAccountID) {
                Text("Not Linked").tag(Optional<UUID>.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
        }
    }
}

private struct FixedLiabilityTermsEditorSection: View {
    @Binding var startDate: Date
    @Binding var hasMaturity: Bool
    let maturityDate: Binding<Date>
    @Binding var principalText: String
    let usesLinkedLedger: Bool
    @Binding var rateText: String
    @Binding var currentPortionText: String

    var body: some View {
        Section("Terms") {
            DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
            Toggle("Has Maturity Date", isOn: $hasMaturity)
            if hasMaturity {
                DatePicker("Maturity", selection: maturityDate, displayedComponents: .date)
            }
            if usesLinkedLedger {
                LabeledContent("Loan Amount", value: "From linked account ledger")
                Text("Manual Original Principal is not added for linked liabilities, preventing double counting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                TextField("Original Principal", text: $principalText)
                    .keyboardType(.numbersAndPunctuation)
            }
            TextField("Annual Interest %", text: $rateText)
                .keyboardType(.decimalPad)
            TextField("Current Portion (Next 12 Months)", text: $currentPortionText)
                .keyboardType(.numbersAndPunctuation)
        }
    }
}

private struct FixedLiabilitySettlementEditorSection: View {
    let snapshot: FixedLiabilityLedgerSnapshot
    let currencyCode: String

    var body: some View {
        Section {
            valueRow("Loan Recorded", snapshot.originalPrincipal + snapshot.increases)
            valueRow("Installments Paid", snapshot.repayments, incoming: true)
            valueRow("Outstanding Liability", snapshot.outstanding, emphasized: true)
            LabeledContent("Status", value: snapshot.status.title)
                .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
            ProgressView(value: snapshot.repaymentProgress)
                .tint(snapshot.status == .settled ? AppTheme.green : AppTheme.blue)
            if let date = snapshot.settledDate, snapshot.status == .settled {
                LabeledContent(
                    "Settled Date",
                    value: date.formatted(date: .long, time: .omitted)
                )
            }
        } header: {
            Text("Ledger Settlement")
        } footer: {
            Text("Linked status comes only from the account ledger. No manual principal is added. Bank/Account → Liability is an installment; Liability → Bank/Account is loan taken/increase.")
        }
    }

    @ViewBuilder
    private func valueRow(
        _ title: String,
        _ value: Decimal,
        incoming: Bool = false,
        emphasized: Bool = false
    ) -> some View {
        LabeledContent(title, value: DisplayFormat.currency(value, code: currencyCode))
            .font(emphasized ? .body.bold() : .body)
            .foregroundStyle(incoming ? AppTheme.green : .primary)
    }
}

private struct FixedLiabilityRepaymentsEditorSection: View {
    @EnvironmentObject private var store: LedgerStore
    let transactions: [LedgerTransaction]
    let currencyCode: String

    var body: some View {
        Section("Recent Installments") {
            if transactions.isEmpty {
                Text("No Bank/Account → Liability installments found yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transactions) { transaction in
                    repaymentRow(transaction)
                }
            }
        }
    }

    private func repaymentRow(_ transaction: LedgerTransaction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.details.isEmpty ? "Liability installment" : transaction.details)
                    .font(.caption)
                    .lineLimit(2)
                Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("−" + DisplayFormat.currency(
                store.effectiveDestinationAmount(transaction),
                code: currencyCode
            ))
            .font(.caption.bold())
            .foregroundStyle(AppTheme.green)
        }
    }
}

private struct FixedLiabilityManualStatusEditorSection: View {
    @Binding var status: FixedLiabilityStatus
    let settledDate: Binding<Date>

    var body: some View {
        Section {
            Picker("Status", selection: $status) {
                ForEach(FixedLiabilityStatus.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if status == .settled {
                DatePicker("Settled Date", selection: settledDate, displayedComponents: .date)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Link a liability account to calculate repayment and settlement automatically from ledger transactions.")
        }
    }
}


private struct FixedAssetRegisterExportView: View {
    @Environment(\.dismiss) private var dismiss
    let assets: [FixedAssetRecord]
    let asOfDate: Date
    let registerTitle: String
    @State private var generatedURL: URL?
    @State private var generatedLabel = ""
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FIXED ASSET REGISTER SNAPSHOT")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(registerTitle)
                            .font(.title2.bold())
                        Text("As of \(asOfDate.formatted(date: .long, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(currencySummaries, id: \.currency) { summary in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(summary.currency).font(.headline)
                            LabeledContent("Cost", value: DisplayFormat.currency(summary.cost, code: summary.currency))
                            LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(summary.accumulated, code: summary.currency))
                            LabeledContent("Net Book Value", value: DisplayFormat.currency(summary.nbv, code: summary.currency))
                            LabeledContent("Gain / (Loss)", value: DisplayFormat.currency(summary.gainLoss, code: summary.currency))
                        }
                        .padding(14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Register Detail · \(assets.count) assets")
                            .font(.headline)
                        ForEach(assets.prefix(30)) { asset in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(asset.assetNumber.isEmpty ? "—" : asset.assetNumber)
                                        .font(.caption.bold())
                                    Text(asset.name).font(.subheadline.bold())
                                    Spacer()
                                    Text(asset.status.title).font(.caption)
                                }
                                HStack {
                                    Text(asset.category).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Cost " + DisplayFormat.currency(asset.cost, code: asset.currencyCode))
                                        .font(.caption)
                                    Text("NBV " + DisplayFormat.currency(asset.netBookValue(asOf: asOfDate), code: asset.currencyCode))
                                        .font(.caption.bold())
                                }
                            }
                            .padding(.vertical, 5)
                            Divider()
                        }
                        if assets.count > 30 {
                            Text("Snapshot shows first 30 rows. The downloaded file contains all \(assets.count) rows.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.red)
                    }
                    if let generatedURL {
                        ShareLink(item: generatedURL) {
                            Label("Share / Save \(generatedLabel)", systemImage: "square.and.arrow.up.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.page)
            .navigationTitle("Report Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            generatePDF()
                        } label: {
                            Label("PDF", systemImage: "doc.richtext.fill")
                        }
                        Button {
                            generateCSV()
                        } label: {
                            Label("Excel / CSV", systemImage: "tablecells.fill")
                        }
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down.fill")
                    }
                }
            }
        }
    }

    private var currencySummaries: [(currency: String, cost: Decimal, accumulated: Decimal, nbv: Decimal, gainLoss: Decimal)] {
        let grouped = Dictionary(grouping: assets, by: { $0.currencyCode })
        var result: [(currency: String, cost: Decimal, accumulated: Decimal, nbv: Decimal, gainLoss: Decimal)] = []
        for currency in grouped.keys.sorted() {
            let values = grouped[currency] ?? []
            var cost = Decimal.zero
            var accumulated = Decimal.zero
            var nbv = Decimal.zero
            var gainLoss = Decimal.zero
            for asset in values {
                cost += asset.cost
                accumulated += asset.accumulatedDepreciation(asOf: asOfDate)
                nbv += asset.netBookValue(asOf: asOfDate)
                gainLoss += asset.disposalGainLoss ?? 0
            }
            result.append((currency, cost, accumulated, nbv, gainLoss))
        }
        return result
    }

    private func generatePDF() {
        do {
            generatedURL = try FixedAssetRegisterFileExporter.pdf(assets: assets, asOfDate: asOfDate, title: registerTitle)
            generatedLabel = "PDF"
            exportError = nil
        } catch {
            exportError = "PDF could not be generated: \(error.localizedDescription)"
        }
    }

    private func generateCSV() {
        do {
            generatedURL = try FixedAssetRegisterFileExporter.csv(assets: assets, asOfDate: asOfDate, title: registerTitle)
            generatedLabel = "Excel / CSV"
            exportError = nil
        } catch {
            exportError = "Excel file could not be generated: \(error.localizedDescription)"
        }
    }
}

private enum FixedAssetRegisterFileExporter {
    static func pdf(assets: [FixedAssetRecord], asOfDate: Date, title: String) throws -> URL {
        let url = temporaryURL(ext: "pdf", prefix: "Fixed-Asset-Register")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            let margin: CGFloat = 34
            var y: CGFloat = margin
            let normal: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.label
            ]
            let bold: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 9),
                .foregroundColor: UIColor.label
            ]
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: UIColor.label
            ]

            func newPage() {
                context.beginPage()
                y = margin
                NSString(string: "Fixed Asset Register — \(title)").draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                y += 24
                NSString(string: "As of \(asOfDate.formatted(date: .long, time: .omitted))").draw(at: CGPoint(x: margin, y: y), withAttributes: normal)
                y += 22
                NSString(string: "Asset No.   Asset / Category                         Cost           Accum.Dep.      NBV            Status").draw(at: CGPoint(x: margin, y: y), withAttributes: bold)
                y += 16
            }

            newPage()
            for asset in assets {
                if y > page.height - 48 { newPage() }
                let no = short(asset.assetNumber.isEmpty ? "—" : asset.assetNumber, 10)
                let name = short("\(asset.name) / \(asset.category)", 35)
                let cost = number(asset.cost)
                let dep = number(asset.accumulatedDepreciation(asOf: asOfDate))
                let nbv = number(asset.netBookValue(asOf: asOfDate))
                let line = String(format: "%-10@ %-35@ %12@ %12@ %12@  %@", no as NSString, name as NSString, cost as NSString, dep as NSString, nbv as NSString, asset.status.title as NSString)
                NSString(string: line).draw(at: CGPoint(x: margin, y: y), withAttributes: normal)
                y += 14
            }
        }
        return url
    }

    static func csv(assets: [FixedAssetRecord], asOfDate: Date, title: String) throws -> URL {
        let url = temporaryURL(ext: "csv", prefix: "Fixed-Asset-Register")
        let header = [
            "Register", "As Of", "Asset Number", "Asset Name", "Category", "Currency",
            "Purchase Date", "Cost", "Residual Value", "Depreciation Method", "Annual Rate %",
            "Useful Life Months", "Accumulated Depreciation", "Net Book Value", "Status",
            "Disposal Date", "Proceeds", "Gain/(Loss)", "Notes"
        ]
        var rows = [header.map(csvEscape).joined(separator: ",")]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for asset in assets {
            let row = [
                title,
                df.string(from: asOfDate),
                asset.assetNumber,
                asset.name,
                asset.category,
                asset.currencyCode,
                df.string(from: asset.purchaseDate),
                number(asset.cost),
                number(asset.residualValue),
                asset.depreciationMethod.title,
                number(asset.annualDepreciationRate),
                String(asset.usefulLifeMonths),
                number(asset.accumulatedDepreciation(asOf: asOfDate)),
                number(asset.netBookValue(asOf: asOfDate)),
                asset.status.title,
                asset.disposalDate.map(df.string) ?? "",
                asset.disposalProceeds.map(number) ?? "",
                asset.disposalGainLoss.map(number) ?? "",
                asset.notes
            ]
            rows.append(row.map(csvEscape).joined(separator: ","))
        }
        let contents = "\u{FEFF}" + rows.joined(separator: "\r\n")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func temporaryURL(ext: String, prefix: String) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(prefix)-\(df.string(from: Date())).\(ext)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    private static func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func short(_ value: String, _ length: Int) -> String {
        if value.count <= length { return value }
        return String(value.prefix(max(1, length - 1))) + "…"
    }
}
