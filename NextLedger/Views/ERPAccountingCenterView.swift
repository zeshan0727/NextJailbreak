import SwiftUI
import UIKit

struct ERPAccountingCenterView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage(ERPKey.enabled) private var enabled = true
    @State private var preset = ERPStorage.string(ERPKey.preset, "Preserve Current Logic")

    private let presets = ["Preserve Current Logic", "Accrual Accounting", "Cash Management", "Strict Posting", "Personal Finance"]

    var body: some View {
        List {
            Section {
                Toggle("Enable ERP Accounting Engine", isOn: $enabled)
                Picker("Accounting Preset", selection: $preset) {
                    ForEach(presets, id: \.self) { Text($0).tag($0) }
                }
                Button {
                    ERPAccountingEngine.applyPreset(preset)
                    store.reload()
                } label: {
                    Label("Apply Preset", systemImage: "wand.and.stars")
                }
            } header: {
                Text("Engine")
            } footer: {
                Text("These settings change calculations, posting validation, balances, exchange-rate conversion and reports. Developer Lab remains the separate visual-customization area.")
            }

            Section("Core Accounting") {
                NavigationLink { ERPPostingSettingsView() } label: {
                    ERPAccountingCenterRow(title: "General Ledger & Posting", subtitle: "Required fields, dates, duplicates, negative balances, amount precision", icon: "books.vertical.fill")
                }
                NavigationLink { ERPCurrencySettingsView() } label: {
                    ERPAccountingCenterRow(title: "Currencies & Exchange Rates", subtitle: "Manual dated rates, inverse/cross rates, QAR/PKR/USD defaults, rounding", icon: "coloncurrencysign.circle.fill")
                }
                NavigationLink { ERPSummarySettingsView() } label: {
                    ERPAccountingCenterRow(title: "Financial Summary & Balances", subtitle: "Choose formula components, opening-balance source, net-worth mode and accounts", icon: "sum")
                }
                NavigationLink { ERPReportSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Report Accounting Rules", subtitle: "Transfer treatment, refunds, receivables/payables, tax basis and signs", icon: "doc.text.magnifyingglass")
                }
            }

            Section("ERP Reporting") {
                NavigationLink { ERPReportDesignerView() } label: {
                    ERPAccountingCenterRow(title: "Custom Report Designer", subtitle: "Build saved reports line-by-line from accounts, categories, balances and cash flows", icon: "slider.horizontal.3")
                }
                NavigationLink { ERPTaxSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Tax / VAT Rules & Report", subtitle: "Category tax rules, inclusive/exclusive treatment and recoverable input tax", icon: "percent")
                }
                NavigationLink { ERPDimensionSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Financial Dimensions", subtitle: "Cost center, department, project, location or any custom dimension", icon: "square.grid.3x3.fill")
                }
            }

            Section("Subledgers & Controls") {
                NavigationLink { ERPLoanReceivablePayableSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Loans / Receivables / Payables", subtitle: "Account detection and settlement treatment in cash-flow reports", icon: "banknote.fill")
                }
                NavigationLink { ERPBudgetEngineSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Budget Engine", subtitle: "Alert threshold, history window, suggested-budget factors and rounding", icon: "target")
                }
                NavigationLink { ERPFixedAssetEngineSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Fixed Assets & Liabilities", subtitle: "Default depreciation rules and net-worth inclusion", icon: "building.2.fill")
                }
                NavigationLink { ERPFiscalAndAuditSettingsView() } label: {
                    ERPAccountingCenterRow(title: "Fiscal Year & Audit Controls", subtitle: "Fiscal year, comparative periods, posting locks and audit behavior", icon: "checkmark.shield.fill")
                }
            }

            Section("Configuration") {
                NavigationLink { ERPSummaryBalanceAccountPicker() } label: {
                    ERPAccountingCenterRow(title: "ERP Balance Account Selection", subtitle: "Accounts used by selected-closing and ERP opening-balance modes", icon: "checklist.checked")
                }
                NavigationLink { ERPConfigurationBackupView() } label: {
                    ERPAccountingCenterRow(title: "Copy / Import ERP Configuration", subtitle: "Move all ERP rules between builds or send the configuration for review", icon: "curlybraces.square")
                }
                Button(role: .destructive) {
                    ERPAccountingEngine.resetAll()
                    enabled = true
                    preset = "Preserve Current Logic"
                    store.reload()
                } label: {
                    Label("Reset ERP Rules to Safe Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("ERP / Accounting Center")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.reload() }
    }
}

private struct ERPAccountingCenterRow: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(AppTheme.purple)
        }
        .padding(.vertical, 4)
    }
}

