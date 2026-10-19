import Foundation

enum ERPKey {
    static let enabled = "NLERPEnabled"
    static let preset = "NLERPPreset"

    static let rateSource = "NLERPRateSource"
    static let rateAllowInverse = "NLERPRateAllowInverse"
    static let rateAllowTriangulation = "NLERPRateAllowTriangulation"
    static let ratePivotCurrency = "NLERPRatePivotCurrency"
    static let rateMissingPolicy = "NLERPRateMissingPolicy"
    static let legacyQARPKR = "NLERPLegacyQARPKR"
    static let legacyUSDQAR = "NLERPLegacyUSDQAR"
    static let reportAmountDecimals = "NLERPReportAmountDecimals"
    static let reportRateDecimals = "NLERPReportRateDecimals"
    static let reportRoundingMode = "NLERPReportRoundingMode"
    static let useTransactionDateForRates = "NLERPUseTransactionDateForRates"
    static let currencyRatesJSON = "NLERPCurrencyRatesJSONV1"

    static let postingRoundAmounts = "NLERPPostingRoundAmounts"
    static let postingAmountDecimals = "NLERPPostingAmountDecimals"
    static let postingRequireAccount = "NLERPPostingRequireAccount"
    static let postingRequireCategory = "NLERPPostingRequireCategory"
    static let postingRequireDescription = "NLERPPostingRequireDescription"
    static let postingRequireExpenseVendor = "NLERPPostingRequireExpenseVendor"
    static let postingRequireIncomeVendor = "NLERPPostingRequireIncomeVendor"
    static let postingBlockZero = "NLERPPostingBlockZero"
    static let postingMaxFutureDays = "NLERPPostingMaxFutureDays"
    static let postingMaxBackdateDays = "NLERPPostingMaxBackdateDays"
    static let postingBlockDuplicates = "NLERPPostingBlockDuplicates"
    static let postingDuplicateWindowMinutes = "NLERPPostingDuplicateWindowMinutes"
    static let postingBlockNegativeBankBalance = "NLERPPostingBlockNegativeBankBalance"
    static let postingNegativeBankFloor = "NLERPPostingNegativeBankFloor"
    static let postingBlockHighValue = "NLERPPostingBlockHighValue"
    static let postingHighValueThreshold = "NLERPPostingHighValueThreshold"
    static let postingBlockArchivedAccount = "NLERPPostingBlockArchivedAccount"
    static let postingRequireConfiguredDimensions = "NLERPPostingRequireConfiguredDimensions"
    static let transferRequireDescription = "NLERPTransferRequireDescription"
    static let transferForceSameCurrencyParity = "NLERPTransferForceSameCurrencyParity"
    static let transferUseConfiguredRate = "NLERPTransferUseConfiguredRate"

    static let reportRefundsAsIncome = "NLERPReportRefundsAsIncome"
    static let reportReceivableCollectionsAsIncome = "NLERPReportReceivableCollectionsAsIncome"
    static let reportPaymentPositiveAsReceivable = "NLERPReportPaymentPositiveAsReceivable"
    static let reportNonBankToBankAsIncome = "NLERPReportNonBankToBankAsIncome"
    static let reportPayableFundingAsIncome = "NLERPReportPayableFundingAsIncome"
    static let reportBankToNonBankAsExpense = "NLERPReportBankToNonBankAsExpense"
    static let reportBankToAssetAsExpense = "NLERPReportBankToAssetAsExpense"
    static let reportBankToReceivableAsExpense = "NLERPReportBankToReceivableAsExpense"
    static let reportBankToPayableAsExpense = "NLERPReportBankToPayableAsExpense"
    static let reportExcludeLoanTransfers = "NLERPReportExcludeLoanTransfers"
    static let reportExcludeBankToBankTransfers = "NLERPReportExcludeBankToBankTransfers"
    static let reportUseNetOfTax = "NLERPReportUseNetOfTax"
    static let reportIncludeArchivedAccounts = "NLERPReportIncludeArchivedAccounts"
    static let reportIncludeSubaccounts = "NLERPReportIncludeSubaccounts"
    static let reportIncludeZeroLines = "NLERPReportIncludeZeroLines"
    static let reportBalanceSignMode = "NLERPReportBalanceSignMode"
    static let fiscalYearStartMonth = "NLERPFiscalYearStartMonth"
    static let defaultComparisonPeriods = "NLERPDefaultComparisonPeriods"

    static let summaryIncludeDirectIncome = "NLERPSummaryIncludeDirectIncome"
    static let summaryIncludeRefunds = "NLERPSummaryIncludeRefunds"
    static let summaryIncludeDirectExpense = "NLERPSummaryIncludeDirectExpense"
    static let summaryIncludeLoanIncrease = "NLERPSummaryIncludeLoanIncrease"
    static let summaryIncludeLoanPaid = "NLERPSummaryIncludeLoanPaid"
    static let summaryIncludeReceivableCollections = "NLERPSummaryIncludeReceivableCollections"
    static let summaryIncludeAssetToBank = "NLERPSummaryIncludeAssetToBank"
    static let summaryIncludeBankToAsset = "NLERPSummaryIncludeBankToAsset"
    static let summaryDirectIncomeBankOnly = "NLERPSummaryDirectIncomeBankOnly"
    static let summaryDirectExpenseBankOnly = "NLERPSummaryDirectExpenseBankOnly"
    static let summaryIncludeOpeningBalance = "NLERPSummaryIncludeOpeningBalance"
    static let summaryOpeningSource = "NLERPSummaryOpeningSource"
    static let summaryNetMode = "NLERPSummaryNetMode"
    static let summaryBalanceAccountIDsJSON = "NLERPSummaryBalanceAccountIDsJSON"
    static let summaryNetIncludeBank = "NLERPSummaryNetIncludeBank"
    static let summaryNetIncludeAsset = "NLERPSummaryNetIncludeAsset"
    static let summaryNetIncludeReceivable = "NLERPSummaryNetIncludeReceivable"
    static let summaryNetIncludeControl = "NLERPSummaryNetIncludeControl"
    static let summaryNetIncludeFixedAsset = "NLERPSummaryNetIncludeFixedAsset"
    static let summaryNetIncludeLoan = "NLERPSummaryNetIncludeLoan"
    static let summaryNetIncludePayable = "NLERPSummaryNetIncludePayable"
    static let summaryNetIncludeFixedLiability = "NLERPSummaryNetIncludeFixedLiability"
    static let summaryIncludeUnlinkedFixedAssetRegister = "NLERPSummaryIncludeUnlinkedFixedAssetRegister"
    static let summaryIncludeUnlinkedFixedLiabilityRegister = "NLERPSummaryIncludeUnlinkedFixedLiabilityRegister"

