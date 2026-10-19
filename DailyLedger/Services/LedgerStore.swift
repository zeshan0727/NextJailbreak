import Combine
import Foundation

private struct HistoricalBalanceCacheKey: Hashable {
    let accountIDs: [UUID]
    let cutoff: Date
}

@MainActor
final class LedgerStore: ObservableObject {
    @Published private(set) var transactions: [LedgerTransaction] = []
    @Published private(set) var accounts: [LedgerAccount] = []
    @Published private(set) var settings = LedgerSettings()
    @Published private(set) var fixedBudget = MonthlyFixedBudget()
    @Published var errorMessage: String?
    @Published private(set) var recordingCards: [LedgerTransaction] = []
    private(set) var runningBalances: [UUID: Decimal] = [:]
    private var runningBalancesByAccount: [UUID: [UUID: Decimal]] = [:]
    private var accountsByID: [UUID: LedgerAccount] = [:]
    private var currentBalances: [UUID: Decimal] = [:]
    private var budgetSnapshotsCache: [BudgetConsumptionSnapshot] = []
    private var budgetSnapshotDay = Date.distantPast
    private var categoriesCache: [TransactionType: [String]] = [:]
    private var totalsCache: [String: LedgerTotals] = [:]
    private var loanMovementCache: [String: [LoanNetMovement]] = [:]
    private var historicalBalanceCache: [HistoricalBalanceCacheKey: Decimal] = [:]
    private var hasLoaded = false

    init() {
        reload()
    }

    var currencyCode: String { settings.currencyCode }
    var defaultAccountID: UUID? { settings.defaultAccountID ?? accounts.first?.id }
    var activeAccounts: [LedgerAccount] { accounts.filter { !$0.isArchived } }

    func reload() {
        apply(LedgerDiskStore.shared.load())
    }