struct ERPPostingSettingsView: View {
    @AppStorage(ERPKey.postingRoundAmounts) private var roundAmounts = false
    @AppStorage(ERPKey.postingAmountDecimals) private var amountDecimals = 2
    @AppStorage(ERPKey.postingRequireAccount) private var requireAccount = true
    @AppStorage(ERPKey.postingRequireCategory) private var requireCategory = true
    @AppStorage(ERPKey.postingRequireDescription) private var requireDescription = false
    @AppStorage(ERPKey.postingRequireExpenseVendor) private var requireExpenseVendor = false
    @AppStorage(ERPKey.postingRequireIncomeVendor) private var requireIncomeVendor = false
    @AppStorage(ERPKey.postingBlockZero) private var blockZero = true
    @AppStorage(ERPKey.postingMaxFutureDays) private var maxFutureDays = 3650
    @AppStorage(ERPKey.postingMaxBackdateDays) private var maxBackdateDays = 0
    @AppStorage(ERPKey.postingBlockDuplicates) private var blockDuplicates = false
    @AppStorage(ERPKey.postingDuplicateWindowMinutes) private var duplicateMinutes = 10
    @AppStorage(ERPKey.postingBlockNegativeBankBalance) private var blockNegativeBank = false
    @AppStorage(ERPKey.postingNegativeBankFloor) private var bankFloor = 0.0
    @AppStorage(ERPKey.postingBlockHighValue) private var blockHighValue = false
    @AppStorage(ERPKey.postingHighValueThreshold) private var highValueThreshold = 100000.0
    @AppStorage(ERPKey.postingBlockArchivedAccount) private var blockArchived = true
    @AppStorage(ERPKey.postingRequireConfiguredDimensions) private var requireDimensions = true
    @AppStorage(ERPKey.transferRequireDescription) private var requireTransferDescription = false
    @AppStorage(ERPKey.transferForceSameCurrencyParity) private var sameCurrencyParity = true
    @AppStorage(ERPKey.transferUseConfiguredRate) private var transferConfiguredRate = true