    static let loanDetectionMode = "NLERPLoanDetectionMode"
    static let paymentPositiveActsReceivable = "NLERPPaymentPositiveActsReceivable"
    static let paymentNegativeActsLoan = "NLERPPaymentNegativeActsLoan"

    static let budgetAlertPercent = "NLERPBudgetAlertPercent"
    static let budgetHistoryMonths = "NLERPBudgetHistoryMonths"
    static let budgetHistoricalFactorPercent = "NLERPBudgetHistoricalFactorPercent"
    static let budgetIncomeAllocationPercent = "NLERPBudgetIncomeAllocationPercent"
    static let budgetRoundingDecimals = "NLERPBudgetRoundingDecimals"

    static let taxEnabled = "NLERPTaxEnabled"
    static let taxDefaultRatePercent = "NLERPTaxDefaultRatePercent"
    static let taxDefaultInclusive = "NLERPTaxDefaultInclusive"
    static let taxDefaultRecoverablePercent = "NLERPTaxDefaultRecoverablePercent"
    static let taxRulesJSON = "NLERPTaxRulesJSONV1"

    static let dimensionDefinitionsJSON = "NLERPDimensionDefinitionsJSONV1"
    static let reportDefinitionsJSON = "NLERPReportDefinitionsJSONV1"

    static let fixedAssetDefaultRate = "NLERPFixedAssetDefaultRate"
    static let fixedAssetDefaultLifeMonths = "NLERPFixedAssetDefaultLifeMonths"
    static let fixedAssetDefaultResidualPercent = "NLERPFixedAssetDefaultResidualPercent"
    static let fixedAssetDepreciationConvention = "NLERPFixedAssetDepreciationConvention"
    static let fixedAssetDepreciationDecimals = "NLERPFixedAssetDepreciationDecimals"

    static let allSimpleKeys: [String] = [
        enabled, preset,
        rateSource, rateAllowInverse, rateAllowTriangulation, ratePivotCurrency,
        rateMissingPolicy, legacyQARPKR, legacyUSDQAR, reportAmountDecimals,
        reportRateDecimals, reportRoundingMode, useTransactionDateForRates,
        postingRoundAmounts, postingAmountDecimals, postingRequireAccount,
        postingRequireCategory, postingRequireDescription, postingRequireExpenseVendor,
        postingRequireIncomeVendor, postingBlockZero, postingMaxFutureDays,
        postingMaxBackdateDays, postingBlockDuplicates, postingDuplicateWindowMinutes,
        postingBlockNegativeBankBalance, postingNegativeBankFloor, postingBlockHighValue,
        postingHighValueThreshold, postingBlockArchivedAccount,
        postingRequireConfiguredDimensions, transferRequireDescription,
        transferForceSameCurrencyParity, transferUseConfiguredRate,
        reportRefundsAsIncome, reportReceivableCollectionsAsIncome,
        reportPaymentPositiveAsReceivable, reportNonBankToBankAsIncome,
        reportPayableFundingAsIncome, reportBankToNonBankAsExpense,
        reportBankToAssetAsExpense, reportBankToReceivableAsExpense,
        reportBankToPayableAsExpense, reportExcludeLoanTransfers,
        reportExcludeBankToBankTransfers, reportUseNetOfTax,
        reportIncludeArchivedAccounts, reportIncludeSubaccounts, reportIncludeZeroLines,
        reportBalanceSignMode, fiscalYearStartMonth, defaultComparisonPeriods,
        summaryIncludeDirectIncome, summaryIncludeRefunds, summaryIncludeDirectExpense,
        summaryIncludeLoanIncrease, summaryIncludeLoanPaid,
        summaryIncludeReceivableCollections, summaryIncludeAssetToBank,
        summaryIncludeBankToAsset, summaryDirectIncomeBankOnly,
        summaryDirectExpenseBankOnly, summaryIncludeOpeningBalance,
        summaryOpeningSource, summaryNetMode, summaryNetIncludeBank,
        summaryNetIncludeAsset, summaryNetIncludeReceivable, summaryNetIncludeControl,
        summaryNetIncludeFixedAsset, summaryNetIncludeLoan, summaryNetIncludePayable,
        summaryNetIncludeFixedLiability, summaryIncludeUnlinkedFixedAssetRegister,
        summaryIncludeUnlinkedFixedLiabilityRegister, loanDetectionMode,
        paymentPositiveActsReceivable, paymentNegativeActsLoan,
        budgetAlertPercent, budgetHistoryMonths, budgetHistoricalFactorPercent,
        budgetIncomeAllocationPercent, budgetRoundingDecimals,
        taxEnabled, taxDefaultRatePercent, taxDefaultInclusive,
        taxDefaultRecoverablePercent, fixedAssetDefaultRate,
        fixedAssetDefaultLifeMonths, fixedAssetDefaultResidualPercent,
        fixedAssetDepreciationConvention, fixedAssetDepreciationDecimals
    ]
}

enum ERPRateSource: String, CaseIterable, Identifiable, Codable {
    case customThenLegacy = "Custom → Legacy"
    case customOnly = "Custom Only"
    case legacyOnly = "Legacy Only"
    var id: String { rawValue }
}

enum ERPMissingRatePolicy: String, CaseIterable, Identifiable, Codable {
    case exclude = "Exclude Amount"
    case oneToOne = "Use 1:1"
    case legacyFallback = "Legacy Fallback"
    var id: String { rawValue }
}

enum ERPRoundingMode: String, CaseIterable, Identifiable, Codable {
    case plain = "Nearest"
    case down = "Down"
    case up = "Up"
    case bankers = "Bankers"
    var id: String { rawValue }

    var decimalMode: Decimal.RoundingMode {
        switch self {
        case .plain: return .plain
        case .down: return .down
        case .up: return .up
        case .bankers: return .bankers
        }
    }
}

enum ERPBalanceSignMode: String, CaseIterable, Identifiable, Codable {
    case raw = "Ledger Sign"
    case natural = "Natural Debit/Credit"
    case absoluteByNature = "Positive Assets / Negative Liabilities"
    var id: String { rawValue }
}

enum ERPSummaryNetMode: String, CaseIterable, Identifiable, Codable {
    case flowPlusOpening = "Opening + Period Flow"
    case periodFlow = "Period Flow Only"
    case selectedClosing = "Selected Accounts Closing"
    case liquidNetWorth = "Liquid Net Worth"
    case totalNetWorth = "Total Net Worth"
    var id: String { rawValue }
}

