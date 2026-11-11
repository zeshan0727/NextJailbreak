import Foundation

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .income: return "Income"
        case .expense: return "Expense"
        case .transfer: return "Transfer"
        }
    }
}

enum AccountGroup: String, Codable, CaseIterable, Identifiable {
    case qatar
    case pakistan
    case payments
    case assets
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qatar: return "Qatar"
        case .pakistan: return "Pakistan"
        case .payments: return "Payments"
        case .assets: return "Assets"
        case .other: return "Other"
        }
    }
}

enum AccountNature: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case loan
    case receivable
    case payable
    case control
    case asset
    case fixedAsset
    case fixedLiability
    case dailyExpense
    case bank

    var id: String { rawValue }
    var title: String {
        switch self {
        case .unassigned: return "Unassigned"
        case .loan: return "Loan"
        case .receivable: return "Receivable"
        case .payable: return "Payable"
        case .control: return "Control"
        case .asset: return "Asset"
        case .fixedAsset: return "Fixed Asset"
        case .fixedLiability: return "Fixed Liability"
        case .dailyExpense: return "Daily Expense"
        case .bank: return "Bank"
        }
    }
}

struct LedgerAccount: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var currencyCode: String
    var group: AccountGroup
    var icon: String
    var openingBalance: Decimal
    var isArchived: Bool
    var nature: AccountNature?
    var chartCode: String?
    var parentAccountID: UUID?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        currencyCode: String = "QAR",
        group: AccountGroup = .qatar,
        icon: String = "creditcard.fill",
        openingBalance: Decimal = 0,
        isArchived: Bool = false,
        nature: AccountNature? = nil,
        chartCode: String? = nil,
        parentAccountID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.currencyCode = currencyCode
        self.group = group
        self.icon = icon
        self.openingBalance = openingBalance
        self.isArchived = isArchived
        self.nature = nature
        self.chartCode = chartCode
        self.parentAccountID = parentAccountID
        self.createdAt = createdAt
    }

    static let legacyMainID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let legacyMain = LedgerAccount(
        id: legacyMainID,
        name: "Main Account",
        currencyCode: "QAR",
        group: .qatar,
        icon: "wallet.pass.fill"
    )
}

struct ERPTransactionDimension: Codable, Hashable, Identifiable {
    var id: String { name.lowercased() }
    var name: String
    var value: String

    init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

struct LedgerTransaction: Identifiable, Codable, Hashable {
    let id: UUID
    var type: TransactionType
    var amount: Decimal
    var date: Date
    var category: String
    var vendor: String?
    var details: String
    var accountID: UUID?
    var destinationAccountID: UUID?
    var destinationAmount: Decimal?
    var dimensions: [ERPTransactionDimension]?
    var refundOfTransactionID: UUID?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        type: TransactionType,
        amount: Decimal,
        date: Date = Date(),
        category: String,
        vendor: String? = nil,
        details: String = "",
        accountID: UUID? = nil,
        destinationAccountID: UUID? = nil,
        destinationAmount: Decimal? = nil,
        dimensions: [ERPTransactionDimension]? = nil,
        refundOfTransactionID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.amount = amount
        self.date = date
        self.category = category
        self.vendor = vendor
        self.details = details
        self.accountID = accountID
        self.destinationAccountID = destinationAccountID
        self.destinationAmount = destinationAmount
        self.dimensions = dimensions
        self.refundOfTransactionID = refundOfTransactionID
        self.createdAt = createdAt
    }
}

extension LedgerTransaction {
    static func vendorFromMessage(_ text: String) -> String? {
        let patterns = [
            #"(?i)\b(?:at|to|merchant)\s+([A-Z0-9][A-Z0-9 '&.-]{1,40}?)(?=\s+(?:on|at|for|using|card|amount|date|available)\b|[,.;\n]|$)"#,
            #"(?i)\bfrom\s+([A-Z0-9][A-Z0-9 '&.-]{1,40}?)(?=\s+(?:on|at|for|using|card|amount|date)\b|[,.;\n]|$)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2 { return value }
        }
        return nil
    }
}

