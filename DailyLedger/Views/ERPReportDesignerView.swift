import SwiftUI

struct ERPReportDesignerView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var reports: [ERPReportDefinition] = ERPAccountingEngine.reportDefinitions
    @State private var editingReport: ERPReportDefinition?
    @State private var previewReport: ERPReportDefinition?

    var body: some View {
        List {
            Section {
                ForEach(reports) { report in
                    Button {
                        previewReport = report
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(AppTheme.purple)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(report.name).font(.headline)
                                Text("\(report.lines.count) lines · \(report.currencyCode)\(report.comparative ? " · Comparative" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(report.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            editingReport = report
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(AppTheme.purple)
                    }
                    .contextMenu {
                        Button {
                            editingReport = report
                        } label: {
                            Label("Edit Report", systemImage: "pencil")
                        }
                        Button {
                            duplicate(report)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            delete(report.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("Saved ERP Reports")
            } footer: {
                Text("Each report line can pull from transaction flows, account balances, categories, financial dimensions, loans, receivables, payables, fixed assets or net worth. Values are calculated by the ERP accounting rules and configured exchange rates.")
            }

            Section("Templates") {
                Button {
                    addTemplate("Management Summary")
                } label: {
                    Label("Add Management Summary", systemImage: "chart.bar.doc.horizontal.fill")
                }
                Button {
                    addTemplate("Net Cash Flow")
                } label: {
                    Label("Add Net Cash Flow", systemImage: "arrow.left.arrow.right.square.fill")
                }
                Button {
                    editingReport = ERPReportDefinition(
                        name: "Custom Report",
                        currencyCode: store.currencyCode,
                        lines: []
                    )
                } label: {
                    Label("Create Blank Report", systemImage: "plus.rectangle.on.folder.fill")
                }
            }
        }
        .navigationTitle("Custom Report Designer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    editingReport = ERPReportDefinition(
                        name: "Custom Report",
                        currencyCode: store.currencyCode,
                        lines: []
                    )
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add report")
            }
        }
        .sheet(item: $editingReport) { report in
            NavigationStack {
                ERPReportDefinitionEditor(report: report) { saved in
                    save(saved)
                }
                .environmentObject(store)
            }
        }
        .sheet(item: $previewReport) { report in
            NavigationStack {
                ERPReportPreviewView(report: report)
                    .environmentObject(store)
            }
        }
        .onAppear { reports = ERPAccountingEngine.reportDefinitions }
    }

    private func save(_ report: ERPReportDefinition) {
        if let index = reports.firstIndex(where: { $0.id == report.id }) {
            reports[index] = report
        } else {
            reports.append(report)
        }
        ERPAccountingEngine.reportDefinitions = reports
        editingReport = nil
    }

    private func delete(_ id: UUID) {
        reports.removeAll { $0.id == id }
        ERPAccountingEngine.reportDefinitions = reports
    }

    private func duplicate(_ report: ERPReportDefinition) {
        var copy = report
        copy.id = UUID()
        copy.name = report.name + " Copy"
        copy.lines = report.lines.map { line in
            var lineCopy = line
            lineCopy.id = UUID()
            return lineCopy
        }
        reports.append(copy)
        ERPAccountingEngine.reportDefinitions = reports
    }

    private func move(from source: IndexSet, to destination: Int) {
        reports.move(fromOffsets: source, toOffset: destination)
        ERPAccountingEngine.reportDefinitions = reports
    }

    private func addTemplate(_ name: String) {
        guard let template = ERPAccountingEngine.defaultReportDefinitions.first(where: { $0.name == name }) else { return }
        var report = template
        report.id = UUID()
        report.name = uniqueName(template.name)
        report.currencyCode = store.currencyCode
        report.lines = template.lines.map { line in
            var item = line
            item.id = UUID()
            return item
        }
        reports.append(report)
        ERPAccountingEngine.reportDefinitions = reports
    }

    private func uniqueName(_ base: String) -> String {
        guard reports.contains(where: { $0.name.caseInsensitiveCompare(base) == .orderedSame }) else { return base }
        var index = 2
        while reports.contains(where: { $0.name.caseInsensitiveCompare("\(base) \(index)") == .orderedSame }) {
            index += 1
        }
        return "\(base) \(index)"
    }
}

private struct ERPReportDefinitionEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var report: ERPReportDefinition
    @State private var editingLine: ERPReportLineDefinition?
    let onSave: (ERPReportDefinition) -> Void

    init(report: ERPReportDefinition, onSave: @escaping (ERPReportDefinition) -> Void) {
        _report = State(initialValue: report)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Report") {
                TextField("Report name", text: $report.name)
                Picker("Currency", selection: $report.currencyCode) {
                    ForEach(availableCurrencies, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Show grand total", isOn: $report.showGrandTotal)
                Toggle("Compare previous equal period", isOn: $report.comparative)
            }

            Section {
                if report.lines.isEmpty {
                    Text("No lines yet. Add a line and choose exactly what accounting component it should calculate.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(report.lines) { line in
                    Button {
                        editingLine = line
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.label.isEmpty ? line.component.title : line.label)
                                    .foregroundStyle(.primary)
                                Text(lineSubtitle(line))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(multiplierText(line.multiplier))
                                .font(.caption.bold())
                                .foregroundStyle(line.multiplier < 0 ? AppTheme.red : AppTheme.green)
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteLines)
                .onMove(perform: moveLines)

                Button {
                    editingLine = ERPReportLineDefinition()
                } label: {
                    Label("Add Report Line", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Lines")
                    Spacer()
                    EditButton()
                }
            } footer: {
                Text("Use a negative multiplier for deductions such as expenses or loan repayments. Disable ‘Include in grand total’ for informational balances like Net Worth.")
            }
        }
        .navigationTitle("Report Definition")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let cleaned = report.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    report.name = cleaned.isEmpty ? "Custom Report" : cleaned
                    onSave(report)
                    dismiss()
                }
            }
        }
        .sheet(item: $editingLine) { line in
            NavigationStack {
                ERPReportLineEditor(line: line, currencyCode: report.currencyCode) { saved in
                    if let index = report.lines.firstIndex(where: { $0.id == saved.id }) {
                        report.lines[index] = saved
                    } else {
                        report.lines.append(saved)
                    }
                    editingLine = nil
                }
                .environmentObject(store)
            }
        }
    }

    private var availableCurrencies: [String] {
        Array(Set(store.accounts.map { $0.currencyCode.uppercased() } + [store.currencyCode.uppercased(), "QAR", "PKR", "USD", "EUR", "GBP"])).sorted()
    }

    private func deleteLines(at offsets: IndexSet) {
        report.lines.remove(atOffsets: offsets)
    }

    private func moveLines(from source: IndexSet, to destination: Int) {
        report.lines.move(fromOffsets: source, toOffset: destination)
    }

    private func multiplierText(_ value: Decimal) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        return "×\(text)"
    }

    private func lineSubtitle(_ line: ERPReportLineDefinition) -> String {
        var parts = [line.component.title]
        if !line.categoryContains.isEmpty { parts.append("Category: \(line.categoryContains)") }
        if !line.dimensionName.isEmpty { parts.append("\(line.dimensionName)=\(line.dimensionValue)") }
        if !line.accountIDs.isEmpty { parts.append("\(line.accountIDs.count) accounts") }
        if !line.includeInGrandTotal { parts.append("Info only") }
        return parts.joined(separator: " · ")
    }
}