enum ERPSummaryOpeningSource: String, CaseIterable, Identifiable, Codable {
    case existingSelection = "Financial Summary Selection"
    case allBankAccounts = "All Bank Accounts"
    case selectedAccounts = "ERP Selected Accounts"
    case liquidAccounts = "All Liquid Accounts"
    var id: String { rawValue }
}

enum ERPLoanDetectionMode: String, CaseIterable, Identifiable, Codable {
    case hybrid = "Nature + Payments Balance"
    case natureOnly = "Account Nature Only"
    case paymentsOnly = "Payments Group Only"
    var id: String { rawValue }
}

enum ERPDepreciationConvention: String, CaseIterable, Identifiable, Codable {
    case fullMonth = "Full Purchase Month"
    case nextMonth = "Start Next Month"
    case halfMonth = "Half First Month"
    var id: String { rawValue }
}

struct ERPCurrencyRate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var fromCurrency: String = "QAR"
    var toCurrency: String = "PKR"
    var rate: Decimal = 77
    var effectiveFrom: Date = Date.distantPast
    var effectiveTo: Date? = nil
    var enabled: Bool = true
    var note: String = ""

    var pairTitle: String { "\(fromCurrency.uppercased()) → \(toCurrency.uppercased())" }

    func applies(on date: Date) -> Bool {
        enabled && date >= effectiveFrom && (effectiveTo == nil || date <= effectiveTo!)
    }
}

struct ERPTaxRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "Tax Rule"
    var categoryContains: String = ""
    var ratePercent: Decimal = 0
    var inclusive: Bool = true
    var recoverablePercent: Decimal = 100
    var appliesToIncome: Bool = true
    var appliesToExpense: Bool = true
    var enabled: Bool = true
}

struct ERPDimensionDefinition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "Cost Center"
    var values: [String] = []
    var requiredForIncome: Bool = false
    var requiredForExpense: Bool = false
    var requiredForTransfer: Bool = false
    var enabled: Bool = true

    func required(for type: TransactionType) -> Bool {
        switch type {
        case .income: return requiredForIncome
        case .expense: return requiredForExpense
        case .transfer: return requiredForTransfer
        }
    }
}

enum ERPReportComponent: String, CaseIterable, Identifiable, Codable {
    case directIncome
    case refunds
    case allReportIncome
    case directExpenses
    case allReportExpenses
    case loanIncreases
    case loanPayments
    case receivableCollections
    case bankBalances
    case assetBalances
    case receivableBalances
    case payableBalances
    case loanBalances
    case fixedAssetBalances
    case fixedLiabilityBalances
    case selectedAccountBalances
    case categoryIncome
    case categoryExpense
    case netCashFlow
    case netWorth

    var id: String { rawValue }
    var title: String {
        switch self {
        case .directIncome: return "Direct Income"
        case .refunds: return "Refunds"
        case .allReportIncome: return "All Report Income"
        case .directExpenses: return "Direct Expenses"
        case .allReportExpenses: return "All Report Expenses"
        case .loanIncreases: return "Loans Increased"
        case .loanPayments: return "Loans Paid"
        case .receivableCollections: return "Receivable Collections"
        case .bankBalances: return "Bank Balances"
        case .assetBalances: return "Asset Balances"
        case .receivableBalances: return "Receivable Balances"
        case .payableBalances: return "Payable Balances"
        case .loanBalances: return "Loan Balances"
        case .fixedAssetBalances: return "Fixed Asset Balances"
        case .fixedLiabilityBalances: return "Fixed Liability Balances"
        case .selectedAccountBalances: return "Selected Account Balances"
        case .categoryIncome: return "Income Category"
        case .categoryExpense: return "Expense Category"
        case .netCashFlow: return "Net Cash Flow"
        case .netWorth: return "Net Worth"
        }
    }
}

struct ERPReportLineDefinition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String = "New Line"
    var component: ERPReportComponent = .directIncome
    var multiplier: Decimal = 1
    var accountIDs: [UUID] = []
    var categoryContains: String = ""
    var dimensionName: String = ""
    var dimensionValue: String = ""
    var includeInGrandTotal: Bool = true
}

struct ERPReportDefinition: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String = "Management Report"
    var currencyCode: String = "QAR"
    var lines: [ERPReportLineDefinition] = []
    var showGrandTotal: Bool = true
    var comparative: Bool = false
}

struct ERPTaxBreakdown {
    let gross: Decimal
    let net: Decimal
    let tax: Decimal
    let recoverableTax: Decimal
}

struct ERPTaxSummary {
    var outputTax: Decimal = 0
    var inputTax: Decimal = 0
    var recoverableInputTax: Decimal = 0
    var netTaxDue: Decimal { outputTax - recoverableInputTax }
}

enum ERPStorage {
    static let defaults = UserDefaults.standard

    static func has(_ key: String) -> Bool { defaults.object(forKey: key) != nil }
    static func bool(_ key: String, _ fallback: Bool) -> Bool {
        has(key) ? defaults.bool(forKey: key) : fallback
    }
    static func int(_ key: String, _ fallback: Int) -> Int {
        has(key) ? defaults.integer(forKey: key) : fallback
    }
    static func double(_ key: String, _ fallback: Double) -> Double {
        has(key) ? defaults.double(forKey: key) : fallback
    }
    static func string(_ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }
    static func decimal(_ key: String, _ fallback: Decimal) -> Decimal {
        guard has(key) else { return fallback }
        if let text = defaults.string(forKey: key), let value = Decimal(string: text) { return value }
        return Decimal(defaults.double(forKey: key))
    }
    static func setDecimal(_ value: Decimal, for key: String) {
        defaults.set(NSDecimalNumber(decimal: value).stringValue, forKey: key)
    }

    static func decode<T: Decodable>(_ type: T.Type, key: String, fallback: T) -> T {
        guard let text = defaults.string(forKey: key), let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(type, from: data) else { return fallback }
        return value
    }
    static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value),
              let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: key)
    }
}

enum ERPAccountingEngine {
    static var isEnabled: Bool { ERPStorage.bool(ERPKey.enabled, true) }

