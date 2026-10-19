import Combine
import Foundation

private struct HistoricalBalanceCacheKey: Hashable {
    let accountIDs: [UUID]
    let cutoff: Date
}

struct FixedLiabilityLedgerSnapshot {
    let originalPrincipal: Decimal
    let increases: Decimal
    let repayments: Decimal
    let outstanding: Decimal
    let status: FixedLiabilityStatus
    let settledDate: Date?

    var repaymentProgress: Double {
        let total = originalPrincipal + increases
        guard total > 0 else { return status == .settled ? 1 : 0 }
        let ratio = NSDecimalNumber(decimal: min(total, repayments) / total).doubleValue
        return min(max(ratio, 0), 1)
    }
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

    private func requireOpenPeriod(_ date: Date, action: String) -> Bool {
        guard !AccountingPeriodLock.isLocked(date) else {
            errorMessage = AccountingPeriodLock.blockedMessage(action: action, date: date)
            return false
        }
        return true
    }
    var activeAccounts: [LedgerAccount] { accounts.filter { !$0.isArchived } }
    var fixedAssetRecords: [FixedAssetRecord] { settings.fixedAssetRecords }
    var fixedLiabilityRecords: [FixedLiabilityRecord] { settings.fixedLiabilityRecords }
    var fixedAssetCategories: [String] { settings.fixedAssetCategories }
    var fixedLiabilityCategories: [String] { settings.fixedLiabilityCategories }

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
        let ledgerAccountsByID = Dictionary(uniqueKeysWithValues: ledger.accounts.map { ($0.id, $0) })