private struct ERPReportLineEditor: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var line: ERPReportLineDefinition
    @State private var multiplierText: String
    @State private var showingAccounts = false
    let currencyCode: String
    let onSave: (ERPReportLineDefinition) -> Void

    init(line: ERPReportLineDefinition, currencyCode: String, onSave: @escaping (ERPReportLineDefinition) -> Void) {
        _line = State(initialValue: line)
        _multiplierText = State(initialValue: NSDecimalNumber(decimal: line.multiplier).stringValue)
        self.currencyCode = currencyCode
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Line") {
                TextField("Label", text: $line.label)
                Picker("Accounting component", selection: $line.component) {
                    ForEach(ERPReportComponent.allCases) { component in
                        Text(component.title).tag(component)
                    }
                }
                TextField("Multiplier", text: $multiplierText)
                    .keyboardType(.numbersAndPunctuation)
                Toggle("Include in grand total", isOn: $line.includeInGrandTotal)
            }

            if supportsCategoryFilter {
                Section("Category Filter") {
                    TextField("Category contains", text: $line.categoryContains)
                    Text("Leave blank to include all categories for this component.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account Scope") {
                Button {
                    showingAccounts = true
                } label: {
                    HStack {
                        Text("Selected accounts")
                        Spacer()
                        Text(line.accountIDs.isEmpty ? "All" : "\(line.accountIDs.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Clear Account Filter") { line.accountIDs.removeAll() }
                    .disabled(line.accountIDs.isEmpty)
            }

            Section("Financial Dimension Filter") {
                Picker("Dimension", selection: $line.dimensionName) {
                    Text("None").tag("")
                    ForEach(ERPAccountingEngine.dimensionDefinitions.filter(\.enabled)) { definition in
                        Text(definition.name).tag(definition.name)
                    }
                }
                if !line.dimensionName.isEmpty {
                    if let definition = selectedDimension, !definition.values.isEmpty {
                        Picker("Value", selection: $line.dimensionValue) {
                            Text("Any").tag("")
                            ForEach(definition.values, id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        TextField("Dimension value", text: $line.dimensionValue)
                    }
                }
            }

            Section("Result") {
                LabeledContent("Report currency", value: currencyCode)
                Text(componentExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Report Line")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    line.multiplier = Decimal(string: multiplierText.replacingOccurrences(of: ",", with: ".")) ?? 1
                    if line.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        line.label = line.component.title
                    }
                    onSave(line)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showingAccounts) {
            NavigationStack {
                ERPReportAccountPicker(selectedIDs: $line.accountIDs)
                    .environmentObject(store)
            }
        }
        .onChange(of: line.dimensionName) { _ in
            line.dimensionValue = ""
        }
    }

    private var selectedDimension: ERPDimensionDefinition? {
        ERPAccountingEngine.dimensionDefinitions.first { $0.name == line.dimensionName }
    }

    private var supportsCategoryFilter: Bool {
        switch line.component {
        case .categoryIncome, .categoryExpense, .directIncome, .directExpenses, .allReportIncome, .allReportExpenses:
            return true
        default:
            return false
        }
    }

    private var componentExplanation: String {
        switch line.component {
        case .directIncome: return "Explicit income postings only, subject to Financial Summary ERP rules."
        case .refunds: return "Refund/reversal income linked to an original transaction."
        case .allReportIncome: return "All transactions treated as income by the configured ERP report rules."
        case .directExpenses: return "Explicit expense postings only."
        case .allReportExpenses: return "All transactions treated as expense by the configured ERP report rules."
        case .loanIncreases: return "Loan or fixed-liability funding recognized by the ERP loan-detection rules."
        case .loanPayments: return "Bank-to-loan/fixed-liability repayments."
        case .receivableCollections: return "Collections from receivable/payment accounts into bank accounts."
        case .bankBalances: return "Closing balances of accounts with Bank nature."
        case .assetBalances: return "Closing balances of accounts with Asset nature."
        case .receivableBalances: return "Closing balances of Receivable accounts."
        case .payableBalances: return "Closing balances of Payable accounts."
        case .loanBalances: return "Closing balances of Loan accounts."
        case .fixedAssetBalances: return "Closing balances of Fixed Asset ledger accounts."
        case .fixedLiabilityBalances: return "Closing balances of Fixed Liability ledger accounts."
        case .selectedAccountBalances: return "Closing balances of the accounts selected on this line."
        case .categoryIncome: return "ERP report income filtered by category text."
        case .categoryExpense: return "ERP report expense filtered by category text."
        case .netCashFlow: return "All ERP report income minus all ERP report expenses in the period."
        case .netWorth: return "Net worth calculated from the configured balance-nature and register rules."
        }
    }
}

private struct ERPReportAccountPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIDs: [UUID]
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Button("Select All") { selectedIDs = visibleAccounts.map(\.id) }
                Button("Clear All") { selectedIDs.removeAll() }
            }
            ForEach(visibleAccounts) { account in
                Button {
                    toggle(account.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name).foregroundStyle(.primary)
                            Text([account.chartCode, account.nature?.title, account.currencyCode].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedIDs.contains(account.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIDs.contains(account.id) ? AppTheme.purple : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Report Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search accounts")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var visibleAccounts: [LedgerAccount] {
        store.accounts.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || ($0.chartCode?.localizedCaseInsensitiveContains(searchText) ?? false)
        }.sorted {
            let left = $0.chartCode ?? "9999"
            let right = $1.chartCode ?? "9999"
            return left == right ? $0.name < $1.name : left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selectedIDs.firstIndex(of: id) { selectedIDs.remove(at: index) }
        else { selectedIDs.append(id) }
    }
}

struct ERPReportPreviewView: View {
    @EnvironmentObject private var store: LedgerStore
    let report: ERPReportDefinition
    @State private var startDate = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var endDate = Date()

    var body: some View {
        List {
            Section("Period") {
                DatePicker("From", selection: $startDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
            }

            Section {
                if visibleLines.isEmpty {
                    Text("No non-zero report lines for this period.")
                        .foregroundStyle(.secondary)
                }
                ForEach(visibleLines, id: \.line.id) { item in
                    NavigationLink {
                        ERPReportLineDrilldownView(
                            report: report,
                            line: item.line,
                            interval: interval
                        )
                        .environmentObject(store)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.line.label)
                                Text(item.line.component.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(DisplayFormat.currency(item.value, code: report.currencyCode))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(item.value < 0 ? AppTheme.red : AppTheme.green)
                                if report.comparative {
                                    Text("Prev " + DisplayFormat.currency(item.previous, code: report.currencyCode))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if report.showGrandTotal {
                    Divider()
                    HStack {
                        Text("Grand Total").font(.headline)
                        Spacer()
                        Text(DisplayFormat.currency(grandTotal, code: report.currencyCode))
                            .font(.headline)
                    }
                    if report.comparative {
                        HStack {
                            Text("Previous Period").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(DisplayFormat.currency(previousGrandTotal, code: report.currencyCode))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(report.name)
            } footer: {
                Text("Report formulas use your ERP accounting rules, account natures, custom currency rates and financial-dimension filters.")
            }
        }
        .navigationTitle(report.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var interval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay)
    }

    private var previousInterval: DateInterval {
        let duration = interval.duration
        return DateInterval(start: interval.start.addingTimeInterval(-duration), end: interval.start)
    }

    private var rows: [(line: ERPReportLineDefinition, value: Decimal, previous: Decimal)] {
        report.lines.map { line in
            let value = store.erpReportLineValue(line, interval: interval, currencyCode: report.currencyCode)
            let previous = report.comparative
                ? store.erpReportLineValue(line, interval: previousInterval, currencyCode: report.currencyCode)
                : 0
            return (line, value, previous)
        }
    }

    private var visibleLines: [(line: ERPReportLineDefinition, value: Decimal, previous: Decimal)] {
        let includeZero = ERPStorage.bool(ERPKey.reportIncludeZeroLines, true)
        return includeZero ? rows : rows.filter { $0.value != 0 || (report.comparative && $0.previous != 0) }
    }

    private var grandTotal: Decimal {
        rows.filter { $0.line.includeInGrandTotal }.reduce(0) { $0 + $1.value }
    }

    private var previousGrandTotal: Decimal {
        rows.filter { $0.line.includeInGrandTotal }.reduce(0) { $0 + $1.previous }
    }
}

private struct ERPReportLineDrilldownView: View {
    @EnvironmentObject private var store: LedgerStore
    let report: ERPReportDefinition
    let line: ERPReportLineDefinition
    let interval: DateInterval

    var body: some View {
        List {
            Section("Formula") {
                LabeledContent("Component", value: line.component.title)
                LabeledContent("Multiplier", value: NSDecimalNumber(decimal: line.multiplier).stringValue)
                LabeledContent("Currency", value: report.currencyCode)
                if !line.categoryContains.isEmpty { LabeledContent("Category", value: line.categoryContains) }
                if !line.dimensionName.isEmpty { LabeledContent("Dimension", value: "\(line.dimensionName) = \(line.dimensionValue.isEmpty ? "Any" : line.dimensionValue)") }
                LabeledContent("Calculated Value", value: DisplayFormat.currency(store.erpReportLineValue(line, interval: interval, currencyCode: report.currencyCode), code: report.currencyCode))
            }

            if transactionComponent {
                Section("Matching Transactions") {
                    ForEach(matchingTransactions) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
            }

            if balanceComponent {
                Section("Matching Accounts") {
                    ForEach(matchingAccounts) { account in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text([account.chartCode, account.nature?.title, account.currencyCode].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let value = store.erpConvertedBalance(for: account, before: interval.end, to: report.currencyCode) {
                                Text(DisplayFormat.currency(value, code: report.currencyCode)).font(.caption.bold())
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(line.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var transactionComponent: Bool {
        switch line.component {
        case .directIncome, .refunds, .allReportIncome, .directExpenses, .allReportExpenses, .loanIncreases, .loanPayments, .receivableCollections, .categoryIncome, .categoryExpense, .netCashFlow:
            return true
        default: return false
        }
    }

    private var balanceComponent: Bool { !transactionComponent && line.component != .netWorth }

    private var matchingTransactions: [LedgerTransaction] {
        let ids = Set(line.accountIDs)
        let category = line.categoryContains.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.transactions.filter { transaction in
            guard interval.contains(transaction.date), store.erpTransactionMatchesDimensions(transaction, line: line) else { return false }
            if !ids.isEmpty {
                let relevant = [transaction.accountID, transaction.destinationAccountID].compactMap { $0 }
                guard relevant.contains(where: ids.contains) else { return false }
            }
            if !category.isEmpty && !transaction.category.localizedCaseInsensitiveContains(category) { return false }
            switch line.component {
            case .directIncome: return store.isFinancialSummaryDirectIncome(transaction)
            case .refunds: return store.isFinancialSummaryRefund(transaction)
            case .allReportIncome, .categoryIncome: return store.isReportIncome(transaction)
            case .directExpenses: return store.isFinancialSummaryDirectExpense(transaction)
            case .allReportExpenses, .categoryExpense: return store.isReportExpense(transaction)
            case .loanIncreases: return store.financialSummaryLoanIncreaseAmount(transaction) > 0
            case .loanPayments: return store.financialSummaryLoanPaidAmount(transaction) > 0
            case .receivableCollections: return store.receivableCollectionAmount(transaction) > 0
            case .netCashFlow: return store.isReportIncome(transaction) || store.isReportExpense(transaction)
            default: return false
            }
        }.sorted { $0.date > $1.date }
    }

    private var matchingAccounts: [LedgerAccount] {
        let ids = Set(line.accountIDs)
        return store.accounts.filter { account in
            if !ids.isEmpty && !ids.contains(account.id) { return false }
            switch line.component {
            case .bankBalances: return account.nature == .bank
            case .assetBalances: return account.nature == .asset
            case .receivableBalances: return account.nature == .receivable
            case .payableBalances: return account.nature == .payable
            case .loanBalances: return account.nature == .loan
            case .fixedAssetBalances: return account.nature == .fixedAsset
            case .fixedLiabilityBalances: return account.nature == .fixedLiability
            case .selectedAccountBalances: return true
            default: return false
            }
        }.sorted { ($0.chartCode ?? "9999") < ($1.chartCode ?? "9999") }
    }
}