    static var rateSource: ERPRateSource {
        ERPRateSource(rawValue: ERPStorage.string(ERPKey.rateSource, ERPRateSource.customThenLegacy.rawValue)) ?? .customThenLegacy
    }
    static var missingRatePolicy: ERPMissingRatePolicy {
        ERPMissingRatePolicy(rawValue: ERPStorage.string(ERPKey.rateMissingPolicy, ERPMissingRatePolicy.exclude.rawValue)) ?? .exclude
    }
    static var roundingMode: ERPRoundingMode {
        ERPRoundingMode(rawValue: ERPStorage.string(ERPKey.reportRoundingMode, ERPRoundingMode.plain.rawValue)) ?? .plain
    }
    static var reportDecimals: Int { max(0, min(6, ERPStorage.int(ERPKey.reportAmountDecimals, 2))) }
    static var postingDecimals: Int { max(0, min(6, ERPStorage.int(ERPKey.postingAmountDecimals, 2))) }
    static var rateDecimals: Int { max(2, min(12, ERPStorage.int(ERPKey.reportRateDecimals, 6))) }
    static var pivotCurrency: String { ERPStorage.string(ERPKey.ratePivotCurrency, "QAR").uppercased() }

    static var currencyRates: [ERPCurrencyRate] {
        get { ERPStorage.decode([ERPCurrencyRate].self, key: ERPKey.currencyRatesJSON, fallback: []) }
        set { ERPStorage.encode(newValue, key: ERPKey.currencyRatesJSON) }
    }
    static var taxRules: [ERPTaxRule] {
        get { ERPStorage.decode([ERPTaxRule].self, key: ERPKey.taxRulesJSON, fallback: []) }
        set { ERPStorage.encode(newValue, key: ERPKey.taxRulesJSON) }
    }
    static var dimensionDefinitions: [ERPDimensionDefinition] {
        get { ERPStorage.decode([ERPDimensionDefinition].self, key: ERPKey.dimensionDefinitionsJSON, fallback: []) }
        set { ERPStorage.encode(newValue, key: ERPKey.dimensionDefinitionsJSON) }
    }
    static var reportDefinitions: [ERPReportDefinition] {
        get {
            ERPStorage.decode(
                [ERPReportDefinition].self,
                key: ERPKey.reportDefinitionsJSON,
                fallback: defaultReportDefinitions
            )
        }
        set { ERPStorage.encode(newValue, key: ERPKey.reportDefinitionsJSON) }
    }

    static var defaultReportDefinitions: [ERPReportDefinition] {
        [
            ERPReportDefinition(
                name: "Management Summary",
                currencyCode: "QAR",
                lines: [
                    ERPReportLineDefinition(label: "Direct Income", component: .directIncome, multiplier: 1),
                    ERPReportLineDefinition(label: "Refunds", component: .refunds, multiplier: 1),
                    ERPReportLineDefinition(label: "Loans Increased", component: .loanIncreases, multiplier: 1),
                    ERPReportLineDefinition(label: "Direct Expenses", component: .directExpenses, multiplier: -1),
                    ERPReportLineDefinition(label: "Loans Paid", component: .loanPayments, multiplier: -1),
                    ERPReportLineDefinition(label: "Bank Balances", component: .bankBalances, multiplier: 1, includeInGrandTotal: false),
                    ERPReportLineDefinition(label: "Net Worth", component: .netWorth, multiplier: 1, includeInGrandTotal: false)
                ],
                showGrandTotal: true,
                comparative: true
            ),
            ERPReportDefinition(
                name: "Cash Flow",
                currencyCode: "QAR",
                lines: [
                    ERPReportLineDefinition(label: "All Cash Income", component: .allReportIncome, multiplier: 1),
                    ERPReportLineDefinition(label: "All Cash Expenses", component: .allReportExpenses, multiplier: -1),
                    ERPReportLineDefinition(label: "Loan Drawdowns", component: .loanIncreases, multiplier: 1),
                    ERPReportLineDefinition(label: "Loan Repayments", component: .loanPayments, multiplier: -1),
                    ERPReportLineDefinition(label: "Net Cash Flow", component: .netCashFlow, multiplier: 1, includeInGrandTotal: false)
                ],
                showGrandTotal: true,
                comparative: false
            )
        ]
    }

    static func round(_ value: Decimal, scale: Int? = nil) -> Decimal {
        var input = value
        var output = Decimal.zero
        NSDecimalRound(&output, &input, scale ?? reportDecimals, roundingMode.decimalMode)
        return output
    }

    static func postingAmount(_ amount: Decimal) -> Decimal {
        guard isEnabled && ERPStorage.bool(ERPKey.postingRoundAmounts, false) else { return amount }
        return round(amount, scale: postingDecimals)
    }

    static func legacyRate(from source: String, to destination: String) -> Decimal? {
        let from = source.uppercased()
        let to = destination.uppercased()
        if from == to { return 1 }
        let qarToPkr = ERPStorage.decimal(ERPKey.legacyQARPKR, Decimal(77))
        let usdToQar = ERPStorage.decimal(ERPKey.legacyUSDQAR, Decimal(string: "3.65")!)
        guard qarToPkr > 0, usdToQar > 0 else { return nil }
        let usdToPkr = usdToQar * qarToPkr
        switch (from, to) {
        case ("QAR", "PKR"): return qarToPkr
        case ("PKR", "QAR"): return 1 / qarToPkr
        case ("USD", "QAR"): return usdToQar
        case ("QAR", "USD"): return 1 / usdToQar
        case ("USD", "PKR"): return usdToPkr
        case ("PKR", "USD"): return 1 / usdToPkr
        default: return nil
        }
    }

    static func directCustomRate(from source: String, to destination: String, on date: Date) -> Decimal? {
        let from = source.uppercased()
        let to = destination.uppercased()
        let candidates = currencyRates.filter {
            $0.fromCurrency.uppercased() == from && $0.toCurrency.uppercased() == to && $0.applies(on: date) && $0.rate > 0
        }.sorted { $0.effectiveFrom > $1.effectiveFrom }
        return candidates.first?.rate
    }

    static func rate(from source: String, to destination: String, on date: Date = Date()) -> Decimal? {
        let from = source.uppercased()
        let to = destination.uppercased()
        if from == to { return 1 }
        guard isEnabled else { return legacyRate(from: from, to: to) }

        let allowInverse = ERPStorage.bool(ERPKey.rateAllowInverse, true)
        let allowTriangulation = ERPStorage.bool(ERPKey.rateAllowTriangulation, true)

        func custom(_ a: String, _ b: String) -> Decimal? {
            if let direct = directCustomRate(from: a, to: b, on: date) { return direct }
            if allowInverse, let reverse = directCustomRate(from: b, to: a, on: date), reverse != 0 { return 1 / reverse }
            return nil
        }

        func legacy(_ a: String, _ b: String) -> Decimal? { legacyRate(from: a, to: b) }

        let primary: Decimal?
        switch rateSource {
        case .customOnly: primary = custom(from, to)
        case .legacyOnly: primary = legacy(from, to)
        case .customThenLegacy: primary = custom(from, to) ?? legacy(from, to)
        }
        if let primary { return round(primary, scale: rateDecimals) }

        if allowTriangulation {
            let pivot = pivotCurrency
            if pivot != from && pivot != to {
                let left: Decimal?
                let right: Decimal?
                switch rateSource {
                case .customOnly:
                    left = custom(from, pivot)
                    right = custom(pivot, to)
                case .legacyOnly:
                    left = legacy(from, pivot)
                    right = legacy(pivot, to)
                case .customThenLegacy:
                    left = custom(from, pivot) ?? legacy(from, pivot)
                    right = custom(pivot, to) ?? legacy(pivot, to)
                }
                if let left, let right { return round(left * right, scale: rateDecimals) }
            }
        }

        switch missingRatePolicy {
        case .exclude: return nil
        case .oneToOne: return 1
        case .legacyFallback: return legacy(from, to)
        }
    }