struct VendorCategoryRule: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var keyword: String
    var category: String

    init(id: UUID = UUID(), keyword: String, category: String) {
        self.id = id
        self.keyword = keyword
        self.category = category
    }

    static let defaults: [VendorCategoryRule] = [
        VendorCategoryRule(keyword: "restaurant", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "cafe", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "coffee", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "kfc", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "bakery", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "cafeteria", category: "Restaurants & Cafes"),
        VendorCategoryRule(keyword: "grocery", category: "Grocery"),
        VendorCategoryRule(keyword: "supermarket", category: "Grocery"),
        VendorCategoryRule(keyword: "hypermarket", category: "Grocery"),
        VendorCategoryRule(keyword: "mini mart", category: "Grocery"),
        VendorCategoryRule(keyword: "mini market", category: "Grocery"),
        VendorCategoryRule(keyword: "woqod", category: "Fuel"),
        VendorCategoryRule(keyword: "petrol", category: "Fuel"),
        VendorCategoryRule(keyword: "fuel", category: "Fuel"),
        VendorCategoryRule(keyword: "uber", category: "Transport"),
        VendorCategoryRule(keyword: "karwa", category: "Transport"),
        VendorCategoryRule(keyword: "taxi", category: "Transport"),
        VendorCategoryRule(keyword: "pharmacy", category: "Health"),
        VendorCategoryRule(keyword: "clinic", category: "Health"),
        VendorCategoryRule(keyword: "hospital", category: "Health"),
        VendorCategoryRule(keyword: "medical", category: "Health")
    ]
}

struct ExpenseBudget: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var categories: [String]
    var monthlyAmount: Decimal
    var currencyCode: String
    var alertsEnabled: Bool
    var cycleStartDay: Int
    var cycleEndDay: Int

    init(
        id: UUID = UUID(),
        name: String = "",
        categories: [String],
        monthlyAmount: Decimal,
        currencyCode: String,
        alertsEnabled: Bool = true,
        cycleStartDay: Int = 1,
        cycleEndDay: Int = 28
    ) {
        self.id = id
        self.name = name
        self.categories = categories
        self.monthlyAmount = monthlyAmount
        self.currencyCode = currencyCode
        self.alertsEnabled = alertsEnabled
        self.cycleStartDay = min(max(cycleStartDay, 1), 28)
        self.cycleEndDay = min(max(cycleEndDay, 1), 28)
    }

    var displayName: String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty { return cleaned }
        if categories.count == 1 { return categories[0] }
        return "Monthly Budget"
    }

    func includes(category: String) -> Bool {
        categories.contains { $0.caseInsensitiveCompare(category) == .orderedSame }
    }

    func dateInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        let day = min(max(cycleStartDay, 1), 28)
        var components = calendar.dateComponents([.year, .month], from: date)
        components.day = day
        guard var start = calendar.date(from: components) else { return nil }
        if date < start {
            guard let previous = calendar.date(byAdding: .month, value: -1, to: start) else {
                return nil
            }
            start = previous
        }

        let endMonthOffset = cycleEndDay >= cycleStartDay ? 0 : 1
        guard let endMonth = calendar.date(byAdding: .month, value: endMonthOffset, to: start) else {
            return nil
        }
        var endComponents = calendar.dateComponents([.year, .month], from: endMonth)
        endComponents.day = min(max(cycleEndDay, 1), 28)
        guard let inclusiveEnd = calendar.date(from: endComponents),
              let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd) else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, categories, category, monthlyAmount, currencyCode, alertsEnabled
        case cycleStartDay, cycleEndDay
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let legacyCategory = try values.decodeIfPresent(String.self, forKey: .category)
        categories = try values.decodeIfPresent([String].self, forKey: .categories)
            ?? legacyCategory.map { [$0] }
            ?? []
        name = try values.decodeIfPresent(String.self, forKey: .name)
            ?? legacyCategory
            ?? ""
        monthlyAmount = try values.decodeIfPresent(Decimal.self, forKey: .monthlyAmount) ?? 0
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "QAR"
        alertsEnabled = try values.decodeIfPresent(Bool.self, forKey: .alertsEnabled) ?? true
        cycleStartDay = min(
            max(try values.decodeIfPresent(Int.self, forKey: .cycleStartDay) ?? 1, 1),
            28
        )
        cycleEndDay = min(
            max(try values.decodeIfPresent(Int.self, forKey: .cycleEndDay) ?? 28, 1),
            28
        )
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(categories, forKey: .categories)
        try values.encode(monthlyAmount, forKey: .monthlyAmount)
        try values.encode(currencyCode, forKey: .currencyCode)
        try values.encode(alertsEnabled, forKey: .alertsEnabled)
        try values.encode(cycleStartDay, forKey: .cycleStartDay)
        try values.encode(cycleEndDay, forKey: .cycleEndDay)
    }
}