        func legacyTransferDestinationAmount(_ item: LedgerTransaction) -> Decimal {
            if let stored = item.destinationAmount { return stored }
            guard item.type == .transfer,
                  let sourceID = item.accountID,
                  let destinationID = item.destinationAccountID,
                  let source = ledgerAccountsByID[sourceID],
                  let destination = ledgerAccountsByID[destinationID] else { return item.amount }
            let from = source.currencyCode.uppercased()
            let to = destination.currencyCode.uppercased()
            if from == to { return item.amount }
            let qarToPkr = Decimal(string: "77")!
            let usdToQar = Decimal(string: "3.65")!
            let usdToPkr = qarToPkr * usdToQar
            let rate: Decimal?
            switch (from, to) {
            case ("QAR", "PKR"): rate = qarToPkr
            case ("PKR", "QAR"): rate = Decimal(1) / qarToPkr
            case ("USD", "QAR"): rate = usdToQar
            case ("QAR", "USD"): rate = Decimal(1) / usdToQar
            case ("USD", "PKR"): rate = usdToPkr
            case ("PKR", "USD"): rate = Decimal(1) / usdToPkr
            default: rate = nil
            }
            guard let rate else { return item.amount }
            var raw = item.amount * rate
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &raw, 2, .plain)
            return rounded
        }

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
                accountBalances[destinationID, default: 0] += legacyTransferDestinationAmount(item)
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

    @discardableResult
    func add(
        type: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String = "",
        details: String,
        accountID: UUID? = nil,
        dimensions: [ERPTransactionDimension]? = nil
    ) -> Bool {
        guard requireOpenPeriod(date, action: "record") else { return false }
        let cleanedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAccountID = accountID ?? defaultAccountID
        let normalizedAmount = ERPAccountingEngine.postingAmount(amount)
        if let error = erpPostingError(
            type: type,
            amount: normalizedAmount,
            date: date,
            category: category,
            vendor: cleanedVendor.nilIfEmpty,
            details: cleanedDetails,
            accountID: resolvedAccountID,
            dimensions: dimensions
        ) {
            errorMessage = error
            return false
        }
        let item = LedgerTransaction(
            type: type,
            amount: normalizedAmount,
            date: date,
            category: category,
            vendor: (cleanedVendor.nilIfEmpty ?? LedgerTransaction.vendorFromMessage(cleanedDetails)),
            details: cleanedDetails,
            accountID: resolvedAccountID,
            dimensions: dimensions
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
            return true
        } catch {
            errorMessage = "The transaction could not be saved."
            return false
        }
    }

    func refundedAmount(for transaction: LedgerTransaction) -> Decimal {
        transactions.reduce(Decimal.zero) { total, item in
            item.refundOfTransactionID == transaction.id ? total + item.amount : total
        }
    }

    func refundableAmount(for transaction: LedgerTransaction) -> Decimal {
        max(Decimal.zero, transaction.amount - refundedAmount(for: transaction))
    }

    @discardableResult
    func addRefund(
        for transaction: LedgerTransaction,
        amount: Decimal,
        date: Date,
        accountID: UUID,
        details: String
    ) -> Bool {
        guard requireOpenPeriod(date, action: "record a refund for") else { return false }
        guard transaction.type != .transfer, transaction.refundOfTransactionID == nil else {
            errorMessage = "This transaction cannot be refunded."
            return false
        }
        let remaining = refundableAmount(for: transaction)
        guard amount > 0, amount <= remaining else {
            errorMessage = "Refund amount must be greater than zero and no more than the remaining refundable amount."
            return false
        }
        guard let refundAccount = account(withID: accountID),
              !refundAccount.isArchived || refundAccount.id == transaction.accountID else {
            errorMessage = "Choose an available refund account."
            return false
        }
        let originalCurrency = account(withID: transaction.accountID)?.currencyCode ?? currencyCode
        guard refundAccount.currencyCode == originalCurrency else {
            errorMessage = "The refund account must use the same currency as the original transaction."
            return false
        }

        let reverseType: TransactionType = transaction.type == .expense ? .income : .expense
        let cleanedNote = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalLabel: String
        if let vendor = transaction.vendor, !vendor.isEmpty {
            originalLabel = vendor
        } else if !transaction.details.isEmpty {
            originalLabel = transaction.details
        } else {
            originalLabel = transaction.category
        }
        let refundDetails = cleanedNote.isEmpty
            ? "Refund of \(originalLabel)"
            : "Refund of \(originalLabel) · \(cleanedNote)"
        let refund = LedgerTransaction(
            type: reverseType,
            amount: amount,
            date: date,
            category: transaction.category,
            vendor: transaction.vendor,
            details: refundDetails,
            accountID: accountID,
            dimensions: transaction.dimensions,
            refundOfTransactionID: transaction.id
        )

        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.append(refund)
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The refund could not be recorded."
            return false
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
        guard requireOpenPeriod(transaction.date, action: "split") else { return }
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
                    dimensions: transaction.dimensions,
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
        guard requireOpenPeriod(transaction.date, action: "split") else { return }
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
                    dimensions: transaction.dimensions,
                    createdAt: transaction.createdAt
                ))
            }
            apply(ledger)
        } catch {
            errorMessage = "The expense could not be split."
        }
    }

    @discardableResult
    func addTransfer(
        from sourceID: UUID,
        to destinationID: UUID,
        amount: Decimal,
        destinationAmount: Decimal,
        date: Date,
        details: String,
        dimensions: [ERPTransactionDimension]? = nil
    ) -> Bool {
        guard requireOpenPeriod(date, action: "record") else { return false }
        guard sourceID != destinationID else {
            errorMessage = "Choose two different accounts."
            return false
        }
        let normalizedAmount = ERPAccountingEngine.postingAmount(amount)
        let cleanedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        var normalizedDestination = ERPAccountingEngine.postingAmount(destinationAmount)
        if ERPAccountingEngine.isEnabled,
           ERPStorage.bool(ERPKey.transferUseConfiguredRate, true),
           let source = account(withID: sourceID),
           let destination = account(withID: destinationID) {
            if source.currencyCode.caseInsensitiveCompare(destination.currencyCode) == .orderedSame {
                normalizedDestination = normalizedAmount
            } else if let rate = ERPAccountingEngine.rate(
                from: source.currencyCode,
                to: destination.currencyCode,
                on: date
            ) {
                normalizedDestination = ERPAccountingEngine.round(normalizedAmount * rate)
            }
        }
        if let error = erpPostingError(
            type: .transfer,
            amount: normalizedAmount,
            date: date,
            category: "Transfer",
            vendor: nil,
            details: cleanedDetails,
            accountID: sourceID,
            destinationAccountID: destinationID,
            destinationAmount: normalizedDestination,
            dimensions: dimensions
        ) {
            errorMessage = error
            return false
        }
        let item = LedgerTransaction(
            type: .transfer,
            amount: normalizedAmount,
            date: date,
            category: "Transfer",
            details: cleanedDetails,
            accountID: sourceID,
            destinationAccountID: destinationID,
            destinationAmount: normalizedDestination,
            dimensions: dimensions
        )
        do {
            apply(try LedgerDiskStore.shared.add(item))
            return true
        } catch {
            errorMessage = "The transfer could not be saved."
            return false
        }
    }

    func smsDraftCategory(for draft: SMSImportDraft) -> String {
        if draft.transactionType == .transfer { return "Transfer" }
        if draft.kind == "cashback" || draft.kind == "reversal" { return "Refund" }

        let vendorKey = normalizedSMSVendor(draft.cleanedVendor)
        if !vendorKey.isEmpty,
           let previous = transactions.first(where: {
               $0.type == draft.transactionType &&
               normalizedSMSVendor($0.vendor ?? "") == vendorKey &&
               !$0.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
           }) {
            return previous.category
        }

        guard let sourceText = SMSImportConsoleService.loadConfiguration().cardAccountIDs[draft.cardEnding],
              let sourceID = UUID(uuidString: sourceText) else {
            return "Other"
        }
        let probe = LedgerTransaction(
            id: draft.id,
            type: draft.transactionType,
            amount: draft.amount,
            date: draft.date,
            category: "Other",
            vendor: draft.cleanedVendor,
            details: draft.cleanedDescription,
            accountID: sourceID
        )
        return suggestedCategory(for: probe) ?? "Other"
    }

    private func normalizedSMSVendor(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func approveReviewedSMSDraft(
        _ draft: SMSImportDraft,
        transactionType: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String,
        details: String,
        accountID: UUID,
        destinationAccountID: UUID?
    ) -> Bool {
        guard requireOpenPeriod(date, action: "approve") else { return false }
        if transactions.contains(where: { $0.id == draft.id }) { return true }
        guard amount > 0 else {
            errorMessage = "Enter an amount greater than zero."
            return false
        }
        guard let sourceAccount = accountsByID[accountID] else {
            errorMessage = "Choose a valid account."
            return false
        }

        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDetails.isEmpty else {
            errorMessage = "Description cannot be empty."
            return false
        }

        let item: LedgerTransaction
        if transactionType == .transfer {
            guard let destinationAccountID,
                  let destinationAccount = accountsByID[destinationAccountID],
                  destinationAccountID != accountID else {
                errorMessage = "Choose different From and To accounts for the transfer."
                return false
            }
            guard sourceAccount.currencyCode == destinationAccount.currencyCode else {
                errorMessage = "For SMS draft transfers, choose From and To accounts with the same currency."
                return false
            }
            item = LedgerTransaction(
                id: draft.id,
                type: .transfer,
                amount: amount,
                date: date,
                category: cleanCategory.isEmpty ? "Transfer" : cleanCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: accountID,
                destinationAccountID: destinationAccountID,
                destinationAmount: amount
            )
        } else {
            item = LedgerTransaction(
                id: draft.id,
                type: transactionType,
                amount: amount,
                date: date,
                category: cleanCategory.isEmpty ? "Other" : cleanCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: accountID
            )
        }

        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard !ledger.transactions.contains(where: { $0.id == item.id }) else { return }
                ledger.transactions.append(item)
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The reviewed SMS draft could not be recorded."
            return false
        }
    }

    @discardableResult
    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
        guard requireOpenPeriod(draft.date, action: "approve") else { return false }
        if transactions.contains(where: { $0.id == draft.id }) { return true }
        guard let sourceText = configuration.cardAccountIDs[draft.cardEnding],
              let sourceID = UUID(uuidString: sourceText),
              accountsByID[sourceID] != nil else {
            errorMessage = "Map card **\(draft.cardEnding) to an account before approval."
            return false
        }

        let cleanVendor = draft.cleanedVendor
        let cleanDetails = draft.cleanedDescription
        guard !cleanDetails.isEmpty else {
            errorMessage = "The original SMS text could not be decoded safely. Reject this draft and scan again after updating the daemon."
            return false
        }
        let resolvedCategory = smsDraftCategory(for: draft)

        let item: LedgerTransaction
        switch draft.kind {
        case "withdrawal", "billPayment":
            let destinationText = draft.kind == "withdrawal"
                ? configuration.cashAccountID
                : (nil as String?)
            guard let destinationText,
                  let destinationID = UUID(uuidString: destinationText),
                  accountsByID[destinationID] != nil,
                  destinationID != sourceID else {
                errorMessage = draft.kind == "withdrawal"
                    ? "Choose a valid Cash destination account."
                    : "Choose a valid Loan Payment destination account."
                return false
            }
            item = LedgerTransaction(
                id: draft.id,
                type: .transfer,
                amount: draft.amount,
                date: draft.date,
                category: "Transfer",
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: sourceID,
                destinationAccountID: destinationID,
                destinationAmount: draft.amount
            )
        case "cashback":
            item = LedgerTransaction(
                id: draft.id,
                type: .income,
                amount: draft.amount,
                date: draft.date,
                category: resolvedCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: sourceID
            )
        case "income":
            item = LedgerTransaction(
                id: draft.id,
                type: .income,
                amount: draft.amount,
                date: draft.date,
                category: resolvedCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: sourceID
            )
        default:
            let probe = LedgerTransaction(
                id: draft.id,
                type: .expense,
                amount: draft.amount,
                date: draft.date,
                category: "Other",
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: sourceID
            )
            item = LedgerTransaction(
                id: draft.id,
                type: .expense,
                amount: draft.amount,
                date: draft.date,
                category: resolvedCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: sourceID
            )
        }

        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard !ledger.transactions.contains(where: { $0.id == item.id }) else { return }
                ledger.transactions.append(item)
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The approved SMS draft could not be recorded."
            return false
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


    func saveFixedAssetRecord(_ record: FixedAssetRecord) {
        updateLedger(failureMessage: "The fixed asset could not be saved.") { ledger in
            var cleaned = record
            cleaned.assetNumber = record.assetNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.category = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.disposalReason = record.disposalReason.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.notes = record.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = ledger.settings.fixedAssetRecords.firstIndex(where: { $0.id == record.id }) {
                ledger.settings.fixedAssetRecords[index] = cleaned
            } else {
                ledger.settings.fixedAssetRecords.append(cleaned)
            }
            if !cleaned.category.isEmpty,
               !ledger.settings.fixedAssetCategories.contains(where: { $0.caseInsensitiveCompare(cleaned.category) == .orderedSame }) {
                ledger.settings.fixedAssetCategories.append(cleaned.category)
                ledger.settings.fixedAssetCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            if let linked = cleaned.linkedAccountID,
               let index = ledger.accounts.firstIndex(where: { $0.id == linked }) {
                ledger.accounts[index].nature = .fixedAsset
            }
        }
    }

    func deleteFixedAssetRecord(_ id: UUID) {
        updateLedger(failureMessage: "The fixed asset could not be removed.") { ledger in
            ledger.settings.fixedAssetRecords.removeAll { $0.id == id }
        }
    }

    func saveFixedLiabilityRecord(_ record: FixedLiabilityRecord) {
        updateLedger(failureMessage: "The fixed liability could not be saved.") { ledger in
            var cleaned = record
            cleaned.reference = record.reference.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.category = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.lender = record.lender.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.notes = record.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = ledger.settings.fixedLiabilityRecords.firstIndex(where: { $0.id == record.id }) {
                ledger.settings.fixedLiabilityRecords[index] = cleaned
            } else {
                ledger.settings.fixedLiabilityRecords.append(cleaned)
            }
            if !cleaned.category.isEmpty,
               !ledger.settings.fixedLiabilityCategories.contains(where: { $0.caseInsensitiveCompare(cleaned.category) == .orderedSame }) {
                ledger.settings.fixedLiabilityCategories.append(cleaned.category)
                ledger.settings.fixedLiabilityCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            if let linked = cleaned.linkedAccountID,
               let index = ledger.accounts.firstIndex(where: { $0.id == linked }) {
                ledger.accounts[index].nature = .fixedLiability
            }
        }
    }

    func deleteFixedLiabilityRecord(_ id: UUID) {
        updateLedger(failureMessage: "The fixed liability could not be removed.") { ledger in
            ledger.settings.fixedLiabilityRecords.removeAll { $0.id == id }
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
            if ledger.accounts[index].parentAccountID == nil {
                for childIndex in ledger.accounts.indices
                where ledger.accounts[childIndex].parentAccountID == account.id {
                    ledger.accounts[childIndex].isArchived = true
                }
            }
            if ledger.settings.defaultAccountID == account.id {
                ledger.settings.defaultAccountID = ledger.accounts.first(where: { !$0.isArchived })?.id
            }
        }
    }

    func account(withID id: UUID?) -> LedgerAccount? {
        guard let id else { return nil }
        return accountsByID[id]
    }


    func isFinancialLiabilityAccount(_ account: LedgerAccount?) -> Bool {
        guard let nature = account?.nature else { return false }
        return nature == .loan || nature == .fixedLiability
    }

    func fixedLiabilitySuggestedPrincipal(for account: LedgerAccount, asOf date: Date = Date()) -> Decimal {
        var drawdowns: Decimal = 0
        for transaction in transactions where transaction.date <= date && transaction.type == .transfer {
            guard transaction.accountID == account.id else { continue }
            let destination = self.account(withID: transaction.destinationAccountID)
            if isFinancialLiabilityAccount(destination) { continue }
            drawdowns += transaction.amount
        }
        let opening = abs(account.openingBalance)
        let current = abs(balance(for: account))
        return max(opening, max(drawdowns, current))
    }

    func fixedLiabilitySnapshot(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> FixedLiabilityLedgerSnapshot {
        let tolerance: Decimal = 0.01

        guard let liabilityID = record.linkedAccountID,
              let linkedAccount = account(withID: liabilityID) else {
            // Unlinked/manual register records keep their manually entered principal.
            let manualPrincipal = max(0, record.originalPrincipal)
            let manualOutstanding = record.status == .settled ? Decimal.zero : manualPrincipal
            return FixedLiabilityLedgerSnapshot(
                originalPrincipal: manualPrincipal,
                increases: 0,
                repayments: record.status == .settled ? manualPrincipal : 0,
                outstanding: manualOutstanding,
                status: record.status,
                settledDate: record.settledDate
            )
        }

        // For a linked liability the ledger is the only source of truth.
        // Do NOT add record.originalPrincipal on top of the account movements.
        let openingLiability: Decimal = linkedAccount.createdAt <= requestedDate
            ? abs(linkedAccount.openingBalance)
            : 0

        var increases: Decimal = 0
        var repayments: Decimal = 0
        var lastRepaymentDate: Date?

        for transaction in transactions where transaction.date <= requestedDate && transaction.type == .transfer {
            if transaction.accountID == liabilityID {
                let destination = account(withID: transaction.destinationAccountID)
                if isFinancialLiabilityAccount(destination) { continue }
                // Liability -> Bank/other account = loan drawdown / liability increase.
                increases += transaction.amount
            } else if transaction.destinationAccountID == liabilityID {
                let source = account(withID: transaction.accountID)
                if isFinancialLiabilityAccount(source) { continue }
                // Bank/other account -> Liability = installment / repayment.
                repayments += effectiveDestinationAmount(transaction)
                if lastRepaymentDate == nil || transaction.date > lastRepaymentDate! {
                    lastRepaymentDate = transaction.date
                }
            }
        }

        let totalLoanRecorded = openingLiability + increases
        let outstanding = max(0, totalLoanRecorded - repayments)
        let automaticallySettled = totalLoanRecorded > 0 && outstanding <= tolerance
        return FixedLiabilityLedgerSnapshot(
            originalPrincipal: openingLiability,
            increases: increases,
            repayments: repayments,
            outstanding: outstanding,
            status: automaticallySettled ? .settled : .active,
            settledDate: automaticallySettled ? (lastRepaymentDate ?? record.settledDate) : nil
        )
    }

    func fixedLiabilityRepaymentTransactions(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> [LedgerTransaction] {
        guard let liabilityID = record.linkedAccountID else { return [] }
        return transactions.filter { transaction in
            guard transaction.type == .transfer,
                  transaction.date <= requestedDate,
                  transaction.destinationAccountID == liabilityID else { return false }
            return !isFinancialLiabilityAccount(account(withID: transaction.accountID))
        }.sorted { $0.date > $1.date }
    }

    func fixedLiabilityIncreaseTransactions(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> [LedgerTransaction] {
        guard let liabilityID = record.linkedAccountID else { return [] }
        return transactions.filter { transaction in
            guard transaction.type == .transfer,
                  transaction.date <= requestedDate,
                  transaction.accountID == liabilityID else { return false }
            return !isFinancialLiabilityAccount(account(withID: transaction.destinationAccountID))
        }.sorted { $0.date > $1.date }
    }


    func fixedLiabilityAllTransactions(
        _ record: FixedLiabilityRecord,
        asOf requestedDate: Date = Date()
    ) -> [LedgerTransaction] {
        let combined = fixedLiabilityIncreaseTransactions(record, asOf: requestedDate)
            + fixedLiabilityRepaymentTransactions(record, asOf: requestedDate)
        var seen = Set<UUID>()
        return combined
            .sorted { $0.date > $1.date }
            .filter { seen.insert($0.id).inserted }
    }

    func balance(for account: LedgerAccount) -> Decimal {
        currentBalances[account.id] ?? account.openingBalance
    }

    /// Destination-side amount used for balance/report reconciliation. Older
    /// transfers may not contain destinationAmount, so known fixed-rate currency
    /// pairs are reconstructed instead of incorrectly assuming a 1:1 transfer.
    func effectiveDestinationAmount(_ transaction: LedgerTransaction) -> Decimal {
        if let stored = transaction.destinationAmount { return stored }
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID) else {
            return transaction.amount
        }
        if source.currencyCode.caseInsensitiveCompare(destination.currencyCode) == .orderedSame {
            return transaction.amount
        }
        guard let rate = ERPAccountingEngine.rate(
            from: source.currencyCode,
            to: destination.currencyCode,
            on: transaction.date
        ) else { return transaction.amount }
        return ERPAccountingEngine.round(transaction.amount * rate)
    }

    func subAccounts(of accountID: UUID, includeArchived: Bool = false) -> [LedgerAccount] {
        accounts.filter {
            $0.parentAccountID == accountID && (includeArchived || !$0.isArchived)
        }.sorted {
            let left = $0.chartCode ?? "9999"
            let right = $1.chartCode ?? "9999"
            return left == right
                ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                : left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    func relatedAccountIDs(for accountID: UUID?) -> Set<UUID> {
        guard let accountID else { return [] }
        var ids: Set<UUID> = [accountID]
        if account(withID: accountID)?.parentAccountID == nil {
            ids.formUnion(subAccounts(of: accountID, includeArchived: true).map(\.id))
        }
        return ids
    }

    func consolidatedBalances(for account: LedgerAccount) -> [String: Decimal] {
        var totals: [String: Decimal] = [
            account.currencyCode.uppercased(): balance(for: account)
        ]
        guard account.parentAccountID == nil else { return totals }
        for child in subAccounts(of: account.id, includeArchived: true) {
            totals[child.currencyCode.uppercased(), default: 0] += balance(for: child)
        }
        return totals
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
                    result += effectiveDestinationAmount(transaction)
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

    func isBankAccount(_ account: LedgerAccount?) -> Bool {
        account?.nature == .bank
    }

    /// Financial Summary cash-flow classification is intentionally stricter than
    /// the general reports. Direct income/expense must be an explicit transaction,
    /// refunds are separated, and only Bank <-> Loan transfers affect loan cash flow.
    func isFinancialSummaryDirectIncome(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .income, transaction.refundOfTransactionID == nil else { return false }
        guard ERPAccountingEngine.isEnabled else { return true }
        guard ERPStorage.bool(ERPKey.summaryIncludeDirectIncome, true) else { return false }
        if ERPStorage.bool(ERPKey.summaryDirectIncomeBankOnly, false) {
            return isBankAccount(account(withID: transaction.accountID))
        }
        return true
    }

    func isFinancialSummaryRefund(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .income, transaction.refundOfTransactionID != nil else { return false }
        return !ERPAccountingEngine.isEnabled || ERPStorage.bool(ERPKey.summaryIncludeRefunds, true)
    }

    func isFinancialSummaryDirectExpense(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .expense, transaction.refundOfTransactionID == nil else { return false }
        guard ERPAccountingEngine.isEnabled else { return true }
        guard ERPStorage.bool(ERPKey.summaryIncludeDirectExpense, true) else { return false }
        if ERPStorage.bool(ERPKey.summaryDirectExpenseBankOnly, false) {
            return isBankAccount(account(withID: transaction.accountID))
        }
        return true
    }

    func financialSummaryLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard !ERPAccountingEngine.isEnabled || ERPStorage.bool(ERPKey.summaryIncludeLoanIncrease, true) else { return 0 }
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              isFinancialLoanAccount(source),
              destination.nature == .bank else { return 0 }
        return transaction.amount
    }

    func financialSummaryLoanPaidAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard !ERPAccountingEngine.isEnabled || ERPStorage.bool(ERPKey.summaryIncludeLoanPaid, true) else { return 0 }
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              source.nature == .bank,
              isFinancialLoanAccount(destination) else { return 0 }
        return transaction.amount
    }

    func convertedFinancialSummaryLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal? {
        let amount = financialSummaryLoanIncreaseAmount(transaction)
        guard amount > 0,
              let source = account(withID: transaction.accountID),
              let rate = ERPAccountingEngine.rate(from: source.currencyCode, to: currencyCode, on: transaction.date) else {
            return nil
        }
        return ERPAccountingEngine.round(amount * rate)
    }

    func convertedFinancialSummaryLoanPaidAmount(_ transaction: LedgerTransaction) -> Decimal? {
        let amount = financialSummaryLoanPaidAmount(transaction)
        guard amount > 0,
              let source = account(withID: transaction.accountID),
              let rate = ERPAccountingEngine.rate(from: source.currencyCode, to: currencyCode, on: transaction.date) else {
            return nil
        }
        return ERPAccountingEngine.round(amount * rate)
    }

    func isFinancialLoanAccount(_ account: LedgerAccount?) -> Bool {
        guard let account else { return false }
        guard ERPAccountingEngine.isEnabled else {
            return account.nature == .loan || account.nature == .fixedLiability || account.group == .payments
        }
        let mode = ERPLoanDetectionMode(
            rawValue: ERPStorage.string(ERPKey.loanDetectionMode, ERPLoanDetectionMode.hybrid.rawValue)
        ) ?? .hybrid
        let natureLoan = account.nature == .loan || account.nature == .fixedLiability
        let paymentLoan = account.group == .payments &&
            ERPStorage.bool(ERPKey.paymentNegativeActsLoan, true) && balance(for: account) < 0
        switch mode {
        case .natureOnly: return natureLoan
        case .paymentsOnly: return account.group == .payments
        case .hybrid: return natureLoan || paymentLoan
        }
    }

    func isPaymentToBankTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              source.group == .payments else { return false }
        return isBankAccount(account(withID: transaction.destinationAccountID))
    }

    func isBankToPaymentTransfer(_ transaction: LedgerTransaction) -> Bool {
        guard transaction.type == .transfer,
              isBankAccount(account(withID: transaction.accountID)),
              let destination = account(withID: transaction.destinationAccountID) else {
            return false
        }
        return destination.group == .payments
    }

    func paymentSourceBalanceBefore(_ transaction: LedgerTransaction) -> Decimal? {
        guard isPaymentToBankTransfer(transaction),
              let sourceID = transaction.accountID else { return nil }
        guard let after = runningBalance(for: transaction.id, accountID: sourceID) else {
            return nil
        }
        return after + transaction.amount
    }

    func receivableCollectionAmount(_ transaction: LedgerTransaction) -> Decimal {
        if ERPAccountingEngine.isEnabled {
            guard ERPStorage.bool(ERPKey.paymentPositiveActsReceivable, true),
                  ERPStorage.bool(ERPKey.reportPaymentPositiveAsReceivable, true) else { return 0 }
        }
        guard let before = paymentSourceBalanceBefore(transaction), before > 0 else { return 0 }
        return min(transaction.amount, before)
    }

    func paymentLoanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard isPaymentToBankTransfer(transaction) else { return 0 }
        return max(0, transaction.amount - receivableCollectionAmount(transaction))
    }

    func paymentLoanPaymentAmount(_ transaction: LedgerTransaction) -> Decimal {
        loanDecreaseAmount(transaction)
    }

    func transferIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              isBankAccount(destination),
              !isBankAccount(source) else { return 0 }

        if !ERPAccountingEngine.isEnabled {
            if source.group == .payments { return receivableCollectionAmount(transaction) }
            guard source.nature != .loan else { return 0 }
            return effectiveDestinationAmount(transaction)
        }
        if source.group == .payments {
            guard ERPStorage.bool(ERPKey.reportReceivableCollectionsAsIncome, true) else { return 0 }
            return receivableCollectionAmount(transaction)
        }
        if isFinancialLoanAccount(source) && ERPStorage.bool(ERPKey.reportExcludeLoanTransfers, true) { return 0 }
        if source.nature == .payable && ERPStorage.bool(ERPKey.reportPayableFundingAsIncome, false) {
            return effectiveDestinationAmount(transaction)
        }
        guard ERPStorage.bool(ERPKey.reportNonBankToBankAsIncome, true) else { return 0 }
        return effectiveDestinationAmount(transaction)
    }

    func isReportIncome(_ transaction: LedgerTransaction) -> Bool {
        if transaction.type == .income {
            if ERPAccountingEngine.isEnabled,
               transaction.refundOfTransactionID != nil,
               !ERPStorage.bool(ERPKey.reportRefundsAsIncome, true) { return false }
            return true
        }
        return transferIncomeAmount(transaction) > 0
    }

    func reportIncomeAmount(_ transaction: LedgerTransaction) -> Decimal {
        let raw = transaction.type == .income ? transaction.amount : transferIncomeAmount(transaction)
        guard ERPAccountingEngine.isEnabled,
              transaction.type == .income,
              ERPStorage.bool(ERPKey.reportUseNetOfTax, false) else { return raw }
        return ERPAccountingEngine.taxBreakdown(amount: raw, category: transaction.category, type: .income).net
    }

    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        transaction.type == .transfer ? transaction.destinationAccountID : transaction.accountID
    }

    func reportIncomeConversionAccountID(_ transaction: LedgerTransaction) -> UUID? {
        if transaction.type == .transfer,
           account(withID: transaction.accountID)?.group == .payments {
            return transaction.accountID
        }
        return reportIncomeAccountID(transaction)
    }

    func isReportExpense(_ transaction: LedgerTransaction) -> Bool {
        if transaction.type == .expense { return true }
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              let destination = account(withID: transaction.destinationAccountID),
              isBankAccount(source) else { return false }
        guard ERPAccountingEngine.isEnabled else {
            return !isBankAccount(destination) && !isFinancialLoanAccount(destination)
        }
        if isBankAccount(destination) && ERPStorage.bool(ERPKey.reportExcludeBankToBankTransfers, true) { return false }
        if isFinancialLoanAccount(destination) && ERPStorage.bool(ERPKey.reportExcludeLoanTransfers, true) { return false }
        switch destination.nature ?? .unassigned {
        case .asset, .fixedAsset:
            return ERPStorage.bool(ERPKey.reportBankToAssetAsExpense, true)
        case .receivable:
            return ERPStorage.bool(ERPKey.reportBankToReceivableAsExpense, true)
        case .payable:
            return ERPStorage.bool(ERPKey.reportBankToPayableAsExpense, true)
        default:
            return ERPStorage.bool(ERPKey.reportBankToNonBankAsExpense, true)
        }
    }

    func reportExpenseAmount(_ transaction: LedgerTransaction) -> Decimal {
        let raw = transaction.amount
        guard ERPAccountingEngine.isEnabled,
              transaction.type == .expense,
              ERPStorage.bool(ERPKey.reportUseNetOfTax, false) else { return raw }
        return ERPAccountingEngine.taxBreakdown(amount: raw, category: transaction.category, type: .expense).net
    }

    func reportExpenseAccountID(_ transaction: LedgerTransaction) -> UUID? { transaction.accountID }

    func loanIncreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              let source = account(withID: transaction.accountID),
              isBankAccount(account(withID: transaction.destinationAccountID)) else { return 0 }
        if source.group == .payments { return paymentLoanIncreaseAmount(transaction) }
        return isFinancialLoanAccount(source) ? transaction.amount : 0
    }

    func loanDecreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              isBankAccount(account(withID: transaction.accountID)),
              isFinancialLoanAccount(account(withID: transaction.destinationAccountID)) else { return 0 }
        return transaction.amount
    }

    func fixedReportConversionRate(from sourceCode: String, to destinationCode: String) -> Decimal? {
        ERPAccountingEngine.rate(from: sourceCode, to: destinationCode)
    }

    func convertedReportAmount(
        _ amount: Decimal,
        accountID: UUID?,
        to destinationCode: String? = nil,
        date: Date? = nil
    ) -> Decimal? {
        let destination = (destinationCode ?? currencyCode).uppercased()
        let source = account(withID: accountID)?.currencyCode.uppercased() ?? destination
        let rateDate = date ?? Date()
        guard let rate = ERPAccountingEngine.rate(from: source, to: destination, on: rateDate) else { return nil }
        return ERPAccountingEngine.round(amount * rate)
    }

    func convertedReportIncomeAmount(
        _ transaction: LedgerTransaction,
        to destinationCode: String? = nil
    ) -> Decimal? {
        guard isReportIncome(transaction) else { return nil }
        let date = ERPStorage.bool(ERPKey.useTransactionDateForRates, true) ? transaction.date : Date()
        return convertedReportAmount(
            reportIncomeAmount(transaction),
            accountID: reportIncomeConversionAccountID(transaction),
            to: destinationCode,
            date: date
        )
    }

    func convertedReportExpenseAmount(
        _ transaction: LedgerTransaction,
        to destinationCode: String? = nil
    ) -> Decimal? {
        guard isReportExpense(transaction) else { return nil }
        let date = ERPStorage.bool(ERPKey.useTransactionDateForRates, true) ? transaction.date : Date()
        return convertedReportAmount(
            reportExpenseAmount(transaction),
            accountID: reportExpenseAccountID(transaction),
            to: destinationCode,
            date: date
        )
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
        guard requireOpenPeriod(transaction.date, action: "delete") else { return }
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                ledger.transactions.removeAll {
                    $0.id == transaction.id || $0.refundOfTransactionID == transaction.id
                }
            }
            apply(ledger)
        } catch {
            errorMessage = "The transaction could not be deleted."
        }
    }

    @discardableResult
    func update(_ transaction: LedgerTransaction) -> Bool {
        if let original = transactions.first(where: { $0.id == transaction.id }),
           !requireOpenPeriod(original.date, action: "update") {
            return false
        }
        guard requireOpenPeriod(transaction.date, action: "move or update") else { return false }
        var candidate = transaction
        candidate.amount = ERPAccountingEngine.postingAmount(candidate.amount)
        if candidate.type == .transfer {
            candidate.destinationAmount = candidate.destinationAmount.map(ERPAccountingEngine.postingAmount)
        }
        if let error = erpPostingError(
            type: candidate.type,
            amount: candidate.amount,
            date: candidate.date,
            category: candidate.category,
            vendor: candidate.vendor,
            details: candidate.details,
            accountID: candidate.accountID,
            destinationAccountID: candidate.destinationAccountID,
            destinationAmount: candidate.destinationAmount,
            dimensions: candidate.dimensions,
            excludingTransactionID: candidate.id
        ) {
            errorMessage = error
            return false
        }
        var found = false
        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard let index = ledger.transactions.firstIndex(where: { $0.id == candidate.id }) else { return }
                ledger.transactions[index] = candidate
                found = true
            }
            guard found else {
                errorMessage = "The original transaction could not be found."
                return false
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The transaction could not be updated."
            return false
        }
    }

    func updateCurrency(_ code: String) {
        guard code != settings.currencyCode else { return }
        updateLedger(failureMessage: "The currency could not be updated.") { ledger in
            ledger.settings.currencyCode = code
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
        guard let historyStart = calendar.date(byAdding: .month, value: -max(1, ERPStorage.int(ERPKey.budgetHistoryMonths, 3)), to: currentMonth) else {
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
            let historicalAverage = historicalTotal / Decimal(max(1, ERPStorage.int(ERPKey.budgetHistoryMonths, 3)))
            if historicalAverage > 0 {
                return (
                    budget.id,
                    roundedBudget(historicalAverage * ERPStorage.decimal(ERPKey.budgetHistoricalFactorPercent, 90) / 100)
                )
            }
            let count = max(budgetCountByCurrency[budget.currencyCode, default: 1], 1)
            if monthlyIncome > 0 && budget.currencyCode == incomeCurrencyCode {
                return (
                    budget.id,
                    roundedBudget(
                        monthlyIncome * ERPStorage.decimal(ERPKey.budgetIncomeAllocationPercent, 80) / 100 / Decimal(count)
                    )
                )
            }
            return (budget.id, budget.monthlyAmount)
        })
    }

    private func roundedBudget(_ amount: Decimal) -> Decimal {
        var value = amount
        var rounded = Decimal()
        NSDecimalRound(
            &rounded,
            &value,
            ERPAccountingEngine.isEnabled ? max(0, min(4, ERPStorage.int(ERPKey.budgetRoundingDecimals, 0))) : 0,
            .plain
        )
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
            let thresholdPercent = ERPAccountingEngine.isEnabled
                ? ERPStorage.decimal(ERPKey.budgetAlertPercent, 80)
                : Decimal(80)
            let threshold = budget.monthlyAmount * thresholdPercent / 100
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
            accountPart,
            ERPAccountingEngine.configurationFingerprint()
        ].joined(separator: "|")
    }

    func totals(in interval: DateInterval, accountIDs: Set<UUID>? = nil) -> LedgerTotals {
        let cacheKey = reportCacheKey(interval: interval, accountIDs: accountIDs)
        if let cached = totalsCache[cacheKey] {
            return cached
        }

        let selectedBySourceAccount = transactions.filter {
            interval.contains($0.date) &&
            (accountIDs == nil || accountIDs?.contains($0.accountID ?? LedgerAccount.legacyMainID) == true)
        }
        let expenseTransactions = selectedBySourceAccount.filter {
            $0.type == .expense && convertedReportExpenseAmount($0) != nil
        }
        let incomeTransactions = transactions.filter {
            guard interval.contains($0.date), isReportIncome($0) else { return false }
            let incomeAccountID = reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID
            return (accountIDs == nil || accountIDs?.contains(incomeAccountID) == true) &&
                convertedReportIncomeAmount($0) != nil
        }
        let sameCurrencySelected = selectedBySourceAccount.filter {
            accountsByID[$0.accountID ?? LedgerAccount.legacyMainID]?.currencyCode == currencyCode
        }

        let income = incomeTransactions.reduce(Decimal.zero) {
            $0 + (convertedReportIncomeAmount($1) ?? 0)
        }
        let expense = expenseTransactions.reduce(Decimal.zero) {
            $0 + (convertedReportExpenseAmount($1) ?? 0)
        }
        let loan = sameCurrencySelected
            .filter {
                $0.type == .transfer &&
                accountsByID[$0.destinationAccountID ?? LedgerAccount.legacyMainID]?.group == .payments
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let transfer = sameCurrencySelected
            .filter { $0.type == .transfer }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let countedIDs = Set(
            expenseTransactions.map(\.id) +
            incomeTransactions.map(\.id) +
            sameCurrencySelected.filter { $0.type == .transfer }.map(\.id)
        )
        let result = LedgerTotals(
            income: income,
            expense: expense,
            loan: loan,
            transfer: transfer,
            count: countedIDs.count
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
            ($0.group == .payments && balance(for: $0) < 0) ||
                ($0.group != .payments && $0.nature == .loan)
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