    static func taxBreakdown(amount: Decimal, category: String, type: TransactionType) -> ERPTaxBreakdown {
        guard isEnabled && ERPStorage.bool(ERPKey.taxEnabled, false), amount != 0 else {
            return ERPTaxBreakdown(gross: amount, net: amount, tax: 0, recoverableTax: 0)
        }
        let normalized = category.lowercased()
        let rule = taxRules.first {
            $0.enabled &&
            ($0.categoryContains.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalized.contains($0.categoryContains.lowercased())) &&
            ((type == .income && $0.appliesToIncome) || (type == .expense && $0.appliesToExpense))
        }
        let ratePercent = rule?.ratePercent ?? ERPStorage.decimal(ERPKey.taxDefaultRatePercent, 0)
        let inclusive = rule?.inclusive ?? ERPStorage.bool(ERPKey.taxDefaultInclusive, true)
        let recoverable = rule?.recoverablePercent ?? ERPStorage.decimal(ERPKey.taxDefaultRecoverablePercent, 100)
        guard ratePercent > 0 else {
            return ERPTaxBreakdown(gross: amount, net: amount, tax: 0, recoverableTax: 0)
        }
        let rate = ratePercent / 100
        let net = inclusive ? amount / (1 + rate) : amount
        let tax = inclusive ? amount - net : amount * rate
        let gross = inclusive ? amount : amount + tax
        let recoverableTax = type == .expense ? tax * max(0, min(100, recoverable)) / 100 : 0
        return ERPTaxBreakdown(
            gross: round(gross),
            net: round(net),
            tax: round(tax),
            recoverableTax: round(recoverableTax)
        )
    }

    static func dimensions(from values: [String: String]) -> [ERPTransactionDimension]? {
        let entries = values
            .map { ERPTransactionDimension(name: $0.key, value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.name.isEmpty && !$0.value.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return entries.isEmpty ? nil : entries
    }

    static func dimensionDictionary(_ transaction: LedgerTransaction) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (transaction.dimensions ?? []).map { ($0.name, $0.value) })
    }

    static func configurationFingerprint() -> String {
        guard isEnabled else { return "erp-off" }
        var parts = ERPKey.allSimpleKeys.map { key in
            let raw = ERPStorage.defaults.object(forKey: key)
            let rendered = raw.map { String(describing: $0) } ?? "default"
            return "\(key)=\(rendered)"
        }
        parts.append(ERPStorage.string(ERPKey.currencyRatesJSON, "[]"))
        parts.append(ERPStorage.string(ERPKey.taxRulesJSON, "[]"))
        parts.append(ERPStorage.string(ERPKey.dimensionDefinitionsJSON, "[]"))
        return String(parts.joined(separator: "|").hashValue)
    }

    static func rateSummaryText(reportingCurrency: String) -> String {
        let code = reportingCurrency.uppercased()
        let pkr = rate(from: "PKR", to: code)
        let usd = rate(from: "USD", to: code)
        var pieces: [String] = []
        if let pkr { pieces.append("1 PKR = \(NSDecimalNumber(decimal: round(pkr, scale: 6)).stringValue) \(code)") }
        if let usd { pieces.append("1 USD = \(NSDecimalNumber(decimal: round(usd, scale: 6)).stringValue) \(code)") }
        return pieces.isEmpty ? "No configured conversion rate to \(code)." : pieces.joined(separator: " · ")
    }

    static func exportConfiguration() -> String {
        var result: [String: Any] = [:]
        for key in ERPKey.allSimpleKeys {
            if let value = ERPStorage.defaults.object(forKey: key) { result[key] = value }
        }
        for key in [ERPKey.currencyRatesJSON, ERPKey.taxRulesJSON, ERPKey.dimensionDefinitionsJSON, ERPKey.reportDefinitionsJSON, ERPKey.summaryBalanceAccountIDsJSON] {
            if let value = ERPStorage.defaults.string(forKey: key) { result[key] = value }
        }
        result["schema"] = 1
        guard JSONSerialization.isValidJSONObject(result),
              let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    @discardableResult
    static func importConfiguration(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        let allowed = Set(ERPKey.allSimpleKeys + [ERPKey.currencyRatesJSON, ERPKey.taxRulesJSON, ERPKey.dimensionDefinitionsJSON, ERPKey.reportDefinitionsJSON, ERPKey.summaryBalanceAccountIDsJSON])
        for (key, value) in object where allowed.contains(key) { ERPStorage.defaults.set(value, forKey: key) }
        return true
    }

    static func resetAll() {
        for key in ERPKey.allSimpleKeys + [ERPKey.currencyRatesJSON, ERPKey.taxRulesJSON, ERPKey.dimensionDefinitionsJSON, ERPKey.reportDefinitionsJSON, ERPKey.summaryBalanceAccountIDsJSON] {
            ERPStorage.defaults.removeObject(forKey: key)
        }
    }

    static func applyPreset(_ preset: String) {
        let preserved = Set([ERPKey.enabled, ERPKey.preset])
        for key in ERPKey.allSimpleKeys where !preserved.contains(key) {
            ERPStorage.defaults.removeObject(forKey: key)
        }
        ERPStorage.defaults.set(preset, forKey: ERPKey.preset)
        ERPStorage.defaults.set(true, forKey: ERPKey.enabled)
        switch preset {
        case "Accrual Accounting":
            ERPStorage.defaults.set(false, forKey: ERPKey.reportBankToAssetAsExpense)
            ERPStorage.defaults.set(false, forKey: ERPKey.reportBankToReceivableAsExpense)
            ERPStorage.defaults.set(false, forKey: ERPKey.reportBankToPayableAsExpense)
            ERPStorage.defaults.set(false, forKey: ERPKey.reportPayableFundingAsIncome)
            ERPStorage.defaults.set(true, forKey: ERPKey.reportExcludeLoanTransfers)
            ERPStorage.defaults.set(ERPSummaryNetMode.totalNetWorth.rawValue, forKey: ERPKey.summaryNetMode)
        case "Cash Management":
            ERPStorage.defaults.set(true, forKey: ERPKey.reportNonBankToBankAsIncome)
            ERPStorage.defaults.set(true, forKey: ERPKey.reportBankToNonBankAsExpense)
            ERPStorage.defaults.set(true, forKey: ERPKey.summaryIncludeReceivableCollections)
            ERPStorage.defaults.set(ERPSummaryNetMode.flowPlusOpening.rawValue, forKey: ERPKey.summaryNetMode)
        case "Strict Posting":
            ERPStorage.defaults.set(true, forKey: ERPKey.postingRequireDescription)
            ERPStorage.defaults.set(true, forKey: ERPKey.postingRequireExpenseVendor)
            ERPStorage.defaults.set(true, forKey: ERPKey.postingBlockDuplicates)
            ERPStorage.defaults.set(true, forKey: ERPKey.postingBlockNegativeBankBalance)
            ERPStorage.defaults.set(true, forKey: ERPKey.postingRoundAmounts)
        case "Personal Finance":
            ERPStorage.defaults.set(true, forKey: ERPKey.reportBankToAssetAsExpense)
            ERPStorage.defaults.set(true, forKey: ERPKey.reportBankToReceivableAsExpense)
            ERPStorage.defaults.set(true, forKey: ERPKey.reportBankToPayableAsExpense)
            ERPStorage.defaults.set(ERPSummaryNetMode.flowPlusOpening.rawValue, forKey: ERPKey.summaryNetMode)
        default:
            break
        }
    }
}

extension LedgerStore {
    func erpConvertedBalance(for account: LedgerAccount, before cutoff: Date?, to destinationCode: String) -> Decimal? {
        let balanceValue = cutoff.map { combinedBalance(for: [account], before: $0) } ?? balance(for: account)
        let rateDate = cutoff ?? Date()
        guard let rate = ERPAccountingEngine.rate(from: account.currencyCode, to: destinationCode, on: rateDate) else { return nil }
        return ERPAccountingEngine.round(balanceValue * rate)
    }