enum FixedAssetStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case sold
    case disposed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return "Active"
        case .sold: return "Sold"
        case .disposed: return "Disposed"
        }
    }
}

enum FixedAssetDepreciationMethod: String, Codable, CaseIterable, Identifiable {
    case straightLineRate
    case straightLineLife
    case none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .straightLineRate: return "Straight Line %"
        case .straightLineLife: return "Straight Line Life"
        case .none: return "No Depreciation"
        }
    }
}

struct FixedAssetRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var assetNumber: String
    var name: String
    var category: String
    var currencyCode: String
    var linkedAccountID: UUID?
    var purchaseDate: Date
    var cost: Decimal
    var residualValue: Decimal
    var depreciationStartDate: Date
    var depreciationMethod: FixedAssetDepreciationMethod
    var annualDepreciationRate: Decimal
    var usefulLifeMonths: Int
    var openingAccumulatedDepreciation: Decimal
    var status: FixedAssetStatus
    var disposalDate: Date?
    var disposalProceeds: Decimal?
    var disposalReason: String
    var notes: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        assetNumber: String = "",
        name: String = "",
        category: String = "Furniture & Fixtures",
        currencyCode: String = "QAR",
        linkedAccountID: UUID? = nil,
        purchaseDate: Date = Date(),
        cost: Decimal = 0,
        residualValue: Decimal = 0,
        depreciationStartDate: Date = Date(),
        depreciationMethod: FixedAssetDepreciationMethod = .straightLineRate,
        annualDepreciationRate: Decimal = 15,
        usefulLifeMonths: Int = 60,
        openingAccumulatedDepreciation: Decimal = 0,
        status: FixedAssetStatus = .active,
        disposalDate: Date? = nil,
        disposalProceeds: Decimal? = nil,
        disposalReason: String = "",
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.assetNumber = assetNumber
        self.name = name
        self.category = category
        self.currencyCode = currencyCode
        self.linkedAccountID = linkedAccountID
        self.purchaseDate = purchaseDate
        self.cost = cost
        self.residualValue = residualValue
        self.depreciationStartDate = depreciationStartDate
        self.depreciationMethod = depreciationMethod
        self.annualDepreciationRate = annualDepreciationRate
        self.usefulLifeMonths = usefulLifeMonths
        self.openingAccumulatedDepreciation = openingAccumulatedDepreciation
        self.status = status
        self.disposalDate = disposalDate
        self.disposalProceeds = disposalProceeds
        self.disposalReason = disposalReason
        self.notes = notes
        self.createdAt = createdAt
    }

    static let defaultCategories = [
        "Furniture & Fixtures", "Computers & IT Equipment", "Office Equipment",
        "Motor Vehicles", "Machinery & Equipment", "Leasehold Improvements",
        "Buildings", "Right-of-Use Assets", "Other Fixed Assets"
    ]

    var depreciableAmount: Decimal { max(0, cost - max(0, residualValue)) }

    func accumulatedDepreciation(asOf requestedDate: Date, calendar: Calendar = .current) -> Decimal {
        let terminalDate: Date
        if status != .active, let disposalDate {
            terminalDate = min(requestedDate, disposalDate)
        } else {
            terminalDate = requestedDate
        }
        let opening = min(max(0, openingAccumulatedDepreciation), depreciableAmount)
        guard terminalDate >= depreciationStartDate, depreciationMethod != .none else { return opening }
        let startComponents = calendar.dateComponents([.year, .month], from: depreciationStartDate)
        let endComponents = calendar.dateComponents([.year, .month], from: terminalDate)
        guard let startMonth = calendar.date(from: startComponents),
              let endMonth = calendar.date(from: endComponents) else { return opening }
        let elapsed = max(0, calendar.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0)
        let depreciationFactor: Decimal
        if ERPAccountingEngine.isEnabled {
            let convention = ERPDepreciationConvention(
                rawValue: ERPStorage.string(ERPKey.fixedAssetDepreciationConvention, ERPDepreciationConvention.fullMonth.rawValue)
            ) ?? .fullMonth
            switch convention {
            case .fullMonth: depreciationFactor = Decimal(elapsed + 1)
            case .nextMonth: depreciationFactor = Decimal(elapsed)
            case .halfMonth: depreciationFactor = Decimal(elapsed) + Decimal(string: "0.5")!
            }
        } else {
            depreciationFactor = Decimal(elapsed + 1)
        }
        let monthly: Decimal
        switch depreciationMethod {
        case .straightLineRate:
            monthly = cost * max(0, annualDepreciationRate) / Decimal(100) / Decimal(12)
        case .straightLineLife:
            monthly = usefulLifeMonths > 0 ? depreciableAmount / Decimal(usefulLifeMonths) : 0
        case .none:
            monthly = 0
        }
        let calculated = min(depreciableAmount, opening + monthly * depreciationFactor)
        guard ERPAccountingEngine.isEnabled else { return calculated }
        return ERPAccountingEngine.round(
            calculated,
            scale: max(0, min(6, ERPStorage.int(ERPKey.fixedAssetDepreciationDecimals, 2)))
        )
    }

    func netBookValue(asOf date: Date) -> Decimal {
        max(0, cost - accumulatedDepreciation(asOf: date))
    }

    var disposalGainLoss: Decimal? {
        guard status != .active, let disposalDate else { return nil }
        return (disposalProceeds ?? 0) - netBookValue(asOf: disposalDate)
    }
}