    private func apply(_ ledger: LedgerData) {
        let previousTransactions = transactions
        let previousIDs = Set(transactions.map(\.id))
        let ordered = ledger.transactions.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.createdAt < $1.createdAt
        }
        var accountBalances = Dictionary(uniqueKeysWithValues: ledger.accounts.map {
            ($0.id, $0.openingBalance)
        })
        var running: [UUID: Decimal] = [:]
        var accountRunning: [UUID: [UUID: Decimal]] = [:]
        for item in ordered {
            if let sourceID = item.accountID {
                switch item.type {
                case .income:
                    accountBalances[sourceID, default: 0] += item.amount
                case .expense, .transfer:
                    accountBalances[sourceID, default: 0] -= item.amount
                }
                running[item.id] = accountBalances[sourceID, default: 0]
                accountRunning[sourceID, default: [:]][item.id] = accountBalances[sourceID, default: 0]
            }
            if item.type == .transfer, let destinationID = item.destinationAccountID {
                accountBalances[destinationID, default: 0] += item.destinationAmount ?? item.amount
                accountRunning[destinationID, default: [:]][item.id] = accountBalances[destinationID, default: 0]
            }
        }
        accounts = ledger.accounts
        accountsByID = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })
        currentBalances = accountBalances
        historicalBalanceCache.removeAll(keepingCapacity: true)
        settings = ledger.settings
        fixedBudget = ledger.fixedBudget
        runningBalances = running
        runningBalancesByAccount = accountRunning
        transactions = Array(ordered.reversed())
        rebuildPerformanceCaches()
        if hasLoaded {
            let additions = transactions.filter { !previousIDs.contains($0.id) }
            if !additions.isEmpty {
                recordingCards.append(contentsOf: additions.prefix(8))
                checkBudgetThresholds(
                    additions: additions,
                    previousTransactions: previousTransactions,
                    budgets: ledger.settings.expenseBudgets,
                    accounts: ledger.accounts
                )
            }
        }
        hasLoaded = true
    }

    func add(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String = "",
        details: String,
        accountID: UUID? = nil
    ) {
        let cleanedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = LedgerTransaction(
            type: type,
            amount: amount,
            date: date,
            category: category,
            vendor: (cleanedVendor.nilIfEmpty ?? LedgerTransaction.vendorFromMessage(cleanedDetails)),
            details: cleanedDetails,
            accountID: accountID ?? defaultAccountID
        )
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.append(item)
                guard let vendor = item.vendor, !vendor.isEmpty,
                      !ledger.settings.vendorRules.contains(where: {
                          $0.keyword.caseInsensitiveCompare(vendor) == .orderedSame
                      }) else { return }
                ledger.settings.vendorRules.append(
                    VendorCategoryRule(keyword: vendor, category: item.category)
                )
            }
            apply(ledger)
        } catch {
            errorMessage = "The transaction could not be saved."
        }
    }

    func dismissRecordingCard(_ id: UUID) {
        recordingCards.removeAll { $0.id == id }
    }

    func split(
        _ transaction: LedgerTransaction,
        firstAccountID: UUID,
        firstAmount: Decimal,
        secondAccountID: UUID,
        secondAmount: Decimal
    ) {
        guard firstAccountID != secondAccountID, firstAmount > 0, secondAmount > 0,
              firstAmount + secondAmount == transaction.amount else {
            errorMessage = "Split amounts must equal the original amount and use two different accounts."
            return
        }
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard let index = ledger.transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
                ledger.transactions[index].accountID = firstAccountID
                ledger.transactions[index].amount = firstAmount
                ledger.transactions.append(LedgerTransaction(
                    type: transaction.type, amount: secondAmount, date: transaction.date,
                    category: transaction.category, vendor: transaction.vendor,
                    details: transaction.details, accountID: secondAccountID,
                    createdAt: transaction.createdAt
                ))
            }
            apply(ledger)
        } catch {
            errorMessage = "The transaction could not be split."
        }
    }

    func splitExpense(
        _ transaction: LedgerTransaction,
        firstCategory: String,
        firstAmount: Decimal,
        secondCategory: String,
        secondAmount: Decimal
    ) {
        guard transaction.type == .expense, firstAmount > 0, secondAmount > 0,
              firstAmount + secondAmount == transaction.amount,
              !firstCategory.isEmpty, !secondCategory.isEmpty else {
            errorMessage = "Expense split amounts must equal the original amount."
            return
        }
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard let index = ledger.transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
                ledger.transactions[index].category = firstCategory
                ledger.transactions[index].amount = firstAmount
                ledger.transactions.append(LedgerTransaction(
                    type: .expense, amount: secondAmount, date: transaction.date,
                    category: secondCategory, vendor: transaction.vendor,
                    details: transaction.details, accountID: transaction.accountID,
                    createdAt: transaction.createdAt
                ))
            }
            apply(ledger)
        } catch {
            errorMessage = "The expense could not be split."
        }
    }

    func addTransfer(
        from sourceID: UUID,
        to destinationID: UUID,
        amount: Decimal,
        destinationAmount: Decimal,
        date: Date,
        details: String
    ) {
        guard sourceID != destinationID else {
            errorMessage = "Choose two different accounts."
            return
        }
        let item = LedgerTransaction(
            type: .transfer,
            amount: amount,
            date: date,
            category: "Transfer",
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: sourceID,
            destinationAccountID: destinationID,
            destinationAmount: destinationAmount
        )
        do {
            apply(try LedgerDiskStore.shared.add(item))
        } catch {
            errorMessage = "The transfer could not be saved."
        }
    }

    func addAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be saved.") { ledger in
            guard !ledger.accounts.contains(where: { $0.id == account.id }) else { return }
            ledger.accounts.append(account)
            if ledger.settings.defaultAccountID == nil {
                ledger.settings.defaultAccountID = account.id
            }
        }
    }

    func updateAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be updated.") { ledger in
            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index] = account
        }
    }

    func saveChartCategory(type: TransactionType, originalName: String?, name: String, code: String) {
        guard type != .transfer else { return }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateLedger(failureMessage: "The category could not be saved.") { ledger in
            let original = originalName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let original, !original.isEmpty,
               original.caseInsensitiveCompare(cleaned) != .orderedSame {
                for index in ledger.transactions.indices
                where ledger.transactions[index].type == type &&
                    ledger.transactions[index].category.caseInsensitiveCompare(original) == .orderedSame {
                    ledger.transactions[index].category = cleaned
                }
                if type == .expense {
                    for index in ledger.settings.vendorRules.indices
                    where ledger.settings.vendorRules[index].category.caseInsensitiveCompare(original) == .orderedSame {
                        ledger.settings.vendorRules[index].category = cleaned
                    }
                    for budgetIndex in ledger.settings.expenseBudgets.indices {
                        for categoryIndex in ledger.settings.expenseBudgets[budgetIndex].categories.indices
                        where ledger.settings.expenseBudgets[budgetIndex].categories[categoryIndex]
                            .caseInsensitiveCompare(original) == .orderedSame {
                            ledger.settings.expenseBudgets[budgetIndex].categories[categoryIndex] = cleaned
                        }
                    }
                    Self.appendUnique(original, to: &ledger.settings.hiddenExpenseCategories)
                    ledger.settings.expenseCategoryCodes.removeValue(forKey: original)
                } else {
                    Self.appendUnique(original, to: &ledger.settings.hiddenIncomeCategories)
                    ledger.settings.incomeCategoryCodes.removeValue(forKey: original)
                }
            }
            if type == .expense {
                Self.appendUnique(cleaned, to: &ledger.settings.customExpenseCategories)
                ledger.settings.hiddenExpenseCategories.removeAll {
                    $0.caseInsensitiveCompare(cleaned) == .orderedSame
                }
                ledger.settings.expenseCategoryCodes[cleaned] = cleanedCode
            } else {
                Self.appendUnique(cleaned, to: &ledger.settings.customIncomeCategories)
                ledger.settings.hiddenIncomeCategories.removeAll {
                    $0.caseInsensitiveCompare(cleaned) == .orderedSame
                }
                ledger.settings.incomeCategoryCodes[cleaned] = cleanedCode
            }
        }
    }

    func deleteChartCategory(type: TransactionType, name: String) {
        guard type != .transfer else { return }
        let isUsed = transactions.contains {
            $0.type == type && $0.category.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !isUsed else {
            errorMessage = "This category is used by transactions. Rename it instead of deleting it."
            return
        }
        updateLedger(failureMessage: "The category could not be removed.") { ledger in
            if type == .expense {
                ledger.settings.customExpenseCategories.removeAll {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                }
                ledger.settings.expenseCategoryCodes.removeValue(forKey: name)
                Self.appendUnique(name, to: &ledger.settings.hiddenExpenseCategories)
            } else {
                ledger.settings.customIncomeCategories.removeAll {
                    $0.caseInsensitiveCompare(name) == .orderedSame
                }
                ledger.settings.incomeCategoryCodes.removeValue(forKey: name)
                Self.appendUnique(name, to: &ledger.settings.hiddenIncomeCategories)
            }
        }
    }

    func archiveAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be archived.") { ledger in
            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index].isArchived = true
            if ledger.settings.defaultAccountID == account.id {
                ledger.settings.defaultAccountID = ledger.accounts.first(where: { !$0.isArchived })?.id
            }
        }
    }

    func account(withID id: UUID?) -> LedgerAccount? {
        guard let id else { return nil }
        return accountsByID[id]
    }

    func balance(for account: LedgerAccount) -> Decimal {
        currentBalances[account.id] ?? account.openingBalance
    }

    /// Returns the combined closing balance immediately before `cutoff`.
    /// Passing nil uses the cached current balances and avoids scanning transactions.
    func combinedBalance(for accounts: [LedgerAccount], before cutoff: Date? = nil) -> Decimal {
        guard let cutoff else {
            return accounts.reduce(Decimal.zero) { $0 + balance(for: $1) }
        }

        let accountIDs = Set(accounts.map(\.id))
        let cacheKey = HistoricalBalanceCacheKey(
            accountIDs: accountIDs.sorted { $0.uuidString < $1.uuidString },
            cutoff: cutoff
        )
        if let cached = historicalBalanceCache[cacheKey] {
            return cached
        }
        var result = accounts.reduce(Decimal.zero) { $0 + $1.openingBalance }
        for transaction in transactions where transaction.date < cutoff {
            switch transaction.type {
            case .income:
                if transaction.accountID.map(accountIDs.contains) == true {
                    result += transaction.amount
                }
            case .expense:
                if transaction.accountID.map(accountIDs.contains) == true {
                    result -= transaction.amount
                }
            case .transfer:
                if transaction.accountID.map(accountIDs.contains) == true {
                    result -= transaction.amount
                }
                if transaction.destinationAccountID.map(accountIDs.contains) == true {
                    result += transaction.destinationAmount ?? transaction.amount
                }
            }
        }
        historicalBalanceCache[cacheKey] = result
        return result
    }

    func runningBalance(for transactionID: UUID, accountID: UUID?) -> Decimal? {
        guard let accountID else { return runningBalances[transactionID] }
        return runningBalancesByAccount[accountID]?[transactionID]
    }

    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        transaction.type == .income || isAmaraTransfer(transaction)
    }

    func reportIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        isAmaraTransfer(transaction)
            ? (transaction.destinationAmount ?? transaction.amount)
            : transaction.amount
    }

    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        isAmaraTransfer(transaction) ? transaction.destinationAccountID : transaction.accountID
    }

    private func isAmaraTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              let name = account(withID: transaction.accountID)?.name else { return false }
        return name.localizedCaseInsensitiveContains("amara")
    }

    func remainingBalance(accountIDs: Set<UUID>? = nil) -> Decimal {
        let selectedAccounts = activeAccounts.filter {
            $0.currencyCode == currencyCode && (accountIDs == nil || accountIDs?.contains($0.id) == true)
        }
        let ids = Set(selectedAccounts.map(\.id))
        var result = selectedAccounts.reduce(Decimal.zero) { $0 + $1.openingBalance }
        for item in transactions {
            switch item.type {
            case .income where item.accountID.map(ids.contains) == true:
                result += item.amount
            case .expense where item.accountID.map(ids.contains) == true:
                result -= item.amount
            case .transfer:
                if item.accountID.map(ids.contains) == true { result -= item.amount }
                if item.destinationAccountID.map(ids.contains) == true {
                    result += item.destinationAmount ?? item.amount
                }
            default:
                break
            }
        }
        return result
    }

    func delete(_ transaction: LedgerTransaction) {
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.removeAll { $0.id == transaction.id }
            }
            apply(ledger)
        } catch {
            errorMessage = "The transaction could not be deleted."
        }
    }

    func update(_ transaction: LedgerTransaction) {
        var found = false
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard let index = ledger.transactions.firstIndex(where: { $0.id == transaction.id }) else {
                    return
                }
                ledger.transactions[index] = transaction
                found = true
            }
            guard found else {
                errorMessage = "The original transaction could not be found."
                return
            }
            apply(ledger)
        } catch {
            errorMessage = "The transaction could not be updated."
        }
    }

    func updateCurrency(_ code: String) {
        guard code != settings.currencyCode else { return }
        updateLedger(failureMessage: "The currency could not be updated.") { ledger in
            ledger.settings.currencyCode = code
        }
    }

    func updateSMSAutoImport(_ enabled: Bool) {
        guard enabled != settings.smsAutoImportEnabled else { return }
        updateLedger(failureMessage: "The SMS auto-import setting could not be updated.") { ledger in
            ledger.settings.smsAutoImportEnabled = enabled
        }
    }

    func updateSMSPreferences(matchText: String, destinationAccountID: UUID?) {
        updateLedger(failureMessage: "The SMS import preferences could not be updated.") { ledger in
            ledger.settings.smsMatchText = matchText.trimmingCharacters(in: .whitespacesAndNewlines)
            ledger.settings.smsDestinationAccountID = destinationAccountID
        }
    }

    func requestSMSRescan() {
        updateLedger(failureMessage: "The SMS rescan could not be requested.") { ledger in
            ledger.settings.smsRescanRequestID += 1
        }
    }

    func saveVendorRule(_ rule: VendorCategoryRule) {
        updateLedger(failureMessage: "The vendor rule could not be saved.") { ledger in
            if let index = ledger.settings.vendorRules.firstIndex(where: { $0.id == rule.id }) {
                ledger.settings.vendorRules[index] = rule
            } else {
                ledger.settings.vendorRules.append(rule)
            }
        }
    }

    func learnVendorCategory(from transaction: LedgerTransaction, category: String) {
        guard let keyword = vendorLearningKeyword(for: transaction) else { return }
        updateLedger(failureMessage: "The vendor category could not be learned.") { ledger in
            if let index = ledger.settings.vendorRules.firstIndex(where: {
                $0.keyword.caseInsensitiveCompare(keyword) == .orderedSame
            }) {
                ledger.settings.vendorRules[index].category = category
            } else {
                ledger.settings.vendorRules.insert(
                    VendorCategoryRule(keyword: keyword, category: category),
                    at: 0
                )
            }
        }
    }

    private func vendorLearningKeyword(for transaction: LedgerTransaction) -> String? {
        var merchant = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if merchant.isEmpty {
            let pattern = #"\bat\s+(.+?)\s+at\s+\d{1,2}:\d{2}"#
            if let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = expression.firstMatch(
                    in: transaction.details,
                    range: NSRange(transaction.details.startIndex..., in: transaction.details)
               ),
               let range = Range(match.range(at: 1), in: transaction.details) {
                merchant = String(transaction.details[range])
            }
        }
        let words = merchant
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let ignored = Set(["al", "new", "the", "merchant", "store"])
        guard let keyword = words.first(where: {
            $0.count >= 3 && !ignored.contains($0.lowercased())
        }) else { return nil }
        return keyword
    }

    func deleteVendorRules(at offsets: IndexSet) {
        updateLedger(failureMessage: "The vendor rule could not be deleted.") { ledger in
            for index in offsets.sorted(by: >) where ledger.settings.vendorRules.indices.contains(index) {
                ledger.settings.vendorRules.remove(at: index)
            }
        }
    }

    func resetVendorRules() {
        updateLedger(failureMessage: "The vendor rules could not be reset.") { ledger in
            ledger.settings.vendorRules = VendorCategoryRule.defaults
        }
    }

    func saveBudget(_ budget: ExpenseBudget) {
        guard budget.monthlyAmount > 0,
              !budget.categories.isEmpty else {
            errorMessage = "Select at least one expense type and enter a budget amount greater than zero."
            return
        }
        updateLedger(failureMessage: "The budget could not be saved.") { ledger in
            var cleaned = budget
            cleaned.name = budget.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.categories = budget.categories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if let index = ledger.settings.expenseBudgets.firstIndex(where: { $0.id == budget.id }) {
                ledger.settings.expenseBudgets[index] = cleaned
            } else {
                ledger.settings.expenseBudgets.append(cleaned)
            }
            ledger.settings.expenseBudgets.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        if budget.alertsEnabled {
            BudgetNotificationService.requestAuthorization()
        }
    }

    func deleteBudgets(at offsets: IndexSet) {
        updateLedger(failureMessage: "The budget could not be deleted.") { ledger in
            for index in offsets.sorted(by: >)
            where ledger.settings.expenseBudgets.indices.contains(index) {
                ledger.settings.expenseBudgets.remove(at: index)
            }
        }
    }

    func monthlyBudgetSpent(_ budget: ExpenseBudget, containing date: Date = Date()) -> Decimal {
        budgetConsumptionSnapshots(containing: date)
            .first { $0.budget.id == budget.id }?
            .spent ?? 0
    }

    func budgetConsumptionSnapshots(
        containing date: Date = Date()
    ) -> [BudgetConsumptionSnapshot] {
        if Calendar.current.isDate(date, inSameDayAs: budgetSnapshotDay) {
            return budgetSnapshotsCache
        }
        return makeBudgetConsumptionSnapshots(containing: date)
    }

    private func makeBudgetConsumptionSnapshots(
        containing date: Date
    ) -> [BudgetConsumptionSnapshot] {
        let budgets = settings.expenseBudgets
        let intervals = Dictionary(uniqueKeysWithValues: budgets.compactMap { budget in
            budget.dateInterval(containing: date).map { (budget.id, $0) }
        })
        var candidates: [String: [UUID]] = [:]
        for budget in budgets {
            for category in budget.categories {
                candidates[budgetLookupKey(currency: budget.currencyCode, category: category), default: []]
                    .append(budget.id)
            }
        }
        var spentByBudget: [UUID: Decimal] = [:]
        for transaction in transactions where transaction.type == .expense {
            guard let currency = accountsByID[
                transaction.accountID ?? LedgerAccount.legacyMainID
            ]?.currencyCode else { continue }
            let key = budgetLookupKey(currency: currency, category: transaction.category)
            for budgetID in candidates[key] ?? [] {
                guard intervals[budgetID]?.contains(transaction.date) == true else { continue }
                spentByBudget[budgetID, default: 0] += transaction.amount
            }
        }
        let today = Calendar.current.startOfDay(for: date)
        return budgets.compactMap { budget in
            guard let interval = intervals[budget.id] else { return nil }
            let spent = spentByBudget[budget.id, default: 0]
            let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: interval.end)
                ?? interval.end
            let daysRemaining = max(
                Calendar.current.dateComponents([.day], from: today, to: inclusiveEnd).day ?? 0,
                0
            )
            return BudgetConsumptionSnapshot(
                budget: budget,
                interval: interval,
                spent: spent,
                daysRemaining: daysRemaining
            )
        }
    }

    func transactions(for snapshot: BudgetConsumptionSnapshot) -> [LedgerTransaction] {
        transactions.filter {
            $0.type == .expense &&
            snapshot.interval.contains($0.date) &&
            snapshot.budget.includes(category: $0.category) &&
            account(withID: $0.accountID)?.currencyCode == snapshot.budget.currencyCode
        }
    }

    func suggestedBudgetAmount(
        for budget: ExpenseBudget,
        monthlyIncome: Decimal
    ) -> Decimal {
        suggestedBudgetAmounts(
            monthlyIncome: monthlyIncome,
            incomeCurrencyCode: budget.currencyCode
        )[budget.id] ?? budget.monthlyAmount
    }

    func suggestedBudgetAmounts(
        monthlyIncome: Decimal,
        incomeCurrencyCode: String
    ) -> [UUID: Decimal] {
        let calendar = Calendar.current
        let currentMonth = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        guard let historyStart = calendar.date(byAdding: .month, value: -3, to: currentMonth) else {
            return Dictionary(uniqueKeysWithValues: settings.expenseBudgets.map {
                ($0.id, $0.monthlyAmount)
            })
        }
        var categoryHistory: [String: Decimal] = [:]
        for transaction in transactions where
            transaction.type == .expense &&
            transaction.date >= historyStart &&
            transaction.date < currentMonth {
            guard let currency = account(withID: transaction.accountID)?.currencyCode else { continue }
            categoryHistory[
                budgetLookupKey(currency: currency, category: transaction.category),
                default: 0
            ] += transaction.amount
        }
        let budgetCountByCurrency = Dictionary(grouping: settings.expenseBudgets, by: \.currencyCode)
            .mapValues { $0.count }
        return Dictionary(uniqueKeysWithValues: settings.expenseBudgets.map { budget in
            let historicalTotal = budget.categories.reduce(Decimal.zero) {
                $0 + categoryHistory[
                    budgetLookupKey(currency: budget.currencyCode, category: $1),
                    default: 0
                ]
            }
            let historicalAverage = historicalTotal / 3
            if historicalAverage > 0 {
                return (
                    budget.id,
                    roundedBudget(historicalAverage * Decimal(string: "0.90")!)
                )
            }
            let count = max(budgetCountByCurrency[budget.currencyCode, default: 1], 1)
            if monthlyIncome > 0 && budget.currencyCode == incomeCurrencyCode {
                return (
                    budget.id,
                    roundedBudget(
                        monthlyIncome * Decimal(string: "0.80")! / Decimal(count)
                    )
                )
            }
            return (budget.id, budget.monthlyAmount)
        })
    }

    private func roundedBudget(_ amount: Decimal) -> Decimal {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return max(rounded, 1)
    }

    private func budgetLookupKey(currency: String, category: String) -> String {
        let normalized = category
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        return "\(currency.uppercased())|\(normalized)"
    }

    private func checkBudgetThresholds(
        additions: [LedgerTransaction],
        previousTransactions: [LedgerTransaction],
        budgets: [ExpenseBudget],
        accounts: [LedgerAccount]
    ) {
        let accountCurrency = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.currencyCode) })
        for budget in budgets where budget.alertsEnabled && budget.monthlyAmount > 0 {
            guard let cycle = budget.dateInterval(containing: Date()) else { continue }
            let matches: (LedgerTransaction) -> Bool = { transaction in
                transaction.type == .expense &&
                cycle.contains(transaction.date) &&
                budget.includes(category: transaction.category) &&
                accountCurrency[transaction.accountID ?? LedgerAccount.legacyMainID] == budget.currencyCode
            }
            guard additions.contains(where: matches) else { continue }
            let before = previousTransactions.lazy.filter(matches)
                .reduce(Decimal.zero) { $0 + $1.amount }
            let after = before + additions.lazy.filter(matches)
                .reduce(Decimal.zero) { $0 + $1.amount }
            let threshold = budget.monthlyAmount * Decimal(string: "0.80")!
            if before < threshold && after >= threshold {
                BudgetNotificationService.notifyEightyPercent(budget: budget, spent: after)
            }
        }
    }

    func addMissingVendorRules() {
        updateLedger(failureMessage: "Vendor rules could not be updated.") { ledger in
            for transaction in ledger.transactions {
                guard let vendor = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !vendor.isEmpty,
                      !ledger.settings.vendorRules.contains(where: {
                          $0.keyword.caseInsensitiveCompare(vendor) == .orderedSame
                      }) else { continue }
                ledger.settings.vendorRules.append(
                    VendorCategoryRule(keyword: vendor, category: transaction.category)
                )
            }
            ledger.settings.vendorRules.sort {
                $0.keyword.localizedCaseInsensitiveCompare($1.keyword) == .orderedAscending
            }
        }
    }

    var uncategorizedTransactions: [LedgerTransaction] {
        let now = Date()
        return transactions.filter { isAutoCategorizationCandidate($0, now: now) }
    }

    @discardableResult
    func automaticallyCategorizeTransactions() -> CategorizationSummary {
        var categorized = 0
        var categorizedIDs: [UUID] = []
        let now = Date()
        updateLedger(failureMessage: "Transactions could not be categorized.") { ledger in
            let rules = (ledger.settings.vendorRules + VendorCategoryRule.defaults)
                .enumerated()
                .sorted { left, right in
                    if left.element.keyword.count != right.element.keyword.count {
                        return left.element.keyword.count > right.element.keyword.count
                    }
                    return left.offset < right.offset
                }
                .map(\.element)
            for index in ledger.transactions.indices {
                let transaction = ledger.transactions[index]
                guard isAutoCategorizationCandidate(transaction, now: now),
                      let category = suggestedCategory(for: transaction, rules: rules) else { continue }
                ledger.transactions[index].category = category
                categorized += 1
                categorizedIDs.append(transaction.id)
            }
        }
        recordingCards.append(contentsOf: transactions.filter { categorizedIDs.contains($0.id) })
        return CategorizationSummary(
            categorizedCount: categorized,
            reviewCount: uncategorizedTransactions.count
        )
    }

    func suggestedCategory(for transaction: LedgerTransaction) -> String? {
        suggestedCategory(for: transaction, rules: settings.vendorRules)
    }

    private func suggestedCategory(
        for transaction: LedgerTransaction,
        rules: [VendorCategoryRule]
    ) -> String? {
        let text = [transaction.vendor, transaction.details]
            .compactMap { $0 }
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        guard !text.isEmpty else { return nil }
        return rules.first { rule in
            let keyword = rule.keyword
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            return !keyword.isEmpty && text.contains(keyword)
        }?.category
    }

    private func isAutoCategorizationCandidate(
        _ transaction: LedgerTransaction,
        now: Date
    ) -> Bool {
        guard transaction.type != .transfer else { return false }
        let categoryMatches = transaction.category
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Z-iP-14PM-16.0") == .orderedSame
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: now)
            ?? now.addingTimeInterval(-30 * 24 * 60 * 60)
        return categoryMatches && transaction.date >= cutoff && transaction.date <= now
    }

    private func updateLedger(
        failureMessage: String,
        _ changes: (inout LedgerData) -> Void
    ) {
        do {
            apply(try LedgerDiskStore.shared.mutate(changes))
        } catch {
            errorMessage = failureMessage
        }
    }

    func importFile(at url: URL) throws -> ImportSummary {
        let incoming = try ImportExportCodec.decode(url: url)
        return try mergeImport(incoming)
    }

    func importData(_ data: Data) throws -> ImportSummary {
        let incoming = try ImportExportCodec.decode(data: data)
        return try mergeImport(incoming)
    }

    private func mergeImport(_ incoming: ImportPayload) throws -> ImportSummary {
        let oldLedger = LedgerDiskStore.shared.load()
        let ledger = try LedgerDiskStore.shared.merge(
            incoming.transactions,
            accounts: incoming.accounts,
            restoring: incoming.settings,
            fixedBudget: incoming.fixedBudget
        )
        apply(ledger)
        return ImportSummary(
            transactionCount: ledger.transactions.count - oldLedger.transactions.count,
            accountCount: ledger.accounts.count - oldLedger.accounts.count
        )
    }

    func saveFixedBudget(_ plan: MonthlyFixedBudget) {
        updateLedger(failureMessage: "Fixed budget could not be saved.") { ledger in
            ledger.fixedBudget = plan
        }
    }

    func syncBackupNow() {
        BackupSyncService.shared.syncNow(ledger: LedgerDiskStore.shared.load())
    }

    func restoreLatestICloudBackup() {
        do {
            let ledger = try BackupSyncService.shared.restoreLatestICloudBackup()
            try LedgerDiskStore.shared.save(ledger)
            apply(ledger)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func categories(for type: TransactionType) -> [String] {
        categoriesCache[type] ?? makeCategories(for: type)
    }

    func chartCode(for category: String, type: TransactionType) -> String {
        let codes = type == .expense
            ? settings.expenseCategoryCodes
            : settings.incomeCategoryCodes
        return codes.first {
            $0.key.caseInsensitiveCompare(category) == .orderedSame
        }?.value ?? ""
    }

    private func makeCategories(for type: TransactionType) -> [String] {
        let defaults = type == .expense
            ? LedgerTransaction.expenseCategories
            : LedgerTransaction.incomeCategories
        let custom = type == .expense
            ? settings.customExpenseCategories
            : settings.customIncomeCategories
        let hidden = type == .expense
            ? settings.hiddenExpenseCategories
            : settings.hiddenIncomeCategories
        let used = transactions.lazy
            .filter { $0.type == type }
            .map(\.category)
        var seen = Set<String>()
        return (defaults + custom + Array(used)).compactMap { item in
            let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = cleaned
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
            guard !cleaned.isEmpty,
                  !hidden.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame }),
                  seen.insert(key).inserted else { return nil }
            return cleaned
        }
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        values.append(value)
    }

    private func rebuildPerformanceCaches() {
        totalsCache.removeAll(keepingCapacity: true)
        loanMovementCache.removeAll(keepingCapacity: true)
        categoriesCache = [
            .income: makeCategories(for: .income),
            .expense: makeCategories(for: .expense)
        ]
        let now = Date()
        budgetSnapshotDay = Calendar.current.startOfDay(for: now)
        budgetSnapshotsCache = makeBudgetConsumptionSnapshots(containing: now)
    }

    private func reportCacheKey(
        interval: DateInterval,
        accountIDs: Set<UUID>?
    ) -> String {
        let accountPart = accountIDs?
            .map(\.uuidString)
            .sorted()
            .joined(separator: ",") ?? "all"
        return [
            String(interval.start.timeIntervalSinceReferenceDate),
            String(interval.end.timeIntervalSinceReferenceDate),
            currencyCode.uppercased(),
            accountPart
        ].joined(separator: "|")
    }

    func totals(in interval: DateInterval, accountIDs: Set<UUID>? = nil) -> LedgerTotals {
        let cacheKey = reportCacheKey(interval: interval, accountIDs: accountIDs)
        if let cached = totalsCache[cacheKey] {
            return cached
        }
        let selected = transactions.filter {
            interval.contains($0.date) &&
            accountsByID[$0.accountID ?? LedgerAccount.legacyMainID]?.currencyCode == currencyCode &&
            (accountIDs == nil || accountIDs?.contains($0.accountID ?? LedgerAccount.legacyMainID) == true)
        }
        let income = transactions.lazy
            .filter {
                guard interval.contains($0.date), self.isReportIncome($0) else { return false }
                let incomeAccountID = self.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID
                return self.accountsByID[incomeAccountID]?.currencyCode == self.currencyCode &&
                    (accountIDs == nil || accountIDs?.contains(incomeAccountID) == true)
            }
            .reduce(Decimal.zero) { $0 + self.reportIncomeAmount($1) }
        let expense = selected
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let loan = selected
            .filter {
                $0.type == .transfer &&
                accountsByID[$0.destinationAccountID ?? LedgerAccount.legacyMainID]?.group == .payments
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let transfer = selected
            .filter { $0.type == .transfer }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let result = LedgerTotals(
            income: income,
            expense: expense,
            loan: loan,
            transfer: transfer,
            count: selected.count
        )
        totalsCache[cacheKey] = result
        return result
    }

    func loanNetMovements(
        in interval: DateInterval,
        accountIDs: Set<UUID>? = nil
    ) -> [LoanNetMovement] {
        let cacheKey = reportCacheKey(interval: interval, accountIDs: accountIDs)
        if let cached = loanMovementCache[cacheKey] {
            return cached
        }
        let loanAccountIDs = Set(accounts.filter {
            $0.group == .payments || $0.nature == .loan
        }.map(\.id))
        var increases: [String: Decimal] = [:]
        var decreases: [String: Decimal] = [:]

        for transaction in transactions where interval.contains(transaction.date) {
            if let sourceID = transaction.accountID,
               loanAccountIDs.contains(sourceID),
               accountIDs == nil || accountIDs?.contains(sourceID) == true,
               transaction.type == .expense || transaction.type == .transfer,
               let source = accountsByID[sourceID] {
                increases[source.currencyCode, default: 0] += transaction.amount
            }
            if transaction.type == .transfer,
               let destinationID = transaction.destinationAccountID,
               loanAccountIDs.contains(destinationID),
               accountIDs == nil || accountIDs?.contains(destinationID) == true,
               let destination = accountsByID[destinationID] {
                decreases[destination.currencyCode, default: 0] +=
                    transaction.destinationAmount ?? transaction.amount
            }
        }

        let currencies = Set<String>(increases.keys).union(Set<String>(decreases.keys))
        let result: [LoanNetMovement] = currencies.compactMap { currency -> LoanNetMovement? in
            let net = increases[currency, default: 0] - decreases[currency, default: 0]
            guard net != 0 else { return nil }
            return LoanNetMovement(currencyCode: currency, netAmount: net)
        }.sorted { $0.currencyCode < $1.currencyCode }
        loanMovementCache[cacheKey] = result
        return result
    }
}

struct ImportSummary {
    let transactionCount: Int
    let accountCount: Int
}

struct CategorizationSummary {
    let categorizedCount: Int
    let reviewCount: Int
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct LedgerTotals {
    let income: Decimal
    let expense: Decimal
    let loan: Decimal
    let transfer: Decimal
    let count: Int
    var balance: Decimal { income - expense - loan }
}

struct LoanNetMovement: Identifiable {
    var id: String { currencyCode }
    let currencyCode: String
    let netAmount: Decimal

    var title: String {
        netAmount > 0 ? "Loan increased" : "Loan decreased"
    }
}

struct BudgetConsumptionSnapshot: Identifiable, Equatable {
    var id: UUID { budget.id }
    let budget: ExpenseBudget
    let interval: DateInterval
    let spent: Decimal
    let daysRemaining: Int

    var remaining: Decimal { budget.monthlyAmount - spent }
    var progress: Double {
        guard budget.monthlyAmount > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / budget.monthlyAmount).doubleValue
    }
}