    func erpAccountBalanceContribution(_ account: LedgerAccount, before cutoff: Date?, to destinationCode: String) -> Decimal {
        guard let converted = erpConvertedBalance(for: account, before: cutoff, to: destinationCode) else { return 0 }
        let mode = ERPBalanceSignMode(rawValue: ERPStorage.string(ERPKey.reportBalanceSignMode, ERPBalanceSignMode.raw.rawValue)) ?? .raw
        guard mode != .raw else { return converted }
        let nature = account.nature ?? .unassigned
        let liability = nature == .loan || nature == .payable || nature == .fixedLiability
        if mode == .absoluteByNature { return liability ? -abs(converted) : abs(converted) }
        return liability ? -converted : converted
    }

    func erpSelectedSummaryAccounts(existing: [LedgerAccount]) -> [LedgerAccount] {
        let source = ERPSummaryOpeningSource(rawValue: ERPStorage.string(ERPKey.summaryOpeningSource, ERPSummaryOpeningSource.existingSelection.rawValue)) ?? .existingSelection
        switch source {
        case .existingSelection: return existing
        case .allBankAccounts:
            return accounts.filter { !$0.isArchived && $0.nature == .bank }
        case .selectedAccounts:
            let ids = Set(ERPStorage.decode([UUID].self, key: ERPKey.summaryBalanceAccountIDsJSON, fallback: []))
            return accounts.filter { ids.contains($0.id) }
        case .liquidAccounts:
            return accounts.filter {
                guard !$0.isArchived else { return false }
                let nature = $0.nature ?? .unassigned
                return nature == .bank || nature == .asset || nature == .receivable
            }
        }
    }

    func erpSummaryOpeningBalance(existingAccounts: [LedgerAccount], interval: DateInterval) -> Decimal {
        guard !ERPAccountingEngine.isEnabled || ERPStorage.bool(ERPKey.summaryIncludeOpeningBalance, true) else { return 0 }
        let accounts = ERPAccountingEngine.isEnabled ? erpSelectedSummaryAccounts(existing: existingAccounts) : existingAccounts
        if !ERPAccountingEngine.isEnabled {
            return combinedBalance(for: accounts, before: interval.start)
        }
        return accounts.reduce(Decimal.zero) { total, account in
            total + erpAccountBalanceContribution(account, before: interval.start, to: currencyCode)
        }
    }

    func erpNetWorth(asOf cutoff: Date, includeFixedAssets: Bool) -> Decimal {
        let includeArchived = ERPStorage.bool(ERPKey.reportIncludeArchivedAccounts, true)
        var result: Decimal = 0
        for account in accounts where includeArchived || !account.isArchived {
            let nature = account.nature ?? .unassigned
            let include: Bool
            switch nature {
            case .bank: include = ERPStorage.bool(ERPKey.summaryNetIncludeBank, true)
            case .asset: include = ERPStorage.bool(ERPKey.summaryNetIncludeAsset, true)
            case .receivable: include = ERPStorage.bool(ERPKey.summaryNetIncludeReceivable, true)
            case .control: include = ERPStorage.bool(ERPKey.summaryNetIncludeControl, false)
            case .fixedAsset: include = includeFixedAssets && ERPStorage.bool(ERPKey.summaryNetIncludeFixedAsset, true)
            case .loan: include = ERPStorage.bool(ERPKey.summaryNetIncludeLoan, true)
            case .payable: include = ERPStorage.bool(ERPKey.summaryNetIncludePayable, true)
            case .fixedLiability: include = ERPStorage.bool(ERPKey.summaryNetIncludeFixedLiability, true)
            default: include = false
            }
            if include { result += erpAccountBalanceContribution(account, before: cutoff, to: currencyCode) }
        }
        if includeFixedAssets && ERPStorage.bool(ERPKey.summaryIncludeUnlinkedFixedAssetRegister, false) {
            for record in fixedAssetRecords where record.linkedAccountID == nil && record.purchaseDate < cutoff {
                guard let rate = ERPAccountingEngine.rate(from: record.currencyCode, to: currencyCode, on: cutoff) else { continue }
                result += ERPAccountingEngine.round(record.netBookValue(asOf: cutoff) * rate)
            }
        }
        if ERPStorage.bool(ERPKey.summaryIncludeUnlinkedFixedLiabilityRegister, false) {
            for record in fixedLiabilityRecords where record.linkedAccountID == nil && record.startDate < cutoff {
                let outstanding = fixedLiabilitySnapshot(record, asOf: cutoff).outstanding
                guard let rate = ERPAccountingEngine.rate(from: record.currencyCode, to: currencyCode, on: cutoff) else { continue }
                result -= abs(ERPAccountingEngine.round(outstanding * rate))
            }
        }
        return ERPAccountingEngine.round(result)
    }