enum FixedLiabilityStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case settled
    var id: String { rawValue }
    var title: String { self == .active ? "Active" : "Settled" }
}

struct FixedLiabilityRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var reference: String
    var name: String
    var category: String
    var lender: String
    var currencyCode: String
    var linkedAccountID: UUID?
    var startDate: Date
    var maturityDate: Date?
    var originalPrincipal: Decimal
    var annualInterestRate: Decimal
    var currentPortion: Decimal
    var status: FixedLiabilityStatus
    var settledDate: Date?
    var notes: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        reference: String = "",
        name: String = "",
        category: String = "Bank Loan",
        lender: String = "",
        currencyCode: String = "QAR",
        linkedAccountID: UUID? = nil,
        startDate: Date = Date(),
        maturityDate: Date? = nil,
        originalPrincipal: Decimal = 0,
        annualInterestRate: Decimal = 0,
        currentPortion: Decimal = 0,
        status: FixedLiabilityStatus = .active,
        settledDate: Date? = nil,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.reference = reference
        self.name = name
        self.category = category
        self.lender = lender
        self.currencyCode = currencyCode
        self.linkedAccountID = linkedAccountID
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.originalPrincipal = originalPrincipal
        self.annualInterestRate = annualInterestRate
        self.currentPortion = currentPortion
        self.status = status
        self.settledDate = settledDate
        self.notes = notes
        self.createdAt = createdAt
    }

    static let defaultCategories = [
        "Bank Loan", "Finance Lease / Lease Liability", "Vehicle Finance",
        "Related Party / Shareholder Loan", "Long-Term Payable", "Other Long-Term Liability"
    ]
}

struct LedgerSettings: Codable, Equatable {
    var currencyCode: String
    var vendorRules: [VendorCategoryRule]
    var defaultAccountID: UUID?
    var expenseBudgets: [ExpenseBudget]
    var customExpenseCategories: [String]
    var customIncomeCategories: [String]
    var hiddenExpenseCategories: [String]
    var hiddenIncomeCategories: [String]
    var expenseCategoryCodes: [String: String]
    var incomeCategoryCodes: [String: String]
    var chartOfAccountsMigrationVersion: Int
    var fixedAssetRecords: [FixedAssetRecord]
    var fixedAssetCategories: [String]
    var fixedLiabilityRecords: [FixedLiabilityRecord]
    var fixedLiabilityCategories: [String]

