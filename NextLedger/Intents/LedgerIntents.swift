import AppIntents
import Foundation

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Record an expense in Next Ledger without opening the app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Description")
    var details: String?

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "Account")
    var account: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount.isFinite, amount > 0 else {
            return .result(dialog: "Enter an amount greater than zero.")
        }

        let transaction = LedgerTransaction(
            type: .expense,
            amount: Decimal(amount),
            date: date ?? Date(),
            category: normalizedCategory(category),
            details: details ?? "",
            accountID: accountID(named: account)
        )

        do {
            try LedgerDiskStore.shared.add(transaction)
            return .result(dialog: "Expense saved in Next Ledger.")
        } catch {
            return .result(dialog: "The expense could not be saved.")
        }
    }
}

struct AddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Income"
    static let description = IntentDescription("Record income in Next Ledger without opening the app.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Category")
    var category: String?

    @Parameter(title: "Description")
    var details: String?

    @Parameter(title: "Date")
    var date: Date?

    @Parameter(title: "Account")
    var account: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount.isFinite, amount > 0 else {
            return .result(dialog: "Enter an amount greater than zero.")
        }

        let transaction = LedgerTransaction(
            type: .income,
            amount: Decimal(amount),
            date: date ?? Date(),
            category: normalizedCategory(category, fallback: "Salary"),
            details: details ?? "",
            accountID: accountID(named: account)
        )

        do {
            try LedgerDiskStore.shared.add(transaction)
            return .result(dialog: "Income saved in Next Ledger.")
        } catch {
            return .result(dialog: "The income could not be saved.")
        }
    }
}

struct TransferMoneyIntent: AppIntent {
    static let title: LocalizedStringResource = "Transfer Money"
    static let description = IntentDescription("Move money between two Next Ledger accounts.")
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "From Account")
    var sourceAccount: String

    @Parameter(title: "To Account")
    var destinationAccount: String

    @Parameter(title: "Amount Sent")
    var amount: Double

    @Parameter(title: "Amount Received")
    var destinationAmount: Double?

    @Parameter(title: "Description")
    var details: String?

    @Parameter(title: "Date")
    var date: Date?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ledger = LedgerDiskStore.shared.load()
        guard amount.isFinite, amount > 0,
              let source = findAccount(named: sourceAccount, in: ledger),
              let destination = findAccount(named: destinationAccount, in: ledger),
              source.id != destination.id else {
            return .result(dialog: "Enter two different existing account names and a valid amount.")
        }
        let received = destinationAmount ?? amount
        guard received.isFinite, received > 0 else {
            return .result(dialog: "Enter an amount received greater than zero.")
        }
        let transaction = LedgerTransaction(
            type: .transfer,
            amount: Decimal(amount),
            date: date ?? Date(),
            category: "Transfer",
            details: details ?? "",
            accountID: source.id,
            destinationAccountID: destination.id,
            destinationAmount: Decimal(received)
        )
        do {
            try LedgerDiskStore.shared.add(transaction)
            return .result(dialog: "Transfer saved in Next Ledger.")
        } catch {
            return .result(dialog: "The transfer could not be saved.")
        }
    }
}

struct OpenAddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Add Expense"
    static let description = IntentDescription("Open Next Ledger on the expense entry screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutRouter.requestAdd(.expense)
        return .result()
    }
}

struct OpenAddIncomeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Add Income"
    static let description = IntentDescription("Open Next Ledger on the income entry screen.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        ShortcutRouter.requestAdd(.income)
        return .result()
    }
}

struct DailyLedgerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Record expense with \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "minus.circle.fill"
        )

        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Record income with \(.applicationName)"
            ],
            shortTitle: "Add Income",
            systemImageName: "plus.circle.fill"
        )

        AppShortcut(
            intent: TransferMoneyIntent(),
            phrases: ["Transfer money with \(.applicationName)"],
            shortTitle: "Transfer Money",
            systemImageName: "arrow.left.arrow.right.circle.fill"
        )

        AppShortcut(
            intent: OpenAddExpenseIntent(),
            phrases: ["Open expense entry in \(.applicationName)"],
            shortTitle: "Open Expense Entry",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: OpenAddIncomeIntent(),
            phrases: ["Open income entry in \(.applicationName)"],
            shortTitle: "Open Income Entry",
            systemImageName: "square.and.pencil"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}

private func normalizedCategory(_ category: String?, fallback: String = "Other") -> String {
    let value = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? fallback : value
}

private func findAccount(named name: String, in ledger: LedgerData) -> LedgerAccount? {
    let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return ledger.accounts.first {
        !$0.isArchived && $0.name.caseInsensitiveCompare(cleaned) == .orderedSame
    }
}

private func accountID(named name: String?) -> UUID? {
    let ledger = LedgerDiskStore.shared.load()
    if let name, let account = findAccount(named: name, in: ledger) { return account.id }
    return ledger.settings.defaultAccountID ?? ledger.accounts.first(where: { !$0.isArchived })?.id
}