    func erpSummaryNetBalance(interval: DateInterval, openingBalance: Decimal, totalMoneyIn: Decimal, totalMoneyOut: Decimal) -> Decimal {
        guard ERPAccountingEngine.isEnabled else { return totalMoneyIn - totalMoneyOut + openingBalance }
        let mode = ERPSummaryNetMode(rawValue: ERPStorage.string(ERPKey.summaryNetMode, ERPSummaryNetMode.flowPlusOpening.rawValue)) ?? .flowPlusOpening
        switch mode {
        case .flowPlusOpening: return ERPAccountingEngine.round(totalMoneyIn - totalMoneyOut + openingBalance)
        case .periodFlow: return ERPAccountingEngine.round(totalMoneyIn - totalMoneyOut)
        case .selectedClosing:
            let accounts = erpSelectedSummaryAccounts(existing: [])
            return ERPAccountingEngine.round(accounts.reduce(Decimal.zero) {
                $0 + erpAccountBalanceContribution($1, before: interval.end, to: currencyCode)
            })
        case .liquidNetWorth: return erpNetWorth(asOf: interval.end, includeFixedAssets: false)
        case .totalNetWorth: return erpNetWorth(asOf: interval.end, includeFixedAssets: true)
        }
    }

    func erpRateSummaryText() -> String {
        ERPAccountingEngine.rateSummaryText(reportingCurrency: currencyCode)
    }

    func erpTransactionMatchesDimensions(_ transaction: LedgerTransaction, line: ERPReportLineDefinition) -> Bool {
        let name = line.dimensionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line.dimensionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !value.isEmpty else { return true }
        return (transaction.dimensions ?? []).contains {
            $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.value.caseInsensitiveCompare(value) == .orderedSame
        }
    }

    func erpCustomReportLineValue(_ line: ERPReportLineDefinition, interval: DateInterval, currencyCode requestedCurrency: String) -> Decimal {
        erpReportLineValue(line, interval: interval, currencyCode: requestedCurrency)
    }

    func erpReportLineValue(_ line: ERPReportLineDefinition, interval: DateInterval, currencyCode requestedCurrency: String) -> Decimal {
        let categoryNeedle = line.categoryContains.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredTransactions = transactions.filter {
            interval.contains($0.date) && erpTransactionMatchesDimensions($0, line: line) &&
            (categoryNeedle.isEmpty || $0.category.localizedCaseInsensitiveContains(categoryNeedle))
        }
        let selectedIDs = Set(line.accountIDs)
        func accountAllowed(_ id: UUID?) -> Bool { selectedIDs.isEmpty || id.map(selectedIDs.contains) == true }
        func converted(_ amount: Decimal, accountID: UUID?, date: Date) -> Decimal {
            let source = account(withID: accountID)?.currencyCode ?? requestedCurrency
            guard let rate = ERPAccountingEngine.rate(from: source, to: requestedCurrency, on: date) else { return 0 }
            return ERPAccountingEngine.round(amount * rate)
        }
        var value: Decimal = 0
        switch line.component {
        case .directIncome:
            value = filteredTransactions.filter { isFinancialSummaryDirectIncome($0) && accountAllowed($0.accountID) }
                .reduce(0) { $0 + converted($1.amount, accountID: $1.accountID, date: $1.date) }
        case .refunds:
            value = filteredTransactions.filter { isFinancialSummaryRefund($0) && accountAllowed($0.accountID) }
                .reduce(0) { $0 + converted($1.amount, accountID: $1.accountID, date: $1.date) }
        case .allReportIncome:
            value = filteredTransactions.filter { isReportIncome($0) && accountAllowed(reportIncomeAccountID($0)) }
                .reduce(0) { $0 + (convertedReportIncomeAmount($1, to: requestedCurrency) ?? 0) }
        case .directExpenses:
            value = filteredTransactions.filter { isFinancialSummaryDirectExpense($0) && accountAllowed($0.accountID) }
                .reduce(0) { $0 + converted($1.amount, accountID: $1.accountID, date: $1.date) }
        case .allReportExpenses:
            value = filteredTransactions.filter { isReportExpense($0) && accountAllowed(reportExpenseAccountID($0)) }
                .reduce(0) { $0 + (convertedReportExpenseAmount($1, to: requestedCurrency) ?? 0) }
        case .loanIncreases:
            value = filteredTransactions.filter { accountAllowed($0.accountID) }.reduce(0) {
                let amount = financialSummaryLoanIncreaseAmount($1)
                return $0 + converted(amount, accountID: $1.accountID, date: $1.date)
            }
        case .loanPayments:
            value = filteredTransactions.filter { accountAllowed($0.accountID) }.reduce(0) {
                let amount = financialSummaryLoanPaidAmount($1)
                return $0 + converted(amount, accountID: $1.accountID, date: $1.date)
            }
        case .receivableCollections:
            value = filteredTransactions.filter { accountAllowed($0.accountID) }.reduce(0) {
                let amount = receivableCollectionAmount($1)
                return $0 + converted(amount, accountID: $1.accountID, date: $1.date)
            }
        case .bankBalances, .assetBalances, .receivableBalances, .payableBalances, .loanBalances, .fixedAssetBalances, .fixedLiabilityBalances, .selectedAccountBalances:
            let targetNature: AccountNature?
            switch line.component {
            case .bankBalances: targetNature = .bank
            case .assetBalances: targetNature = .asset
            case .receivableBalances: targetNature = .receivable
            case .payableBalances: targetNature = .payable
            case .loanBalances: targetNature = .loan
            case .fixedAssetBalances: targetNature = .fixedAsset
            case .fixedLiabilityBalances: targetNature = .fixedLiability
            default: targetNature = nil
            }
            value = accounts.filter {
                (selectedIDs.isEmpty || selectedIDs.contains($0.id)) && (targetNature == nil || $0.nature == targetNature)
            }.reduce(0) { $0 + (erpConvertedBalance(for: $1, before: interval.end, to: requestedCurrency) ?? 0) }
        case .categoryIncome:
            value = filteredTransactions.filter { isReportIncome($0) && accountAllowed(reportIncomeAccountID($0)) }
                .reduce(0) { $0 + (convertedReportIncomeAmount($1, to: requestedCurrency) ?? 0) }
        case .categoryExpense:
            value = filteredTransactions.filter { isReportExpense($0) && accountAllowed(reportExpenseAccountID($0)) }
                .reduce(0) { $0 + (convertedReportExpenseAmount($1, to: requestedCurrency) ?? 0) }
        case .netCashFlow:
            let income = filteredTransactions.filter(isReportIncome).reduce(0) { $0 + (convertedReportIncomeAmount($1, to: requestedCurrency) ?? 0) }
            let expense = filteredTransactions.filter(isReportExpense).reduce(0) { $0 + (convertedReportExpenseAmount($1, to: requestedCurrency) ?? 0) }
            value = income - expense
        case .netWorth:
            if requestedCurrency.caseInsensitiveCompare(currencyCode) == .orderedSame {
                value = erpNetWorth(asOf: interval.end, includeFixedAssets: true)
            } else {
                value = accounts.reduce(0) { $0 + (erpConvertedBalance(for: $1, before: interval.end, to: requestedCurrency) ?? 0) }
            }
        }
        return ERPAccountingEngine.round(value * line.multiplier)
    }