    init(
        currencyCode: String = "QAR",
        vendorRules: [VendorCategoryRule] = VendorCategoryRule.defaults,
        defaultAccountID: UUID? = nil,
        expenseBudgets: [ExpenseBudget] = [],
        customExpenseCategories: [String] = [],
        customIncomeCategories: [String] = [],
        hiddenExpenseCategories: [String] = [],
        hiddenIncomeCategories: [String] = [],
        expenseCategoryCodes: [String: String] = LedgerTransaction.defaultExpenseCategoryCodes,
        incomeCategoryCodes: [String: String] = LedgerTransaction.defaultIncomeCategoryCodes,
        chartOfAccountsMigrationVersion: Int = 0,
        fixedAssetRecords: [FixedAssetRecord] = [],
        fixedAssetCategories: [String] = FixedAssetRecord.defaultCategories,
        fixedLiabilityRecords: [FixedLiabilityRecord] = [],
        fixedLiabilityCategories: [String] = FixedLiabilityRecord.defaultCategories
    ) {
        self.currencyCode = currencyCode
        self.vendorRules = vendorRules
        self.defaultAccountID = defaultAccountID
        self.expenseBudgets = expenseBudgets
        self.customExpenseCategories = customExpenseCategories
        self.customIncomeCategories = customIncomeCategories
        self.hiddenExpenseCategories = hiddenExpenseCategories
        self.hiddenIncomeCategories = hiddenIncomeCategories
        self.expenseCategoryCodes = expenseCategoryCodes
        self.incomeCategoryCodes = incomeCategoryCodes
        self.chartOfAccountsMigrationVersion = chartOfAccountsMigrationVersion
        self.fixedAssetRecords = fixedAssetRecords
        self.fixedAssetCategories = fixedAssetCategories
        self.fixedLiabilityRecords = fixedLiabilityRecords
        self.fixedLiabilityCategories = fixedLiabilityCategories
    }

    private enum CodingKeys: String, CodingKey {
        case currencyCode
        case vendorRules
        case defaultAccountID
        case expenseBudgets
        case customExpenseCategories
        case customIncomeCategories
        case hiddenExpenseCategories
        case hiddenIncomeCategories
        case expenseCategoryCodes
        case incomeCategoryCodes
        case chartOfAccountsMigrationVersion
        case fixedAssetRecords
        case fixedAssetCategories
        case fixedLiabilityRecords
        case fixedLiabilityCategories
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try values.decodeIfPresent(String.self, forKey: .currencyCode) ?? "QAR"
        vendorRules = try values.decodeIfPresent([VendorCategoryRule].self, forKey: .vendorRules)
            ?? VendorCategoryRule.defaults
        defaultAccountID = try values.decodeIfPresent(UUID.self, forKey: .defaultAccountID)
        expenseBudgets = try values.decodeIfPresent([ExpenseBudget].self, forKey: .expenseBudgets) ?? []
        customExpenseCategories = try values.decodeIfPresent([String].self, forKey: .customExpenseCategories) ?? []
        customIncomeCategories = try values.decodeIfPresent([String].self, forKey: .customIncomeCategories) ?? []
        hiddenExpenseCategories = try values.decodeIfPresent([String].self, forKey: .hiddenExpenseCategories) ?? []
        hiddenIncomeCategories = try values.decodeIfPresent([String].self, forKey: .hiddenIncomeCategories) ?? []
        expenseCategoryCodes = try values.decodeIfPresent(
            [String: String].self,
            forKey: .expenseCategoryCodes
        ) ?? LedgerTransaction.defaultExpenseCategoryCodes
        incomeCategoryCodes = try values.decodeIfPresent(
            [String: String].self,
            forKey: .incomeCategoryCodes
        ) ?? LedgerTransaction.defaultIncomeCategoryCodes
        chartOfAccountsMigrationVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .chartOfAccountsMigrationVersion
        ) ?? 0
        fixedAssetRecords = try values.decodeIfPresent([FixedAssetRecord].self, forKey: .fixedAssetRecords) ?? []
        fixedAssetCategories = try values.decodeIfPresent([String].self, forKey: .fixedAssetCategories)
            ?? FixedAssetRecord.defaultCategories
        fixedLiabilityRecords = try values.decodeIfPresent([FixedLiabilityRecord].self, forKey: .fixedLiabilityRecords) ?? []
        fixedLiabilityCategories = try values.decodeIfPresent([String].self, forKey: .fixedLiabilityCategories)
            ?? FixedLiabilityRecord.defaultCategories
    }
}