    var body: some View {
        Form {
            Section("Required Posting Data") {
                Toggle("Require account", isOn: $requireAccount)
                Toggle("Require category", isOn: $requireCategory)
                Toggle("Require description", isOn: $requireDescription)
                Toggle("Require vendor on expenses", isOn: $requireExpenseVendor)
                Toggle("Require source/vendor on income", isOn: $requireIncomeVendor)
                Toggle("Enforce required dimensions", isOn: $requireDimensions)
                Toggle("Block archived accounts", isOn: $blockArchived)
            }
            Section("Amounts") {
                Toggle("Block zero / negative amount", isOn: $blockZero)
                Toggle("Round amount before posting", isOn: $roundAmounts)
                if roundAmounts { Stepper("Posted amount decimals: \(amountDecimals)", value: $amountDecimals, in: 0...6) }
                Toggle("Block high-value transactions", isOn: $blockHighValue)
                if blockHighValue {
                    HStack { Text("Threshold"); Spacer(); TextField("100000", value: $highValueThreshold, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
            }
            Section("Date Controls") {
                Stepper("Maximum future days: \(maxFutureDays)", value: $maxFutureDays, in: 0...3650)
                Stepper("Maximum backdate days: \(maxBackdateDays == 0 ? "Unlimited" : String(maxBackdateDays))", value: $maxBackdateDays, in: 0...3650)
            }
            Section("Duplicate & Balance Controls") {
                Toggle("Block possible duplicates", isOn: $blockDuplicates)
                if blockDuplicates { Stepper("Duplicate window: \(duplicateMinutes) min", value: $duplicateMinutes, in: 1...1440) }
                Toggle("Block bank balance below floor", isOn: $blockNegativeBank)
                if blockNegativeBank {
                    HStack { Text("Minimum bank balance"); Spacer(); TextField("0", value: $bankFloor, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                }
            }
            Section("Transfer Controls") {
                Toggle("Require transfer description", isOn: $requireTransferDescription)
                Toggle("Same-currency amounts must match", isOn: $sameCurrencyParity)
                Toggle("Use configured FX rate in Transfer screen", isOn: $transferConfiguredRate)
            }
        }
        .navigationTitle("GL & Posting")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPSummarySettingsView: View {
    @AppStorage(ERPKey.summaryIncludeDirectIncome) private var directIncome = true
    @AppStorage(ERPKey.summaryIncludeRefunds) private var refunds = true
    @AppStorage(ERPKey.summaryIncludeDirectExpense) private var directExpense = true
    @AppStorage(ERPKey.summaryIncludeLoanIncrease) private var loanIncrease = true
    @AppStorage(ERPKey.summaryIncludeLoanPaid) private var loanPaid = true
    @AppStorage(ERPKey.summaryIncludeReceivableCollections) private var receivableCollections = false
    @AppStorage(ERPKey.summaryIncludeAssetToBank) private var assetToBank = false
    @AppStorage(ERPKey.summaryIncludeBankToAsset) private var bankToAsset = false
    @AppStorage(ERPKey.summaryDirectIncomeBankOnly) private var incomeBankOnly = false
    @AppStorage(ERPKey.summaryDirectExpenseBankOnly) private var expenseBankOnly = false
    @AppStorage(ERPKey.summaryIncludeOpeningBalance) private var includeOpening = true
    @AppStorage(ERPKey.summaryOpeningSource) private var openingSource = ERPSummaryOpeningSource.existingSelection.rawValue
    @AppStorage(ERPKey.summaryNetMode) private var netMode = ERPSummaryNetMode.flowPlusOpening.rawValue
    @AppStorage(ERPKey.summaryNetIncludeBank) private var includeBank = true
    @AppStorage(ERPKey.summaryNetIncludeAsset) private var includeAsset = true
    @AppStorage(ERPKey.summaryNetIncludeReceivable) private var includeReceivable = true
    @AppStorage(ERPKey.summaryNetIncludeControl) private var includeControl = false
    @AppStorage(ERPKey.summaryNetIncludeFixedAsset) private var includeFixedAsset = true
    @AppStorage(ERPKey.summaryNetIncludeLoan) private var includeLoan = true
    @AppStorage(ERPKey.summaryNetIncludePayable) private var includePayable = true
    @AppStorage(ERPKey.summaryNetIncludeFixedLiability) private var includeFixedLiability = true
    @AppStorage(ERPKey.summaryIncludeUnlinkedFixedAssetRegister) private var unlinkedAssets = false
    @AppStorage(ERPKey.summaryIncludeUnlinkedFixedLiabilityRegister) private var unlinkedLiabilities = false

    var body: some View {
        Form {
            Section("Money In") {
                Toggle("Direct income", isOn: $directIncome)
                Toggle("Refunds", isOn: $refunds)
                Toggle("Loan increases / drawdowns", isOn: $loanIncrease)
                Toggle("Receivable collections", isOn: $receivableCollections)
                Toggle("Asset / non-bank → Bank as money in", isOn: $assetToBank)
                Toggle("Direct income must hit Bank nature", isOn: $incomeBankOnly)
            }
            Section("Money Out") {
                Toggle("Direct expenses", isOn: $directExpense)
                Toggle("Loan repayments", isOn: $loanPaid)
                Toggle("Bank → Asset as money out", isOn: $bankToAsset)
                Toggle("Direct expenses must use Bank nature", isOn: $expenseBankOnly)
            }
            Section("Net Balance Formula") {
                Picker("Net balance mode", selection: $netMode) {
                    ForEach(ERPSummaryNetMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Include opening balance", isOn: $includeOpening)
                if includeOpening {
                    Picker("Opening balance source", selection: $openingSource) {
                        ForEach(ERPSummaryOpeningSource.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    }
                }
                NavigationLink("Select ERP balance accounts") { ERPSummaryBalanceAccountPicker() }
            }
            Section("Net Worth Account Natures") {
                Toggle("Bank", isOn: $includeBank)
                Toggle("Asset", isOn: $includeAsset)
                Toggle("Receivable", isOn: $includeReceivable)
                Toggle("Control", isOn: $includeControl)
                Toggle("Fixed Asset", isOn: $includeFixedAsset)
                Toggle("Loan", isOn: $includeLoan)
                Toggle("Payable", isOn: $includePayable)
                Toggle("Fixed Liability", isOn: $includeFixedLiability)
                Toggle("Add unlinked Fixed Asset Register NBV", isOn: $unlinkedAssets)
                Toggle("Subtract unlinked Fixed Liability Register", isOn: $unlinkedLiabilities)
            }
        }
        .navigationTitle("Summary & Balances")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPReportSettingsView: View {
    @AppStorage(ERPKey.reportRefundsAsIncome) private var refundsAsIncome = true
    @AppStorage(ERPKey.reportReceivableCollectionsAsIncome) private var receivableAsIncome = true
    @AppStorage(ERPKey.reportNonBankToBankAsIncome) private var nonBankToBank = true
    @AppStorage(ERPKey.reportPayableFundingAsIncome) private var payableFunding = false
    @AppStorage(ERPKey.reportBankToNonBankAsExpense) private var bankToNonBank = true
    @AppStorage(ERPKey.reportBankToAssetAsExpense) private var bankToAsset = true
    @AppStorage(ERPKey.reportBankToReceivableAsExpense) private var bankToReceivable = true
    @AppStorage(ERPKey.reportBankToPayableAsExpense) private var bankToPayable = true
    @AppStorage(ERPKey.reportExcludeLoanTransfers) private var excludeLoans = true
    @AppStorage(ERPKey.reportExcludeBankToBankTransfers) private var excludeBankTransfers = true
    @AppStorage(ERPKey.reportUseNetOfTax) private var netOfTax = false
    @AppStorage(ERPKey.reportIncludeArchivedAccounts) private var archived = true
    @AppStorage(ERPKey.reportIncludeSubaccounts) private var subaccounts = true
    @AppStorage(ERPKey.reportIncludeZeroLines) private var zeroLines = false
    @AppStorage(ERPKey.reportBalanceSignMode) private var signMode = ERPBalanceSignMode.raw.rawValue
    @AppStorage(ERPKey.reportAmountDecimals) private var decimals = 2
    @AppStorage(ERPKey.reportRoundingMode) private var rounding = ERPRoundingMode.plain.rawValue

    var body: some View {
        Form {
            Section("Income Classification") {
                Toggle("Refunds appear in income reports", isOn: $refundsAsIncome)
                Toggle("Receivable collections appear as income", isOn: $receivableAsIncome)
                Toggle("Non-bank → Bank may be income", isOn: $nonBankToBank)
                Toggle("Payable → Bank may be income", isOn: $payableFunding)
            }
            Section("Expense Classification") {
                Toggle("Bank → Non-bank may be expense", isOn: $bankToNonBank)
                Toggle("Bank → Asset may be expense", isOn: $bankToAsset)
                Toggle("Bank → Receivable may be expense", isOn: $bankToReceivable)
                Toggle("Bank → Payable may be expense", isOn: $bankToPayable)
                Toggle("Exclude loan/fixed-liability transfers", isOn: $excludeLoans)
                Toggle("Exclude Bank ↔ Bank internal transfers", isOn: $excludeBankTransfers)
            }
            Section("Amount Presentation") {
                Toggle("Use net-of-tax amount in ERP reports", isOn: $netOfTax)
                Stepper("Report decimals: \(decimals)", value: $decimals, in: 0...6)
                Picker("Rounding", selection: $rounding) {
                    ForEach(ERPRoundingMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Picker("Balance sign", selection: $signMode) {
                    ForEach(ERPBalanceSignMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            }
            Section("Scope") {
                Toggle("Include archived account activity", isOn: $archived)
                Toggle("Include sub-accounts", isOn: $subaccounts)
                Toggle("Show zero-value lines in custom reports", isOn: $zeroLines)
            }
        }
        .navigationTitle("Report Rules")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPLoanReceivablePayableSettingsView: View {
    @AppStorage(ERPKey.loanDetectionMode) private var loanMode = ERPLoanDetectionMode.hybrid.rawValue
    @AppStorage(ERPKey.paymentPositiveActsReceivable) private var positiveReceivable = true
    @AppStorage(ERPKey.paymentNegativeActsLoan) private var negativeLoan = true
    @AppStorage(ERPKey.reportReceivableCollectionsAsIncome) private var collectionsIncome = true
    @AppStorage(ERPKey.reportPayableFundingAsIncome) private var payableFunding = false

    var body: some View {
        Form {
            Section("Loan Detection") {
                Picker("Loan account detection", selection: $loanMode) {
                    ForEach(ERPLoanDetectionMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Positive Payments balance acts as Receivable", isOn: $positiveReceivable)
                Toggle("Negative Payments balance acts as Loan", isOn: $negativeLoan)
            }
            Section("Cash-flow Treatment") {
                Toggle("Receivable collection counts as income", isOn: $collectionsIncome)
                Toggle("Payable funding counts as income", isOn: $payableFunding)
            }
            Section {
                Text("Use Account Nature in Chart of Accounts to classify dedicated Receivable, Payable, Loan and Fixed Liability accounts. These rules control how their transfers enter reports without changing the underlying bank balances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Loans / R&P")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPBudgetEngineSettingsView: View {
    @AppStorage(ERPKey.budgetAlertPercent) private var alertPercent = 80
    @AppStorage(ERPKey.budgetHistoryMonths) private var historyMonths = 3
    @AppStorage(ERPKey.budgetHistoricalFactorPercent) private var historyFactor = 90
    @AppStorage(ERPKey.budgetIncomeAllocationPercent) private var incomeFactor = 80
    @AppStorage(ERPKey.budgetRoundingDecimals) private var roundingDecimals = 0

    var body: some View {
        Form {
            Section("Consumption Alert") {
                Stepper("Alert at \(alertPercent)%", value: $alertPercent, in: 1...100)
            }
            Section("Budget Suggestions") {
                Stepper("History window: \(historyMonths) months", value: $historyMonths, in: 1...24)
                Stepper("Historical target: \(historyFactor)%", value: $historyFactor, in: 1...200)
                Stepper("Income allocation fallback: \(incomeFactor)%", value: $incomeFactor, in: 1...100)
                Stepper("Round suggestions to \(roundingDecimals) decimals", value: $roundingDecimals, in: 0...2)
            }
        }
        .navigationTitle("Budget Engine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPFixedAssetEngineSettingsView: View {
    @AppStorage(ERPKey.fixedAssetDefaultRate) private var defaultRate = 15.0
    @AppStorage(ERPKey.fixedAssetDefaultLifeMonths) private var lifeMonths = 60
    @AppStorage(ERPKey.fixedAssetDefaultResidualPercent) private var residualPercent = 0.0
    @AppStorage(ERPKey.fixedAssetDepreciationConvention) private var convention = ERPDepreciationConvention.fullMonth.rawValue
    @AppStorage(ERPKey.fixedAssetDepreciationDecimals) private var decimals = 2
    @AppStorage(ERPKey.summaryIncludeUnlinkedFixedAssetRegister) private var includeUnlinkedAssets = false
    @AppStorage(ERPKey.summaryIncludeUnlinkedFixedLiabilityRegister) private var includeUnlinkedLiabilities = false

    var body: some View {
        Form {
            Section("New Fixed Asset Defaults") {
                HStack { Text("Annual depreciation %"); Spacer(); TextField("15", value: $defaultRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Stepper("Useful life: \(lifeMonths) months", value: $lifeMonths, in: 1...600)
                HStack { Text("Residual value %"); Spacer(); TextField("0", value: $residualPercent, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("Depreciation convention", selection: $convention) {
                    ForEach(ERPDepreciationConvention.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Stepper("Depreciation decimals: \(decimals)", value: $decimals, in: 0...6)
            }
            Section("Net Worth") {
                Toggle("Include unlinked Fixed Asset Register NBV", isOn: $includeUnlinkedAssets)
                Toggle("Include unlinked Fixed Liability Register outstanding", isOn: $includeUnlinkedLiabilities)
            }
        }
        .navigationTitle("Fixed Assets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPFiscalAndAuditSettingsView: View {
    @AppStorage(ERPKey.fiscalYearStartMonth) private var fiscalMonth = 1
    @AppStorage(ERPKey.defaultComparisonPeriods) private var comparisonPeriods = 1
    @AppStorage("AccountingPeriodStartDay") private var periodStartDay = 26
    @AppStorage("AccountingPeriodLockEnabled") private var lockEnabled = false
    @AppStorage("AccountingPeriodLockThroughTimestamp") private var lockTimestamp = 0.0

    private let monthNames = Calendar.current.monthSymbols

    var body: some View {
        Form {
            Section("Fiscal Calendar") {
                Picker("Fiscal year starts", selection: $fiscalMonth) {
                    ForEach(1...12, id: \.self) { month in Text(monthNames[month - 1]).tag(month) }
                }
                Stepper("Management period start day: \(periodStartDay)", value: $periodStartDay, in: 1...28)
                Stepper("Default comparative periods: \(comparisonPeriods)", value: $comparisonPeriods, in: 0...12)
            }
            Section("Accounting Lock") {
                Toggle("Enable period lock", isOn: $lockEnabled)
                if lockEnabled {
                    DatePicker("Lock through", selection: Binding(
                        get: { lockTimestamp > 0 ? Date(timeIntervalSince1970: lockTimestamp) : Date() },
                        set: { lockTimestamp = Calendar.current.startOfDay(for: $0).timeIntervalSince1970 }
                    ), displayedComponents: .date)
                }
            }
        }
        .navigationTitle("Fiscal & Audit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ERPSummaryBalanceAccountPicker: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage(ERPKey.summaryBalanceAccountIDsJSON) private var storedIDs = "[]"

    private var selected: Set<UUID> {
        Set(ERPStorage.decode([UUID].self, key: ERPKey.summaryBalanceAccountIDsJSON, fallback: []))
    }

    var body: some View {
        List {
            Section {
                Button("Select All Active") { save(Set(store.activeAccounts.map(\.id))) }
                Button("Select Bank Accounts") { save(Set(store.activeAccounts.filter { $0.nature == .bank }.map(\.id))) }
                Button("Clear Selection") { save([]) }
            }
            Section("Accounts") {
                ForEach(store.accounts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { account in
                    Button {
                        var values = selected
                        if values.contains(account.id) { values.remove(account.id) } else { values.insert(account.id) }
                        save(values)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(account.name).foregroundStyle(.primary)
                                Text("\(account.currencyCode) · \(account.nature?.title ?? "Unassigned")\(account.isArchived ? " · Archived" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selected.contains(account.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(account.id) ? AppTheme.purple : .secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("ERP Balance Accounts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save(_ values: Set<UUID>) {
        ERPStorage.encode(Array(values).sorted { $0.uuidString < $1.uuidString }, key: ERPKey.summaryBalanceAccountIDsJSON)
        storedIDs = ERPStorage.string(ERPKey.summaryBalanceAccountIDsJSON, "[]")
    }
}

struct ERPConfigurationBackupView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var text = ERPAccountingEngine.exportConfiguration()
    @State private var status = ""

    var body: some View {
        Form {
            Section("Configuration JSON") {
                TextEditor(text: $text)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 280)
            }
            Section {
                Button { text = ERPAccountingEngine.exportConfiguration(); UIPasteboard.general.string = text; status = "Copied" } label: {
                    Label("Copy Current ERP Configuration", systemImage: "doc.on.doc")
                }
                Button {
                    if let clipboard = UIPasteboard.general.string { text = clipboard }
                } label: { Label("Paste Configuration", systemImage: "doc.on.clipboard") }
                Button {
                    if ERPAccountingEngine.importConfiguration(text) {
                        store.reload(); status = "Imported successfully"
                    } else { status = "Invalid configuration JSON" }
                } label: { Label("Import & Apply", systemImage: "square.and.arrow.down") }
                if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("ERP Configuration")
        .navigationBarTitleDisplayMode(.inline)
    }
}