    func erpTaxSummary(interval: DateInterval, currencyCode requestedCurrency: String) -> ERPTaxSummary {
        var summary = ERPTaxSummary()
        for transaction in transactions where interval.contains(transaction.date) && transaction.type != .transfer {
            let breakdown = ERPAccountingEngine.taxBreakdown(amount: transaction.amount, category: transaction.category, type: transaction.type)
            guard breakdown.tax != 0,
                  let source = account(withID: transaction.accountID),
                  let rate = ERPAccountingEngine.rate(from: source.currencyCode, to: requestedCurrency, on: transaction.date) else { continue }
            let tax = ERPAccountingEngine.round(breakdown.tax * rate)
            let recoverable = ERPAccountingEngine.round(breakdown.recoverableTax * rate)
            if transaction.type == .income { summary.outputTax += tax }
            if transaction.type == .expense {
                summary.inputTax += tax
                summary.recoverableInputTax += recoverable
            }
        }
        return summary
    }

    func erpPostingError(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String?,
        details: String,
        accountID: UUID?,
        destinationAccountID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        dimensions: [ERPTransactionDimension]? = nil,
        excludingTransactionID: UUID? = nil
    ) -> String? {
        guard ERPAccountingEngine.isEnabled else { return nil }
        if ERPStorage.bool(ERPKey.postingBlockZero, true), amount <= 0 { return "Amount must be greater than zero." }
        if ERPStorage.bool(ERPKey.postingRequireAccount, true), accountID == nil { return "An account is required by ERP posting rules." }
        if ERPStorage.bool(ERPKey.postingRequireCategory, true), category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "A category is required by ERP posting rules." }
        if ERPStorage.bool(ERPKey.postingRequireDescription, false), details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "A description is required by ERP posting rules." }
        if type == .transfer && ERPStorage.bool(ERPKey.transferRequireDescription, false), details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Transfer description is required by ERP posting rules." }
        if type == .expense && ERPStorage.bool(ERPKey.postingRequireExpenseVendor, false), (vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Expense vendor is required by ERP posting rules." }
        if type == .income && ERPStorage.bool(ERPKey.postingRequireIncomeVendor, false), (vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Income source/vendor is required by ERP posting rules." }
        if let source = account(withID: accountID), ERPStorage.bool(ERPKey.postingBlockArchivedAccount, true), source.isArchived { return "Posting to an archived account is blocked." }
        if let destination = account(withID: destinationAccountID), ERPStorage.bool(ERPKey.postingBlockArchivedAccount, true), destination.isArchived { return "Posting to an archived destination account is blocked." }

        let today = Calendar.current.startOfDay(for: Date())
        let postingDay = Calendar.current.startOfDay(for: date)
        let futureDays = ERPStorage.int(ERPKey.postingMaxFutureDays, 3650)
        if futureDays >= 0, let latest = Calendar.current.date(byAdding: .day, value: futureDays, to: today), postingDay > latest { return "Transaction date exceeds the allowed future-date limit." }
        let backDays = ERPStorage.int(ERPKey.postingMaxBackdateDays, 0)
        if backDays > 0, let earliest = Calendar.current.date(byAdding: .day, value: -backDays, to: today), postingDay < earliest { return "Transaction date exceeds the allowed backdating limit." }

        if ERPStorage.bool(ERPKey.postingBlockHighValue, false) {
            let threshold = ERPStorage.decimal(ERPKey.postingHighValueThreshold, Decimal(100000))
            if threshold > 0 && amount > threshold { return "Amount exceeds the ERP high-value posting threshold." }
        }

        if ERPStorage.bool(ERPKey.postingRequireConfiguredDimensions, true) {
            let supplied = Dictionary(uniqueKeysWithValues: (dimensions ?? []).map { ($0.name.lowercased(), $0.value) })
            for definition in ERPAccountingEngine.dimensionDefinitions where definition.enabled && definition.required(for: type) {
                if supplied[definition.name.lowercased()]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    return "Dimension \"\(definition.name)\" is required for \(type.title.lowercased()) postings."
                }
            }
        }

        if type == .transfer, let source = account(withID: accountID), let destination = account(withID: destinationAccountID) {
            if source.id == destination.id { return "Source and destination accounts must be different." }
            if source.currencyCode.caseInsensitiveCompare(destination.currencyCode) == .orderedSame && ERPStorage.bool(ERPKey.transferForceSameCurrencyParity, true) {
                let received = destinationAmount ?? amount
                if abs(received - amount) > Decimal(string: "0.000001")! { return "Same-currency transfers must use the same source and destination amount." }
            }
        }

        if ERPStorage.bool(ERPKey.postingBlockNegativeBankBalance, false),
           let source = account(withID: accountID), source.nature == .bank,
           type == .expense || type == .transfer {
            let floor = ERPStorage.decimal(ERPKey.postingNegativeBankFloor, 0)
            if balance(for: source) - amount < floor { return "Posting would take \(source.name) below the configured minimum balance." }
        }

        if ERPStorage.bool(ERPKey.postingBlockDuplicates, false) {
            let minutes = max(1, ERPStorage.int(ERPKey.postingDuplicateWindowMinutes, 10))
            let window = TimeInterval(minutes * 60)
            if transactions.contains(where: { item in
                item.id != excludingTransactionID && item.type == type && item.accountID == accountID &&
                abs(item.amount - amount) < Decimal(string: "0.000001")! &&
                abs(item.date.timeIntervalSince(date)) <= window &&
                item.category.caseInsensitiveCompare(category) == .orderedSame
            }) { return "Possible duplicate transaction blocked by ERP posting rules." }
        }
        return nil
    }
}