struct LedgerData: Codable {
    var version: Int
    var transactions: [LedgerTransaction]
    var accounts: [LedgerAccount]
    var settings: LedgerSettings
    var fixedBudget: MonthlyFixedBudget

    init(
        version: Int = 5,
        transactions: [LedgerTransaction] = [],
        accounts: [LedgerAccount] = [LedgerAccount.legacyMain],
        settings: LedgerSettings = LedgerSettings(),
        fixedBudget: MonthlyFixedBudget = MonthlyFixedBudget()
    ) {
        self.version = version
        self.transactions = transactions
        self.accounts = accounts
        self.settings = settings
        self.fixedBudget = fixedBudget
        normalize()
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case transactions
        case accounts
        case settings
        case fixedBudget
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        transactions = try values.decodeIfPresent([LedgerTransaction].self, forKey: .transactions) ?? []
        accounts = try values.decodeIfPresent([LedgerAccount].self, forKey: .accounts) ?? []
        settings = try values.decodeIfPresent(LedgerSettings.self, forKey: .settings) ?? LedgerSettings()
        fixedBudget = try values.decodeIfPresent(MonthlyFixedBudget.self, forKey: .fixedBudget) ?? MonthlyFixedBudget()
        normalize()
    }

    mutating func normalize() {
        if accounts.isEmpty {
            accounts = [LedgerAccount.legacyMain]
        }
        let activeAccounts = accounts.filter { !$0.isArchived }
        let fallbackID = settings.defaultAccountID.flatMap { id in
            activeAccounts.contains(where: { $0.id == id }) ? id : nil
        } ?? activeAccounts.first?.id ?? accounts[0].id
        settings.defaultAccountID = fallbackID
        for index in transactions.indices where transactions[index].accountID == nil {
            transactions[index].accountID = fallbackID
        }
        for index in transactions.indices where transactions[index].vendor?.isEmpty != false {
            transactions[index].vendor = LedgerTransaction.vendorFromMessage(transactions[index].details)
        }
        applyApprovedChartOfAccountsIfNeeded()
        version = 5
    }

    private mutating func applyApprovedChartOfAccountsIfNeeded() {
        guard settings.chartOfAccountsMigrationVersion < 1 else { return }
        let approved: [UUID: (String, AccountNature)] = [
            UUID(uuidString: "EA37927C-FEF1-57A0-A0E8-85A6C3334D65")!: ("1010", .asset),
            UUID(uuidString: "94D9C8CB-A48E-5AF2-AC94-D371CF0FB87A")!: ("1020", .asset),
            UUID(uuidString: "BF808990-1A06-58F0-AA88-70EFA32B070E")!: ("1030", .asset),
            UUID(uuidString: "A16378B7-2D98-543B-AB77-3FC888257521")!: ("1040", .asset),
            UUID(uuidString: "1AE44D3F-1819-5D95-AE1D-572F72E6FA7A")!: ("1050", .asset),
            UUID(uuidString: "1547562A-85FD-58F0-A988-57B7AAF33D58")!: ("1060", .asset),
            UUID(uuidString: "49D947CC-0AD0-5E95-ACC6-CB71CF395179")!: ("1070", .asset),
            UUID(uuidString: "3B390900-F5AF-5233-A217-A416736E7927")!: ("1080", .asset),
            UUID(uuidString: "1860A963-09C9-5B37-A69B-F262C8FBA024")!: ("1090", .bank),
            UUID(uuidString: "07111CD1-8254-5C4D-A1D4-FDDF27D820CD")!: ("1100", .bank),
            UUID(uuidString: "E8027AC1-3E41-5174-A5DF-41DF2B5B90AD")!: ("1110", .bank),
            UUID(uuidString: "66A2CBBF-C2A5-582F-AE77-CFCB8568ED47")!: ("1120", .asset),
            UUID(uuidString: "C6E00292-58A8-5514-AC6E-ED767EAA6278")!: ("1130", .asset),
            UUID(uuidString: "BB424F54-779F-5E74-AA57-17C5DB5E730A")!: ("3010", .control),
            UUID(uuidString: "85424C31-C710-56D6-AEF0-CB905EDD572F")!: ("3020", .control),
            UUID(uuidString: "599CA7E4-9B3B-5F42-A3F7-154F5CA83BEB")!: ("2010", .loan),
            UUID(uuidString: "B5D443C6-A8FE-520B-A087-28AC9D74F855")!: ("2020", .loan),
            UUID(uuidString: "E4853ECB-D22A-54C5-AC82-D071CEFF8D2D")!: ("2030", .loan),
            UUID(uuidString: "36AEA784-B9AE-58BA-ACE9-B2DEF19CDD20")!: ("2040", .loan),
            UUID(uuidString: "518DC96E-D74F-576D-A222-087D3BD8A960")!: ("2050", .loan),
            UUID(uuidString: "0C1E9E1B-8D13-5E05-A0A4-878B9682499F")!: ("2060", .loan),
            UUID(uuidString: "9764922E-6AB6-5936-A686-24A127E6B4E0")!: ("2070", .loan),
            UUID(uuidString: "64B389AB-5782-5E9B-ABDE-125ADCB8B2B5")!: ("2080", .loan),
            UUID(uuidString: "F8AF715B-7D47-5C37-A4F3-7BE905E1AA22")!: ("2090", .loan),
            UUID(uuidString: "F08BD228-D21E-5C17-A02A-7D28632AE48A")!: ("2100", .loan),
            UUID(uuidString: "6F63BFAF-1EC2-52BD-AB84-4BEB58BB3A38")!: ("2110", .loan),
            UUID(uuidString: "FA78FD34-4F39-536D-A386-58164897E600")!: ("2120", .loan),
            UUID(uuidString: "151A683D-07BA-5991-A961-D9A090455F01")!: ("2130", .loan),
            UUID(uuidString: "165F0F18-D2DC-5F46-A65C-71C5E3210E10")!: ("2140", .loan),
            UUID(uuidString: "58B79BD6-DD56-50A8-A681-757EC4482E53")!: ("2150", .loan),
            UUID(uuidString: "9CE1D511-38F0-5A9E-AB39-9F0DF8D83E11")!: ("2160", .loan),
            UUID(uuidString: "E8B095C2-D86C-547E-ACA9-F07F9F088BBF")!: ("2170", .loan),
            UUID(uuidString: "DC7E4F55-1644-5CBA-ABED-CCACCB08795F")!: ("9010", .asset),
            UUID(uuidString: "30FEC30E-7CC4-5F1D-A0B2-4426571E5AE5")!: ("9020", .asset),
            UUID(uuidString: "31FB07F0-1D40-5CD9-AF6A-C8BF7CE150E1")!: ("9030", .asset)
        ]
        for index in accounts.indices {
            guard let entry = approved[accounts[index].id] else { continue }
            accounts[index].chartCode = entry.0
            accounts[index].nature = entry.1
        }
        settings.chartOfAccountsMigrationVersion = 1
    }
}

extension LedgerTransaction {
    static let expenseCategories = [
        "Restaurants & Cafes", "Grocery", "Shopping", "Transport", "Bills", "Fuel",
        "Health", "Home", "Family", "Entertainment", "Other"
    ]

    static let incomeCategories = [
        "Salary", "Business", "Refund", "Gift", "Investment", "Other"
    ]

    static let defaultIncomeCategoryCodes = [
        "Salary": "4010", "Business": "4020", "Refund": "4030",
        "Gift": "4040", "Investment": "4050", "Other": "4090"
    ]

    static let defaultExpenseCategoryCodes = [
        "Restaurants & Cafes": "5010", "Grocery": "5020", "Shopping": "5030",
        "Transport": "5040", "Bills": "5050", "Fuel": "5060", "Health": "5070",
        "Home": "5080", "Family": "5090", "Entertainment": "5100", "Other": "5990"
    ]
}
