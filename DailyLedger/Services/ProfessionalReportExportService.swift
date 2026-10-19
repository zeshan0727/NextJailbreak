import CoreGraphics
import Foundation
import UIKit

enum ProfessionalReportType: String, CaseIterable, Identifiable {
    case financialSummary = "Financial Summary"
    case incomeTransactions = "Income Report"
    case expenseTransactions = "Expense Report"
    case transfers = "Loans / Transfers"
    case categorySummary = "Category Report"
    case incomeStatement = "Income Statement"
    case balanceSheet = "Balance Sheet"
    case payablesAging = "Payables Aging"
    case payablesSummary = "Payables Summary"
    case receivablesAging = "Receivables Aging"
    case receivablesSummary = "Receivables Summary"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .financialSummary:
            return "Income, expenses and net result with one QAR total"
        case .incomeTransactions:
            return "Detailed income transactions with native and QAR amounts"
        case .expenseTransactions:
            return "Detailed expenses with native and QAR amounts"
        case .transfers:
            return "Account and loan transfers for the selected period"
        case .categorySummary:
            return "Expense totals by category with one QAR total"
        case .incomeStatement:
            return "Revenue, expenses and profit or loss for a custom period"
        case .balanceSheet:
            return "Opening, movement and closing balances for a custom period"
        case .payablesAging:
            return "Detailed outstanding payable items by age"
        case .payablesSummary:
            return "Payable account totals in aging buckets"
        case .receivablesAging:
            return "Detailed outstanding receivable items by age"
        case .receivablesSummary:
            return "Receivable account totals in aging buckets"
        }
    }

    var icon: String {
        switch self {
        case .financialSummary: return "chart.bar.doc.horizontal.fill"
        case .incomeTransactions: return "arrow.down.left.circle.fill"
        case .expenseTransactions: return "arrow.up.right.circle.fill"
        case .transfers: return "arrow.left.arrow.right.circle.fill"
        case .categorySummary: return "square.grid.2x2.fill"
        case .incomeStatement: return "chart.line.uptrend.xyaxis"
        case .balanceSheet: return "scale.3d"
        case .payablesAging: return "calendar.badge.exclamationmark"
        case .payablesSummary: return "arrow.up.right.circle.fill"
        case .receivablesAging: return "calendar.badge.clock"
        case .receivablesSummary: return "arrow.down.left.circle.fill"
        }
    }

    var usesAsOfDateOnly: Bool {
        switch self {
        case .payablesAging, .payablesSummary, .receivablesAging, .receivablesSummary:
            return true
        default:
            return false
        }
    }
}

enum ProfessionalExportFormat: String {
    case pdf = "PDF"
    case excel = "Excel"

    var fileExtension: String { self == .pdf ? "pdf" : "xlsx" }
    var icon: String { self == .pdf ? "doc.richtext.fill" : "tablecells.fill" }
}

enum ProfessionalReportEmphasis {
    case normal
    case section
    case subtotal
    case total
}

enum ProfessionalReportCell {
    case text(String)
    case number(Decimal)
}

struct ProfessionalReportRow {
    let cells: [ProfessionalReportCell]
    let emphasis: ProfessionalReportEmphasis

    init(_ cells: [ProfessionalReportCell], emphasis: ProfessionalReportEmphasis = .normal) {
        self.cells = cells
        self.emphasis = emphasis
    }
}

struct ProfessionalReportTable {
    let title: String
    let subtitle: String
    let columns: [String]
    let rows: [ProfessionalReportRow]
}

struct ProfessionalReportDocument {
    let title: String
    let subtitle: String
    let periodText: String
    let generatedAt: Date
    let tables: [ProfessionalReportTable]
    let notes: [String]
}

struct ProfessionalReportScope {
    var transactionIDs: Set<UUID> = []
    var accountIDs: Set<UUID> = []
    var currencyCode: String? = nil
    var reportTitle: String? = nil

    var isEmpty: Bool {
        transactionIDs.isEmpty && accountIDs.isEmpty && currencyCode == nil && reportTitle == nil
    }
}

@MainActor
enum ProfessionalReportBuilder {
    private struct AccountBalanceLine {
        let account: LedgerAccount
        let opening: Decimal
        let movement: Decimal
        let closing: Decimal
        let section: BalanceSheetSection
    }

    private enum BalanceSheetSection: String, CaseIterable {
        case assets = "Cash & Other Assets"
        case receivables = "Receivables"
        case payables = "Payables"
        case loans = "Loans"
        case otherLiabilities = "Other Liabilities"

        var isLiability: Bool {
            self == .payables || self == .loans || self == .otherLiabilities
        }
    }

    private struct AgingLot {
        var amount: Decimal
        let date: Date
        let reference: String
    }

    private struct AgingBuckets {
        var current: Decimal = 0
        var days31To60: Decimal = 0
        var days61To90: Decimal = 0
        var over90: Decimal = 0

        var total: Decimal { current + days31To60 + days61To90 + over90 }

        mutating func add(amount: Decimal, days: Int) {
            if days <= 30 {
                current += amount
            } else if days <= 60 {
                days31To60 += amount
            } else if days <= 90 {
                days61To90 += amount
            } else {
                over90 += amount
            }
        }

        mutating func add(_ other: AgingBuckets) {
            current += other.current
            days31To60 += other.days31To60
            days61To90 += other.days61To90
            over90 += other.over90
        }
    }

    static func build(
        type: ProfessionalReportType,
        startDate: Date,
        endDate: Date,
        store: LedgerStore,
        scope: ProfessionalReportScope = ProfessionalReportScope()
    ) -> ProfessionalReportDocument {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let interval = DateInterval(start: start, end: endExclusive)

        if !scope.isEmpty {
            return scopedDocument(
                type: type,
                interval: interval,
                endDay: endDay,
                store: store,
                scope: scope
            )
        }

        let document: ProfessionalReportDocument
        switch type {
        case .financialSummary:
            document = financialSummary(interval: interval, store: store)
        case .incomeTransactions:
            document = transactionReport(isIncome: true, interval: interval, store: store)
        case .expenseTransactions:
            document = transactionReport(isIncome: false, interval: interval, store: store)
        case .transfers:
            document = transferReport(interval: interval, store: store)
        case .categorySummary:
            document = categoryReport(interval: interval, store: store)
        case .incomeStatement:
            document = incomeStatement(interval: interval, store: store)
        case .balanceSheet:
            document = balanceSheet(interval: interval, store: store)
        case .payablesAging:
            document = agingReport(isPayable: true, detailed: true, asOf: endDay, store: store)
        case .payablesSummary:
            document = agingReport(isPayable: true, detailed: false, asOf: endDay, store: store)
        case .receivablesAging:
            document = agingReport(isPayable: false, detailed: true, asOf: endDay, store: store)
        case .receivablesSummary:
            document = agingReport(isPayable: false, detailed: false, asOf: endDay, store: store)
        }
        return addQARConsolidation(document, type: type, interval: interval, store: store)
    }

    private static func scopedDocument(
        type: ProfessionalReportType,
        interval: DateInterval,
        endDay: Date,
        store: LedgerStore,
        scope: ProfessionalReportScope
    ) -> ProfessionalReportDocument {
        let transactions = store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            if !scope.transactionIDs.isEmpty, !scope.transactionIDs.contains(transaction.id) {
                return false
            }
            if !scope.accountIDs.isEmpty {
                let source = transaction.accountID ?? LedgerAccount.legacyMainID
                let destination = transaction.destinationAccountID ?? LedgerAccount.legacyMainID
                let incomeAccount = store.reportIncomeAccountID(transaction) ?? LedgerAccount.legacyMainID
                if !scope.accountIDs.contains(source) &&
                    !scope.accountIDs.contains(destination) &&
                    !scope.accountIDs.contains(incomeAccount) {
                    return false
                }
            }
            if let currency = scope.currencyCode?.uppercased() {
                let accountID = store.isReportIncome(transaction)
                    ? store.reportIncomeAccountID(transaction)
                    : transaction.accountID
                if store.account(withID: accountID)?.currencyCode.uppercased() != currency {
                    return false
                }
            }
            return true
        }

        let accounts = store.activeAccounts.filter { account in
            if !scope.accountIDs.isEmpty, !scope.accountIDs.contains(account.id) { return false }
            if let currency = scope.currencyCode?.uppercased(),
               account.currencyCode.uppercased() != currency { return false }
            return true
        }

        let base: ProfessionalReportDocument
        switch type {
        case .financialSummary:
            base = scopedFinancialSummary(interval: interval, transactions: transactions, store: store)
        case .incomeTransactions:
            base = scopedTransactionReport(isIncome: true, interval: interval, transactions: transactions, store: store)
        case .expenseTransactions:
            base = scopedTransactionReport(isIncome: false, interval: interval, transactions: transactions, store: store)
        case .transfers:
            base = scopedTransferReport(interval: interval, transactions: transactions, store: store)
        case .categorySummary:
            base = scopedCategoryReport(interval: interval, transactions: transactions, store: store)
        case .incomeStatement:
            base = scopedIncomeStatement(interval: interval, transactions: transactions, store: store)
        case .balanceSheet:
            base = scopedBalanceSheet(interval: interval, accounts: accounts, store: store)
        case .payablesAging:
            base = agingReport(isPayable: true, detailed: true, asOf: endDay, store: store)
        case .payablesSummary:
            base = agingReport(isPayable: true, detailed: false, asOf: endDay, store: store)
        case .receivablesAging:
            base = agingReport(isPayable: false, detailed: true, asOf: endDay, store: store)
        case .receivablesSummary:
            base = agingReport(isPayable: false, detailed: false, asOf: endDay, store: store)
        }

        let overview = scopedOverview(
            type: type,
            interval: interval,
            transactions: transactions,
            accounts: accounts,
            store: store
        )
        return ProfessionalReportDocument(
            title: scope.reportTitle ?? base.title,
            subtitle: base.subtitle,
            periodText: base.periodText,
            generatedAt: base.generatedAt,
            tables: (overview.map { [$0] } ?? []) + base.tables,
            notes: base.notes
        )
    }

    private static func scopedCurrencies(
        _ transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> [String] {
        let values = transactions.compactMap { transaction -> String? in
            let accountID = store.isReportIncome(transaction)
                ? store.reportIncomeAccountID(transaction)
                : transaction.accountID
            return store.account(withID: accountID)?.currencyCode.uppercased()
        }
        return Array(Set(values)).sorted()
    }

    private static func scopedFinancialSummary(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        for currency in scopedCurrencies(transactions, store: store) {
            let incomeItems = transactions.filter {
                store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }
            let expenseItems = transactions.filter {
                $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }
            let income = incomeItems.reduce(Decimal.zero) { $0 + store.reportIncomeAmount($1) }
            let expense = expenseItems.reduce(Decimal.zero) { $0 + $1.amount }
            guard income != 0 || expense != 0 else { continue }
            tables.append(ProfessionalReportTable(
                title: "Financial Summary — \(currency)",
                subtitle: "Reviewed transactions only",
                columns: ["Metric", "Amount", "Transactions"],
                rows: [
                    ProfessionalReportRow([.text("Income"), .number(income), .text("\(incomeItems.count)")]),
                    ProfessionalReportRow([.text("Expenses"), .number(expense), .text("\(expenseItems.count)")]),
                    ProfessionalReportRow([.text("Net Result"), .number(income - expense), .text("\(incomeItems.count + expenseItems.count)")], emphasis: .total)
                ]
            ))
        }
        return ProfessionalReportDocument(
            title: "Financial Summary",
            subtitle: "Same period, currency and filters currently being reviewed",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: screenMatchedNotes
        )
    }

    private static func scopedTransactionReport(
        isIncome: Bool,
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let items = transactions.filter { isIncome ? store.isReportIncome($0) : $0.type == .expense }
            .sorted { $0.date < $1.date }
        var rows = items.map { transaction -> ProfessionalReportRow in
            let accountID = isIncome ? store.reportIncomeAccountID(transaction) : transaction.accountID
            let account = store.account(withID: accountID)
            let currency = account?.currencyCode.uppercased() ?? "QAR"
            let amount = isIncome ? store.reportIncomeAmount(transaction) : transaction.amount
            let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                ? .number(amount)
                : currency == "PKR" ? .number(amount / pkrPerQAR) : .text("—")
            return ProfessionalReportRow([
                .text(shortDate(transaction.date)),
                .text(account?.name ?? "Unassigned"),
                .text(transaction.category),
                .text(transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? transaction.vendor! : "—"),
                .number(amount),
                .text(currency),
                qarEquivalent
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([.text("No reviewed transactions"), .text(""), .text(""), .text(""), .number(0), .text(""), .number(0)])]
        }
        let title = isIncome ? "Income Report" : "Expense Report"
        return ProfessionalReportDocument(
            title: title,
            subtitle: "Same transactions currently visible in the report",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: title,
                subtitle: "Native amount and QAR equivalent",
                columns: ["Date", "Account", "Category", "Vendor", "Amount", "Currency", "QAR Equivalent"],
                rows: rows
            )],
            notes: screenMatchedNotes
        )
    }

    private static func scopedTransferReport(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let items = transactions.filter { $0.type == .transfer }.sorted { $0.date < $1.date }
        var rows = items.map { transaction -> ProfessionalReportRow in
            let source = store.account(withID: transaction.accountID)
            let destination = store.account(withID: transaction.destinationAccountID)
            let currency = source?.currencyCode.uppercased() ?? "QAR"
            let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                ? .number(transaction.amount)
                : currency == "PKR" ? .number(transaction.amount / pkrPerQAR) : .text("—")
            return ProfessionalReportRow([
                .text(shortDate(transaction.date)),
                .text(source?.name ?? "Unassigned"),
                .text(destination?.name ?? "Unassigned"),
                .number(transaction.amount),
                .text(currency),
                qarEquivalent
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([.text("No reviewed transfers"), .text(""), .text(""), .number(0), .text(""), .number(0)])]
        }
        return ProfessionalReportDocument(
            title: "Loans / Transfers",
            subtitle: "Same transfers currently visible in the report",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Transfer Detail",
                subtitle: "Source, destination and QAR equivalent",
                columns: ["Date", "From Account", "To Account", "Amount", "Currency", "QAR Equivalent"],
                rows: rows
            )],
            notes: screenMatchedNotes
        )
    }

    private static func scopedCategoryReport(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var totals: [String: (qar: Decimal, pkr: Decimal)] = [:]
        for transaction in transactions where transaction.type == .expense {
            let currency = store.account(withID: transaction.accountID)?.currencyCode.uppercased() ?? "QAR"
            var value = totals[transaction.category] ?? (0, 0)
            if currency == "PKR" { value.pkr += transaction.amount }
            else if currency == "QAR" { value.qar += transaction.amount }
            totals[transaction.category] = value
        }
        let rows = totals.keys.sorted(by: localizedSort).map { category -> ProfessionalReportRow in
            let value = totals[category] ?? (0, 0)
            let pkrInQAR = value.pkr / pkrPerQAR
            return ProfessionalReportRow([
                .text(category), .number(value.qar), .number(value.pkr), .number(pkrInQAR), .number(value.qar + pkrInQAR)
            ])
        }
        return ProfessionalReportDocument(
            title: "Category Report",
            subtitle: "Same categories currently visible in the report",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Expense Categories",
                subtitle: "QAR, PKR and consolidated QAR",
                columns: ["Category", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
                rows: rows
            )],
            notes: screenMatchedNotes
        )
    }

    private static func scopedIncomeStatement(
        interval: DateInterval,
        transactions: [LedgerTransaction],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        for currency in scopedCurrencies(transactions, store: store) {
            var revenue: [String: Decimal] = [:]
            var expenses: [String: Decimal] = [:]
            for transaction in transactions {
                if store.isReportIncome(transaction),
                   store.account(withID: store.reportIncomeAccountID(transaction))?.currencyCode.uppercased() == currency {
                    revenue[transaction.category, default: 0] += store.reportIncomeAmount(transaction)
                } else if transaction.type == .expense,
                          store.account(withID: transaction.accountID)?.currencyCode.uppercased() == currency {
                    expenses[transaction.category, default: 0] += transaction.amount
                }
            }
            let totalRevenue = revenue.values.reduce(Decimal.zero, +)
            let totalExpenses = expenses.values.reduce(Decimal.zero, +)
            guard totalRevenue != 0 || totalExpenses != 0 else { continue }
            var rows: [ProfessionalReportRow] = [ProfessionalReportRow([.text("REVENUE"), .text("")], emphasis: .section)]
            rows += revenue.keys.sorted(by: localizedSort).map { ProfessionalReportRow([.text($0), .number(revenue[$0, default: 0])]) }
            rows.append(ProfessionalReportRow([.text("Total Revenue"), .number(totalRevenue)], emphasis: .subtotal))
            rows.append(ProfessionalReportRow([.text("EXPENSES"), .text("")], emphasis: .section))
            rows += expenses.keys.sorted(by: localizedSort).map { ProfessionalReportRow([.text($0), .number(expenses[$0, default: 0])]) }
            rows.append(ProfessionalReportRow([.text("Total Expenses"), .number(totalExpenses)], emphasis: .subtotal))
            rows.append(ProfessionalReportRow([
                .text(totalRevenue >= totalExpenses ? "Net Profit" : "Net Loss"),
                .number(totalRevenue - totalExpenses)
            ], emphasis: .total))
            tables.append(ProfessionalReportTable(
                title: "Income Statement — \(currency)",
                subtitle: "Reviewed categories in native \(currency)",
                columns: ["Category", "Amount"],
                rows: rows
            ))
        }
        return ProfessionalReportDocument(
            title: "Income Statement",
            subtitle: "Revenue, expenses and profit or loss",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: screenMatchedNotes
        )
    }

    private static func scopedBalanceSheet(
        interval: DateInterval,
        accounts: [LedgerAccount],
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        for currency in Array(Set(accounts.map { $0.currencyCode.uppercased() })).sorted() {
            let lines = accounts.filter { $0.currencyCode.uppercased() == currency }.compactMap { account -> AccountBalanceLine? in
                let opening = store.combinedBalance(for: [account], before: interval.start)
                let closing = store.combinedBalance(for: [account], before: interval.end)
                let movement = closing - opening
                guard opening != 0 || movement != 0 || closing != 0 else { return nil }
                return AccountBalanceLine(account: account, opening: opening, movement: movement, closing: closing, section: balanceSection(account: account, closing: closing))
            }
            guard !lines.isEmpty else { continue }
            var rows: [ProfessionalReportRow] = []
            for section in BalanceSheetSection.allCases {
                let sectionLines = lines.filter { $0.section == section }.sorted { localizedSort($0.account.name, $1.account.name) }
                guard !sectionLines.isEmpty else { continue }
                rows.append(ProfessionalReportRow([.text(""), .text(section.rawValue), .text(""), .text(""), .text("")], emphasis: .section))
                for line in sectionLines {
                    let multiplier: Decimal = section.isLiability ? -1 : 1
                    rows.append(ProfessionalReportRow([
                        .text(chartCodeText(line.account)), .text(line.account.name),
                        .number(line.opening * multiplier), .number(line.movement * multiplier), .number(line.closing * multiplier)
                    ]))
                }
                let multiplier: Decimal = section.isLiability ? -1 : 1
                rows.append(ProfessionalReportRow([
                    .text(""), .text("Total \(section.rawValue)"),
                    .number(sectionLines.reduce(0) { $0 + $1.opening } * multiplier),
                    .number(sectionLines.reduce(0) { $0 + $1.movement } * multiplier),
                    .number(sectionLines.reduce(0) { $0 + $1.closing } * multiplier)
                ], emphasis: .subtotal))
            }
            tables.append(ProfessionalReportTable(
                title: "Balance Sheet Detail — \(currency)",
                subtitle: "Selected accounts only",
                columns: ["Code", "Account", "Opening", "Movement", "Closing"],
                rows: rows
            ))
        }
        return ProfessionalReportDocument(
            title: "Balance Sheet",
            subtitle: "Opening, movement and closing balances",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: screenMatchedNotes
        )
    }

    private static func scopedOverview(
        type: ProfessionalReportType,
        interval: DateInterval,
        transactions: [LedgerTransaction],
        accounts: [LedgerAccount],
        store: LedgerStore
    ) -> ProfessionalReportTable? {
        func income(_ currency: String) -> Decimal {
            transactions.filter {
                store.isReportIncome($0) && store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }.reduce(0) { $0 + store.reportIncomeAmount($1) }
        }
        func expense(_ currency: String) -> Decimal {
            transactions.filter {
                $0.type == .expense && store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(0) { $0 + $1.amount }
        }
        func transfer(_ currency: String) -> Decimal {
            transactions.filter {
                $0.type == .transfer && store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(0) { $0 + $1.amount }
        }
        func balance(_ currency: String) -> (Decimal, Decimal, Decimal) {
            var assets: Decimal = 0
            var liabilities: Decimal = 0
            for account in accounts where account.currencyCode.uppercased() == currency {
                let closing = store.combinedBalance(for: [account], before: interval.end)
                if balanceSection(account: account, closing: closing).isLiability { liabilities += decimalAbs(closing) }
                else { assets += decimalAbs(closing) }
            }
            return (assets, liabilities, assets - liabilities)
        }

        var metrics: [(String, Decimal, Decimal)] = []
        switch type {
        case .financialSummary, .incomeStatement:
            let qi = income("QAR"), pi = income("PKR"), qe = expense("QAR"), pe = expense("PKR")
            metrics = [("Income", qi, pi), ("Expenses", qe, pe), ("Net Result", qi - qe, pi - pe)]
        case .incomeTransactions:
            metrics = [("Total Income", income("QAR"), income("PKR"))]
        case .expenseTransactions, .categorySummary:
            metrics = [("Total Expenses", expense("QAR"), expense("PKR"))]
        case .transfers:
            metrics = [("Transfers", transfer("QAR"), transfer("PKR"))]
        case .balanceSheet:
            let q = balance("QAR"), p = balance("PKR")
            metrics = [("Total Assets", q.0, p.0), ("Total Liabilities", q.1, p.1), ("Net Equity", q.2, p.2)]
        default:
            return nil
        }
        guard metrics.contains(where: { $0.1 != 0 || $0.2 != 0 }) else { return nil }
        return ProfessionalReportTable(
            title: "QAR & PKR Overview",
            subtitle: "PKR converted at the fixed rate: PKR 77 = QAR 1",
            columns: ["Metric", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
            rows: metrics.map { item in
                let converted = item.2 / pkrPerQAR
                return ProfessionalReportRow([
                    .text(item.0), .number(item.1), .number(item.2), .number(converted), .number(item.1 + converted)
                ], emphasis: item.0.contains("Net") ? .total : .subtotal)
            }
        )
    }

    private static let screenMatchedNotes = [
        "This export uses the same period, accounts, currency and transaction filters shown on screen.",
        "PKR consolidated values use the fixed app rate PKR 77 = QAR 1."
    ]

    private static let pkrPerQAR = Decimal(77)

    private static func addQARConsolidation(
        _ document: ProfessionalReportDocument,
        type: ProfessionalReportType,
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        guard let overview = consolidatedOverview(type: type, interval: interval, store: store) else {
            return document
        }
        return ProfessionalReportDocument(
            title: document.title,
            subtitle: document.subtitle,
            periodText: document.periodText,
            generatedAt: document.generatedAt,
            tables: [overview] + document.tables,
            notes: document.notes
        )
    }

    private static func consolidatedOverview(
        type: ProfessionalReportType,
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportTable? {
        func income(_ currency: String) -> Decimal {
            store.transactions.lazy.filter {
                interval.contains($0.date) &&
                    store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { $0 + store.reportIncomeAmount($1) }
        }

        func expenses(_ currency: String) -> Decimal {
            store.transactions.lazy.filter {
                interval.contains($0.date) && $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { $0 + $1.amount }
        }

        func transfers(_ currency: String) -> Decimal {
            store.transactions.lazy.filter {
                interval.contains($0.date) && $0.type == .transfer &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { $0 + $1.amount }
        }

        func balanceMetrics(_ currency: String) -> (assets: Decimal, liabilities: Decimal, equity: Decimal) {
            var assets: Decimal = 0
            var liabilities: Decimal = 0
            for account in store.activeAccounts where account.currencyCode.uppercased() == currency {
                let closing = store.combinedBalance(for: [account], before: interval.end)
                let section = balanceSection(account: account, closing: closing)
                if section.isLiability {
                    liabilities += decimalAbs(closing)
                } else {
                    assets += decimalAbs(closing)
                }
            }
            return (assets, liabilities, assets - liabilities)
        }

        func agingOutstanding(_ currency: String, payable: Bool) -> Decimal {
            store.activeAccounts.lazy.filter(isAgingAccount).filter {
                $0.currencyCode.uppercased() == currency
            }.reduce(Decimal.zero) { total, account in
                let balance = store.combinedBalance(for: [account], before: interval.end)
                if payable, balance < 0 { return total + decimalAbs(balance) }
                if !payable, balance > 0 { return total + balance }
                return total
            }
        }

        var metrics: [(String, Decimal, Decimal)] = []
        switch type {
        case .financialSummary, .incomeStatement:
            let qarIncome = income("QAR")
            let pkrIncome = income("PKR")
            let qarExpense = expenses("QAR")
            let pkrExpense = expenses("PKR")
            metrics = [
                ("Income", qarIncome, pkrIncome),
                ("Expenses", qarExpense, pkrExpense),
                ("Net Result", qarIncome - qarExpense, pkrIncome - pkrExpense)
            ]
        case .incomeTransactions:
            metrics = [("Total Income", income("QAR"), income("PKR"))]
        case .expenseTransactions, .categorySummary:
            metrics = [("Total Expenses", expenses("QAR"), expenses("PKR"))]
        case .transfers:
            metrics = [("Transfers Out", transfers("QAR"), transfers("PKR"))]
        case .balanceSheet:
            let qar = balanceMetrics("QAR")
            let pkr = balanceMetrics("PKR")
            metrics = [
                ("Total Assets", qar.assets, pkr.assets),
                ("Total Liabilities", qar.liabilities, pkr.liabilities),
                ("Net Equity / Balance", qar.equity, pkr.equity)
            ]
        case .payablesAging, .payablesSummary:
            metrics = [("Outstanding Payables", agingOutstanding("QAR", payable: true), agingOutstanding("PKR", payable: true))]
        case .receivablesAging, .receivablesSummary:
            metrics = [("Outstanding Receivables", agingOutstanding("QAR", payable: false), agingOutstanding("PKR", payable: false))]
        }

        guard metrics.contains(where: { $0.1 != 0 || $0.2 != 0 }) else { return nil }
        let rows = metrics.map { metric -> ProfessionalReportRow in
            let pkrInQAR = metric.2 / pkrPerQAR
            return ProfessionalReportRow([
                .text(metric.0),
                .number(metric.1),
                .number(metric.2),
                .number(pkrInQAR),
                .number(metric.1 + pkrInQAR)
            ], emphasis: metric.0.contains("Net") ? .total : .subtotal)
        }
        return ProfessionalReportTable(
            title: "QAR & PKR Consolidated Overview",
            subtitle: "PKR converted at the preset fixed rate: PKR 77 = QAR 1",
            columns: ["Metric", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
            rows: rows
        )
    }

    private static func transactionReport(
        isIncome: Bool,
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let title = isIncome ? "Income Report" : "Expense Report"
        let items = store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            return isIncome ? store.isReportIncome(transaction) : transaction.type == .expense
        }.sorted { $0.date < $1.date }

        var rows = items.map { transaction -> ProfessionalReportRow in
            let accountID = isIncome ? store.reportIncomeAccountID(transaction) : transaction.accountID
            let account = store.account(withID: accountID)
            let currency = account?.currencyCode.uppercased() ?? "QAR"
            let amount = isIncome ? store.reportIncomeAmount(transaction) : transaction.amount
            let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                ? .number(amount)
                : currency == "PKR" ? .number(amount / pkrPerQAR) : .text("—")
            let vendor = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return ProfessionalReportRow([
                .text(shortDate(transaction.date)),
                .text(account?.name ?? "Unassigned"),
                .text(transaction.category),
                .text(vendor.isEmpty ? "—" : vendor),
                .number(amount),
                .text(currency),
                qarEquivalent
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([
                .text("—"), .text("No transactions"), .text("—"), .text("—"), .number(0), .text("QAR"), .number(0)
            ])]
        }
        return ProfessionalReportDocument(
            title: title,
            subtitle: isIncome ? "Income transactions" : "Expense transactions",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: title,
                subtitle: "Native amount retained; QAR equivalent shown for QAR and PKR",
                columns: ["Date", "Account", "Category", "Vendor", "Amount", "Currency", "QAR Eq."],
                rows: rows
            )],
            notes: nativeCurrencyNotes
        )
    }

    private static func transferReport(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let items = store.transactions.filter {
            interval.contains($0.date) && $0.type == .transfer
        }.sorted { $0.date < $1.date }
        var rows = items.map { transaction -> ProfessionalReportRow in
            let source = store.account(withID: transaction.accountID)
            let destination = store.account(withID: transaction.destinationAccountID)
            let currency = source?.currencyCode.uppercased() ?? "QAR"
            let qarEquivalent: ProfessionalReportCell = currency == "QAR"
                ? .number(transaction.amount)
                : currency == "PKR" ? .number(transaction.amount / pkrPerQAR) : .text("—")
            return ProfessionalReportRow([
                .text(shortDate(transaction.date)),
                .text(source?.name ?? "Unassigned"),
                .text(destination?.name ?? "Unassigned"),
                .number(transaction.amount),
                .text(currency),
                qarEquivalent
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([
                .text("—"), .text("No transfers"), .text("—"), .number(0), .text("QAR"), .number(0)
            ])]
        }
        return ProfessionalReportDocument(
            title: "Loans / Transfers",
            subtitle: "Account and loan movements",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Transfer Detail",
                subtitle: "Source currency retained with QAR equivalent",
                columns: ["Date", "From", "To", "Amount", "Currency", "QAR Eq."],
                rows: rows
            )],
            notes: nativeCurrencyNotes
        )
    }

    private static func categoryReport(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var totals: [String: (qar: Decimal, pkr: Decimal)] = [:]
        for transaction in store.transactions where interval.contains(transaction.date) && transaction.type == .expense {
            let currency = store.account(withID: transaction.accountID)?.currencyCode.uppercased() ?? "QAR"
            var value = totals[transaction.category] ?? (0, 0)
            if currency == "PKR" { value.pkr += transaction.amount }
            else if currency == "QAR" { value.qar += transaction.amount }
            totals[transaction.category] = value
        }
        var rows = totals.keys.sorted(by: localizedSort).map { category -> ProfessionalReportRow in
            let value = totals[category] ?? (0, 0)
            let pkrInQAR = value.pkr / pkrPerQAR
            return ProfessionalReportRow([
                .text(category), .number(value.qar), .number(value.pkr), .number(pkrInQAR), .number(value.qar + pkrInQAR)
            ])
        }
        if rows.isEmpty {
            rows = [ProfessionalReportRow([.text("No expenses"), .number(0), .number(0), .number(0), .number(0)])]
        }
        return ProfessionalReportDocument(
            title: "Category Report",
            subtitle: "Expense categories in QAR and PKR",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: [ProfessionalReportTable(
                title: "Expense Categories",
                subtitle: "One readable table with native and consolidated QAR amounts",
                columns: ["Category", "QAR", "PKR", "PKR in QAR", "Consolidated QAR"],
                rows: rows
            )],
            notes: nativeCurrencyNotes
        )
    }

    private static func financialSummary(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        let currencies = reportCurrencies(interval: interval, store: store)

        for currency in currencies {
            let incomeItems = store.transactions.filter {
                interval.contains($0.date) &&
                    store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode.uppercased() == currency
            }
            let expenseItems = store.transactions.filter {
                interval.contains($0.date) &&
                    $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode.uppercased() == currency
            }
            let income = incomeItems.reduce(Decimal.zero) { $0 + store.reportIncomeAmount($1) }
            let expenses = expenseItems.reduce(Decimal.zero) { $0 + $1.amount }
            let net = income - expenses

            let rows: [ProfessionalReportRow] = [
                ProfessionalReportRow([.text("Income"), .number(income), .text("\(incomeItems.count)")]),
                ProfessionalReportRow([.text("Expenses"), .number(expenses), .text("\(expenseItems.count)")]),
                ProfessionalReportRow([.text("Net Result"), .number(net), .text("\(incomeItems.count + expenseItems.count)")], emphasis: .total)
            ]
            tables.append(ProfessionalReportTable(
                title: "Financial Summary — \(currency)",
                subtitle: "Amounts shown in native \(currency)",
                columns: ["Metric", "Amount", "Transactions"],
                rows: rows
            ))
        }

        return ProfessionalReportDocument(
            title: "Financial Summary",
            subtitle: "Income, expenses and net result by currency",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: nativeCurrencyNotes
        )
    }

    private static func incomeStatement(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        let currencies = reportCurrencies(interval: interval, store: store)

        for currency in currencies {
            var revenueByCategory: [String: Decimal] = [:]
            var expenseByCategory: [String: Decimal] = [:]

            for transaction in store.transactions where interval.contains(transaction.date) {
                if store.isReportIncome(transaction),
                   store.account(withID: store.reportIncomeAccountID(transaction))?.currencyCode.uppercased() == currency {
                    revenueByCategory[transaction.category, default: 0] += store.reportIncomeAmount(transaction)
                } else if transaction.type == .expense,
                          store.account(withID: transaction.accountID)?.currencyCode.uppercased() == currency {
                    expenseByCategory[transaction.category, default: 0] += transaction.amount
                }
            }

            let totalRevenue = revenueByCategory.values.reduce(Decimal.zero, +)
            let totalExpenses = expenseByCategory.values.reduce(Decimal.zero, +)
            var rows: [ProfessionalReportRow] = []

            rows.append(ProfessionalReportRow([.text("REVENUE"), .text("")], emphasis: .section))
            if revenueByCategory.isEmpty {
                rows.append(ProfessionalReportRow([.text("No revenue recorded"), .number(0)]))
            } else {
                for category in revenueByCategory.keys.sorted(by: localizedSort) {
                    rows.append(ProfessionalReportRow([.text(category), .number(revenueByCategory[category, default: 0])]))
                }
            }
            rows.append(ProfessionalReportRow([.text("Total Revenue"), .number(totalRevenue)], emphasis: .subtotal))

            rows.append(ProfessionalReportRow([.text("EXPENSES"), .text("")], emphasis: .section))
            if expenseByCategory.isEmpty {
                rows.append(ProfessionalReportRow([.text("No expenses recorded"), .number(0)]))
            } else {
                for category in expenseByCategory.keys.sorted(by: localizedSort) {
                    rows.append(ProfessionalReportRow([.text(category), .number(expenseByCategory[category, default: 0])]))
                }
            }
            rows.append(ProfessionalReportRow([.text("Total Expenses"), .number(totalExpenses)], emphasis: .subtotal))
            rows.append(ProfessionalReportRow([
                .text(totalRevenue - totalExpenses >= 0 ? "Net Profit" : "Net Loss"),
                .number(totalRevenue - totalExpenses)
            ], emphasis: .total))

            tables.append(ProfessionalReportTable(
                title: "Income Statement — \(currency)",
                subtitle: "Revenue and expenses in native \(currency)",
                columns: ["Category", "Amount"],
                rows: rows
            ))
        }

        return ProfessionalReportDocument(
            title: "Income Statement",
            subtitle: "Revenue, expenses and profit or loss",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: nativeCurrencyNotes
        )
    }

    private static func balanceSheet(
        interval: DateInterval,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        var tables: [ProfessionalReportTable] = []
        let currencies = Array(Set(store.activeAccounts.map { $0.currencyCode.uppercased() })).sorted()

        for currency in currencies {
            let lines = store.activeAccounts
                .filter { $0.currencyCode.uppercased() == currency }
                .compactMap { account -> AccountBalanceLine? in
                    let opening = store.combinedBalance(for: [account], before: interval.start)
                    let closing = store.combinedBalance(for: [account], before: interval.end)
                    let movement = closing - opening
                    guard opening != 0 || movement != 0 || closing != 0 else { return nil }
                    return AccountBalanceLine(
                        account: account,
                        opening: opening,
                        movement: movement,
                        closing: closing,
                        section: balanceSection(account: account, closing: closing)
                    )
                }

            var rows: [ProfessionalReportRow] = []
            for section in BalanceSheetSection.allCases {
                let sectionLines = lines
                    .filter { $0.section == section }
                    .sorted { localizedSort($0.account.name, $1.account.name) }
                guard !sectionLines.isEmpty else { continue }
                rows.append(ProfessionalReportRow([
                    .text(""), .text(section.rawValue), .text(""), .text(""), .text("")
                ], emphasis: .section))

                for line in sectionLines {
                    let multiplier: Decimal = section.isLiability ? -1 : 1
                    rows.append(ProfessionalReportRow([
                        .text(chartCodeText(line.account)),
                        .text(line.account.name),
                        .number(line.opening * multiplier),
                        .number(line.movement * multiplier),
                        .number(line.closing * multiplier)
                    ]))
                }

                let sectionOpening = sectionLines.reduce(Decimal.zero) { $0 + $1.opening }
                let sectionMovement = sectionLines.reduce(Decimal.zero) { $0 + $1.movement }
                let sectionClosing = sectionLines.reduce(Decimal.zero) { $0 + $1.closing }
                let multiplier: Decimal = section.isLiability ? -1 : 1
                rows.append(ProfessionalReportRow([
                    .text(""),
                    .text("Total \(section.rawValue)"),
                    .number(sectionOpening * multiplier),
                    .number(sectionMovement * multiplier),
                    .number(sectionClosing * multiplier)
                ], emphasis: .subtotal))
            }

            if rows.isEmpty {
                rows.append(ProfessionalReportRow([
                    .text("—"), .text("No account balances for this period"), .number(0), .number(0), .number(0)
                ]))
            }

            tables.append(ProfessionalReportTable(
                title: "Balance Sheet Detail — \(currency)",
                subtitle: "Opening, period movement and closing balances",
                columns: ["Code", "Account", "Opening", "Movement", "Closing"],
                rows: rows
            ))

            let totalAssets = lines.filter { !$0.section.isLiability }
                .reduce(Decimal.zero) { $0 + decimalAbs($1.closing) }
            let totalLiabilities = lines.filter { $0.section.isLiability }
                .reduce(Decimal.zero) { $0 + decimalAbs($1.closing) }
            let equity = totalAssets - totalLiabilities
            tables.append(ProfessionalReportTable(
                title: "Balance Sheet Summary — \(currency)",
                subtitle: "Balanced presentation in native \(currency)",
                columns: ["Metric", "Amount"],
                rows: [
                    ProfessionalReportRow([.text("Total Assets"), .number(totalAssets)], emphasis: .subtotal),
                    ProfessionalReportRow([.text("Total Liabilities"), .number(totalLiabilities)], emphasis: .subtotal),
                    ProfessionalReportRow([.text("Net Equity / Accumulated Balance"), .number(equity)], emphasis: .subtotal),
                    ProfessionalReportRow([.text("Total Liabilities & Equity"), .number(totalLiabilities + equity)], emphasis: .total)
                ]
            ))
        }

        return ProfessionalReportDocument(
            title: "Balance Sheet",
            subtitle: "Assets, receivables, liabilities and equity",
            periodText: periodText(interval),
            generatedAt: Date(),
            tables: tables,
            notes: nativeCurrencyNotes + [
                "Net Equity / Accumulated Balance is the balancing figure derived from account balances.",
                "Payment accounts are presented dynamically: positive balances are receivables and negative balances are payables."
            ]
        )
    }

    private static func agingReport(
        isPayable: Bool,
        detailed: Bool,
        asOf: Date,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let cutoff = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: asOf)) ?? asOf
        let candidates = store.activeAccounts.filter(isAgingAccount)
        let matching = candidates.filter { account in
            let balance = store.combinedBalance(for: [account], before: cutoff)
            return isPayable ? balance < 0 : balance > 0
        }
        let currencies = Array(Set(matching.map { $0.currencyCode.uppercased() })).sorted()
        var tables: [ProfessionalReportTable] = []

        for currency in currencies {
            let accounts = matching
                .filter { $0.currencyCode.uppercased() == currency }
                .sorted { localizedSort($0.name, $1.name) }
            var rows: [ProfessionalReportRow] = []
            var currencyTotal = AgingBuckets()

            for account in accounts {
                let lots = openAgingLots(account: account, isPayable: isPayable, asOf: asOf, cutoff: cutoff, store: store)
                var accountBuckets = AgingBuckets()

                if detailed {
                    for lot in lots.sorted(by: { $0.date < $1.date }) {
                        let days = agingDays(from: lot.date, to: asOf)
                        var buckets = AgingBuckets()
                        buckets.add(amount: lot.amount, days: days)
                        accountBuckets.add(buckets)
                        rows.append(ProfessionalReportRow([
                            .text(lot.reference == "Opening balance" ? "Opening" : shortDate(lot.date)),
                            .text(account.name),
                            .text(lot.reference),
                            .number(buckets.current),
                            .number(buckets.days31To60),
                            .number(buckets.days61To90),
                            .number(buckets.over90),
                            .number(buckets.total)
                        ]))
                    }
                    rows.append(ProfessionalReportRow([
                        .text(""), .text(account.name), .text("Account Total"),
                        .number(accountBuckets.current),
                        .number(accountBuckets.days31To60),
                        .number(accountBuckets.days61To90),
                        .number(accountBuckets.over90),
                        .number(accountBuckets.total)
                    ], emphasis: .subtotal))
                } else {
                    for lot in lots {
                        accountBuckets.add(amount: lot.amount, days: agingDays(from: lot.date, to: asOf))
                    }
                    rows.append(ProfessionalReportRow([
                        .text(account.name),
                        .number(accountBuckets.current),
                        .number(accountBuckets.days31To60),
                        .number(accountBuckets.days61To90),
                        .number(accountBuckets.over90),
                        .number(accountBuckets.total)
                    ]))
                }
                currencyTotal.add(accountBuckets)
            }

            if detailed {
                rows.append(ProfessionalReportRow([
                    .text(""), .text("\(currency) Total"), .text("Grand Total"),
                    .number(currencyTotal.current),
                    .number(currencyTotal.days31To60),
                    .number(currencyTotal.days61To90),
                    .number(currencyTotal.over90),
                    .number(currencyTotal.total)
                ], emphasis: .total))
            } else {
                rows.append(ProfessionalReportRow([
                    .text("\(currency) Total"),
                    .number(currencyTotal.current),
                    .number(currencyTotal.days31To60),
                    .number(currencyTotal.days61To90),
                    .number(currencyTotal.over90),
                    .number(currencyTotal.total)
                ], emphasis: .total))
            }

            let side = isPayable ? "Payables" : "Receivables"
            tables.append(ProfessionalReportTable(
                title: "\(side) \(detailed ? "Aging" : "Summary") — \(currency)",
                subtitle: "Outstanding balances as of \(shortDate(asOf))",
                columns: detailed
                    ? ["Date", "Account", "Reference", "0–30", "31–60", "61–90", "90+", "Total"]
                    : ["Account", "0–30", "31–60", "61–90", "90+", "Total"],
                rows: rows
            ))
        }

        if tables.isEmpty {
            tables = [ProfessionalReportTable(
                title: isPayable ? "Payables" : "Receivables",
                subtitle: "As of \(shortDate(asOf))",
                columns: ["Status", "Amount"],
                rows: [ProfessionalReportRow([
                    .text("No outstanding \(isPayable ? "payables" : "receivables")"), .number(0)
                ], emphasis: .total)]
            )]
        }

        let title = "\(isPayable ? "Payables" : "Receivables") \(detailed ? "Aging" : "Summary")"
        return ProfessionalReportDocument(
            title: title,
            subtitle: detailed ? "Detailed open-item aging" : "Account-level aging summary",
            periodText: "As of \(shortDate(asOf))",
            generatedAt: Date(),
            tables: tables,
            notes: nativeCurrencyNotes + [
                "Aging is calculated from transaction dates using FIFO settlement allocation.",
                "Opening balances are included in the 90+ bucket because their original invoice dates are not stored.",
                "Payments and Control accounts are classified from their balance as of the selected date."
            ]
        )
    }

    private static func reportCurrencies(interval: DateInterval, store: LedgerStore) -> [String] {
        var values = Set<String>()
        for transaction in store.transactions where interval.contains(transaction.date) {
            if store.isReportIncome(transaction),
               let code = store.account(withID: store.reportIncomeAccountID(transaction))?.currencyCode {
                values.insert(code.uppercased())
            }
            if transaction.type == .expense,
               let code = store.account(withID: transaction.accountID)?.currencyCode {
                values.insert(code.uppercased())
            }
        }
        if values.isEmpty { values.insert(store.currencyCode.uppercased()) }
        return values.sorted()
    }

    private static func chartCodeText(_ account: LedgerAccount) -> String {
        let value = account.chartCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "—" : value
    }

    private static func balanceSection(account: LedgerAccount, closing: Decimal) -> BalanceSheetSection {
        let isPaymentControl = account.group == .payments ||
            account.nature == .control ||
            account.nature == .receivable ||
            account.nature == .payable
        if isPaymentControl {
            if closing < 0 || (closing == 0 && account.openingBalance < 0) { return .payables }
            return .receivables
        }
        if account.nature == .loan { return .loans }
        if closing < 0 { return .otherLiabilities }
        return .assets
    }

    private static func isAgingAccount(_ account: LedgerAccount) -> Bool {
        account.group == .payments ||
            account.nature == .control ||
            account.nature == .receivable ||
            account.nature == .payable
    }

    private static func openAgingLots(
        account: LedgerAccount,
        isPayable: Bool,
        asOf: Date,
        cutoff: Date,
        store: LedgerStore
    ) -> [AgingLot] {
        let polarity: Decimal = isPayable ? -1 : 1
        var lots: [AgingLot] = []
        var unappliedSettlement: Decimal = 0
        let oldDate = Calendar.current.date(byAdding: .day, value: -3650, to: asOf) ?? Date.distantPast

        func applySettlement(_ amount: Decimal) {
            var remaining = amount
            while remaining > 0 && !lots.isEmpty {
                let applied = min(remaining, lots[0].amount)
                lots[0].amount -= applied
                remaining -= applied
                if lots[0].amount <= 0 { lots.removeFirst() }
            }
            if remaining > 0 { unappliedSettlement += remaining }
        }

        func addCharge(_ amount: Decimal, date: Date, reference: String) {
            var remaining = amount
            if unappliedSettlement > 0 {
                let applied = min(remaining, unappliedSettlement)
                remaining -= applied
                unappliedSettlement -= applied
            }
            if remaining > 0 {
                lots.append(AgingLot(amount: remaining, date: date, reference: reference))
            }
        }

        let normalizedOpening = account.openingBalance * polarity
        if normalizedOpening > 0 {
            addCharge(normalizedOpening, date: oldDate, reference: "Opening balance")
        } else if normalizedOpening < 0 {
            applySettlement(decimalAbs(normalizedOpening))
        }

        let movements = store.transactions
            .filter { $0.date < cutoff && ($0.accountID == account.id || $0.destinationAccountID == account.id) }
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.createdAt < $1.createdAt
            }

        for transaction in movements {
            let normalized = signedMovement(transaction, accountID: account.id, store: store) * polarity
            if normalized > 0 {
                addCharge(normalized, date: transaction.date, reference: transactionReference(transaction))
            } else if normalized < 0 {
                applySettlement(decimalAbs(normalized))
            }
        }

        let closing = store.combinedBalance(for: [account], before: cutoff)
        let expected = decimalAbs(closing)
        let calculated = lots.reduce(Decimal.zero) { $0 + $1.amount }
        if calculated > expected {
            applySettlement(calculated - expected)
        } else if calculated < expected {
            lots.append(AgingLot(
                amount: expected - calculated,
                date: Calendar.current.startOfDay(for: asOf),
                reference: "Balance adjustment"
            ))
        }
        return lots.filter { $0.amount > 0 }
    }

    private static func signedMovement(_ transaction: LedgerTransaction, accountID: UUID, store: LedgerStore) -> Decimal {
        var movement: Decimal = 0
        if transaction.accountID == accountID {
            switch transaction.type {
            case .income:
                movement += transaction.amount
            case .expense, .transfer:
                movement -= transaction.amount
            }
        }
        if transaction.type == .transfer, transaction.destinationAccountID == accountID {
            movement += store.effectiveDestinationAmount(transaction)
        }
        return movement
    }

    private static func transactionReference(_ transaction: LedgerTransaction) -> String {
        if let vendor = transaction.vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !vendor.isEmpty {
            return vendor
        }
        let details = transaction.details
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty { return String(details.prefix(72)) }
        return transaction.category
    }

    private static func agingDays(from date: Date, to asOf: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: asOf)
        return max(calendar.dateComponents([.day], from: from, to: to).day ?? 0, 0)
    }

    private static func localizedSort(_ left: String, _ right: String) -> Bool {
        left.localizedCaseInsensitiveCompare(right) == .orderedAscending
    }

    private static func decimalAbs(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }

    private static func shortDate(_ date: Date) -> String {
        ReportDateFormatters.short.string(from: date)
    }

    private static func periodText(_ interval: DateInterval) -> String {
        let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(shortDate(interval.start)) – \(shortDate(inclusiveEnd))"
    }

    private static let nativeCurrencyNotes = [
        "QAR and PKR are shown together. Consolidated totals use the preset fixed rate PKR 77 = QAR 1.",
        "Native QAR and PKR amounts remain visible for checking and reconciliation.",
        "Currencies other than QAR and PKR remain in their native amount without forced conversion."
    ]
}


@MainActor
extension ProfessionalReportBuilder {
    static func accountStatement(
        accountID: UUID,
        startDate: Date,
        endDate: Date,
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let ids = store.relatedAccountIDs(for: accountID)
        let selectedAccounts = store.accounts.filter { ids.contains($0.id) }
        let accountName = store.account(withID: accountID)?.name ?? "Account"
        let currencies = Array(Set(selectedAccounts.map { $0.currencyCode.uppercased() })).sorted()
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "dd-MMM-yyyy"
            return formatter
        }()
        let period = "\(dateFormatter.string(from: start)) – \(dateFormatter.string(from: endDay))"
        var tables: [ProfessionalReportTable] = []

        for currency in currencies {
            let currencyAccounts = selectedAccounts.filter { $0.currencyCode.uppercased() == currency }
            let currencyIDs = Set(currencyAccounts.map(\.id))
            let opening = store.combinedBalance(for: currencyAccounts, before: start)
            let relevant = store.transactions.filter { tx in
                guard tx.date >= start && tx.date < endExclusive else { return false }
                return tx.accountID.map(currencyIDs.contains) == true ||
                    tx.destinationAccountID.map(currencyIDs.contains) == true
            }.sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                return $0.createdAt < $1.createdAt
            }

            func movement(_ tx: LedgerTransaction) -> Decimal {
                var result: Decimal = 0
                if tx.accountID.map(currencyIDs.contains) == true {
                    switch tx.type {
                    case .income: result += tx.amount
                    case .expense, .transfer: result -= tx.amount
                    }
                }
                if tx.type == .transfer,
                   tx.destinationAccountID.map(currencyIDs.contains) == true {
                    result += store.effectiveDestinationAmount(tx)
                }
                return result
            }

            let income = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .income, tx.accountID.map(currencyIDs.contains) == true else { return total }
                return total + tx.amount
            }
            let expenses = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .expense, tx.accountID.map(currencyIDs.contains) == true else { return total }
                return total + tx.amount
            }
            let transfersIn = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .transfer, tx.destinationAccountID.map(currencyIDs.contains) == true else { return total }
                return total + store.effectiveDestinationAmount(tx)
            }
            let transfersOut = relevant.reduce(Decimal.zero) { total, tx in
                guard tx.type == .transfer, tx.accountID.map(currencyIDs.contains) == true else { return total }
                return total + tx.amount
            }
            let closing = relevant.reduce(opening) { $0 + movement($1) }

            tables.append(ProfessionalReportTable(
                title: "Account Summary — \(currency)",
                subtitle: accountName,
                columns: ["Measure", "Amount"],
                rows: [
                    ProfessionalReportRow([.text("Opening Balance"), .number(opening)]),
                    ProfessionalReportRow([.text("Income / Refunds"), .number(income)]),
                    ProfessionalReportRow([.text("Expenses"), .number(expenses)]),
                    ProfessionalReportRow([.text("Transfers In"), .number(transfersIn)]),
                    ProfessionalReportRow([.text("Transfers Out"), .number(transfersOut)]),
                    ProfessionalReportRow([.text("Closing Balance"), .number(closing)], emphasis: .total)
                ]
            ))

            let expenseGroups = Dictionary(grouping: relevant.filter {
                $0.type == .expense && $0.accountID.map(currencyIDs.contains) == true
            }, by: { $0.category })
            let expenseRows = expenseGroups.keys.sorted().map { category in
                ProfessionalReportRow([
                    .text(category),
                    .number(expenseGroups[category, default: []].reduce(Decimal.zero) { $0 + $1.amount })
                ])
            }
            tables.append(ProfessionalReportTable(
                title: "Expense Summary — \(currency)",
                subtitle: "Expenses by category",
                columns: ["Category", "Amount"],
                rows: expenseRows.isEmpty
                    ? [ProfessionalReportRow([.text("No expenses"), .number(0)])]
                    : expenseRows + [ProfessionalReportRow([.text("Total Expenses"), .number(expenses)], emphasis: .total)]
            ))

            var running = opening
            var detailRows: [ProfessionalReportRow] = []
            for tx in relevant {
                let delta = movement(tx)
                running += delta
                let description: String = {
                    if let vendor = tx.vendor?.trimmingCharacters(in: .whitespacesAndNewlines), !vendor.isEmpty {
                        return tx.details.isEmpty ? vendor : "\(vendor) · \(tx.details)"
                    }
                    return tx.details.isEmpty ? tx.category : tx.details
                }()
                detailRows.append(ProfessionalReportRow([
                    .text(dateFormatter.string(from: tx.date)),
                    .text(tx.type.title),
                    .text(tx.category),
                    .text(description),
                    .number(delta < 0 ? -delta : 0),
                    .number(delta > 0 ? delta : 0),
                    .number(running)
                ]))
            }
            tables.append(ProfessionalReportTable(
                title: "Transaction Details — \(currency)",
                subtitle: "Complete account activity",
                columns: ["Date", "Nature", "Category", "Description", "Money Out", "Money In", "Balance"],
                rows: detailRows.isEmpty
                    ? [ProfessionalReportRow([.text("No transactions"), .text("—"), .text("—"), .text("—"), .number(0), .number(0), .number(opening)])]
                    : detailRows
            ))
        }

        return ProfessionalReportDocument(
            title: "\(accountName) Account Statement",
            subtitle: "Summary, expense analysis and full transaction detail",
            periodText: period,
            generatedAt: Date(),
            tables: tables,
            notes: [
                "Balances are rebuilt from opening balances and saved ledger transactions.",
                "Legacy QAR/PKR/USD transfers without a stored destination amount use the app's fixed conversion rates.",
                "Main-account statements include direct sub-accounts, including archived sub-accounts with historical balances."
            ]
        )
    }
}

enum ProfessionalReportExporter {
    static func export(
        _ document: ProfessionalReportDocument,
        format: ProfessionalExportFormat
    ) throws -> URL {
        cleanupOldFiles()
        switch format {
        case .pdf:
            return try exportPDF(document)
        case .excel:
            return try exportExcel(document)
        }
    }

    private static func shouldIncludeTable(_ table: ProfessionalReportTable) -> Bool {
        if table.title.hasPrefix("Financial Summary —") || table.title.hasPrefix("Balance Sheet Summary —") {
            return false
        }
        let blocked = ["no account balances", "no transactions", "no reviewed", "no data"]
        var meaningfulText = false
        var nonZeroNumber = false
        for row in table.rows {
            for cell in row.cells {
                switch cell {
                case .number(let value):
                    if value != 0 { nonZeroNumber = true }
                case .text(let value):
                    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !clean.isEmpty && !blocked.contains(where: { clean.contains($0) }) {
                        meaningfulText = true
                    }
                }
            }
        }
        return nonZeroNumber || (meaningfulText && !table.rows.isEmpty)
    }

    private static func exportPDF(_ document: ProfessionalReportDocument) throws -> URL {
        let url = reportURL(document: document, extension: "pdf")
        let visibleTables = document.tables.filter(shouldIncludeTable)
        let isWide = visibleTables.contains { $0.columns.count >= 7 }
        let pageRect = isWide
            ? CGRect(x: 0, y: 0, width: 841.8, height: 595.2)
            : CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Next Ledger",
            kCGPDFContextAuthor as String: "Next Solution – Zeeshan Barvi",
            kCGPDFContextTitle as String: document.title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            let margin: CGFloat = 30
            let contentWidth = pageRect.width - margin * 2
            let green = UIColor(red: 0.125, green: 0.353, blue: 0.278, alpha: 1)
            let darkGreen = UIColor(red: 0.075, green: 0.235, blue: 0.180, alpha: 1)
            let lightGreen = UIColor(red: 0.925, green: 0.965, blue: 0.945, alpha: 1)
            let grid = UIColor(white: 0.84, alpha: 1)
            var pageNumber = 0
            var cursorY: CGFloat = 0

            func paragraphStyle(_ alignment: NSTextAlignment, lineBreak: NSLineBreakMode = .byWordWrapping) -> NSMutableParagraphStyle {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                style.lineBreakMode = lineBreak
                style.lineSpacing = 0.8
                return style
            }

            func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
                guard width > 2 else { return font.lineHeight }
                let rect = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: font, .paragraphStyle: paragraphStyle(.left)],
                    context: nil
                )
                return ceil(rect.height)
            }

            func drawText(
                _ text: String,
                rect: CGRect,
                font: UIFont,
                color: UIColor,
                alignment: NSTextAlignment = .left
            ) {
                (text as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: paragraphStyle(alignment)
                    ],
                    context: nil
                )
            }

            func cellString(_ cell: ProfessionalReportCell) -> String {
                switch cell {
                case .text(let value): return value
                case .number(let value):
                    return ReportNumberFormatters.decimal.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
                }
            }

            func drawFooter() {
                let lineY = pageRect.height - 24
                grid.setFill()
                UIBezierPath(rect: CGRect(x: margin, y: lineY - 5, width: contentWidth, height: 0.5)).fill()
                drawText(
                    "Next Ledger • \(document.title) • Generated \(ReportDateFormatters.timestamp.string(from: document.generatedAt))",
                    rect: CGRect(x: margin, y: lineY, width: contentWidth - 70, height: 14),
                    font: .systemFont(ofSize: 7.2),
                    color: UIColor(white: 0.40, alpha: 1)
                )
                drawText(
                    "Page \(pageNumber)",
                    rect: CGRect(x: pageRect.width - margin - 65, y: lineY, width: 65, height: 14),
                    font: .systemFont(ofSize: 7.2, weight: .semibold),
                    color: UIColor(white: 0.40, alpha: 1),
                    alignment: .right
                )
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                green.setFill()
                UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 58)).fill()
                drawText("NEXT LEDGER", rect: CGRect(x: margin, y: 10, width: 160, height: 14), font: .systemFont(ofSize: 8.5, weight: .heavy), color: .white)
                drawText(document.title, rect: CGRect(x: margin, y: 23, width: contentWidth, height: 24), font: .systemFont(ofSize: 17, weight: .bold), color: .white)
                drawText(document.periodText, rect: CGRect(x: margin, y: 45, width: contentWidth, height: 12), font: .systemFont(ofSize: 7.8, weight: .medium), color: UIColor.white.withAlphaComponent(0.86))
                cursorY = 70
            }

            func ensureSpace(_ height: CGFloat) {
                if cursorY + height > pageRect.height - 34 {
                    drawFooter()
                    beginPage()
                }
            }

            func columnWidths(for table: ProfessionalReportTable) -> [CGFloat] {
                let names = table.columns.map { $0.lowercased() }
                if table.columns.count == 2 { return [contentWidth * 0.69, contentWidth * 0.31] }
                if table.columns.count == 3 { return [contentWidth * 0.50, contentWidth * 0.29, contentWidth * 0.21] }
                if table.columns.count == 5 {
                    if names.contains("code") && names.contains("account") {
                        return [contentWidth * 0.12, contentWidth * 0.34, contentWidth * 0.18, contentWidth * 0.18, contentWidth * 0.18]
                    }
                    return [contentWidth * 0.27, contentWidth * 0.16, contentWidth * 0.19, contentWidth * 0.19, contentWidth * 0.19]
                }
                if table.columns.count == 6 {
                    return [contentWidth * 0.13, contentWidth * 0.22, contentWidth * 0.22, contentWidth * 0.15, contentWidth * 0.12, contentWidth * 0.16]
                }
                if table.columns.count == 7 {
                    return [contentWidth * 0.10, contentWidth * 0.17, contentWidth * 0.17, contentWidth * 0.20, contentWidth * 0.13, contentWidth * 0.09, contentWidth * 0.14]
                }
                if table.columns.count == 8 {
                    return [contentWidth * 0.10, contentWidth * 0.15, contentWidth * 0.22, contentWidth * 0.11, contentWidth * 0.105, contentWidth * 0.105, contentWidth * 0.105, contentWidth * 0.105]
                }
                return Array(repeating: contentWidth / CGFloat(max(table.columns.count, 1)), count: max(table.columns.count, 1))
            }

            func tableHeaderHeight(_ table: ProfessionalReportTable, widths: [CGFloat]) -> CGFloat {
                let font = UIFont.systemFont(ofSize: 7.2, weight: .bold)
                let heights = table.columns.enumerated().map { index, title in
                    textHeight(title, width: widths[index] - 10, font: font)
                }
                return max(23, (heights.max() ?? 10) + 10)
            }

            func drawTableHeader(_ table: ProfessionalReportTable, widths: [CGFloat]) {
                let height = tableHeaderHeight(table, widths: widths)
                green.setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: cursorY, width: contentWidth, height: height), cornerRadius: 4).fill()
                var x = margin
                for (index, column) in table.columns.enumerated() {
                    let width = widths[index]
                    drawText(
                        column,
                        rect: CGRect(x: x + 5, y: cursorY + 5, width: width - 10, height: height - 8),
                        font: .systemFont(ofSize: 7.2, weight: .bold),
                        color: .white,
                        alignment: index > 0 && !["account", "category", "vendor", "from account", "to account"].contains(column.lowercased()) ? .right : .left
                    )
                    x += width
                }
                cursorY += height
            }

            func rowHeight(_ row: ProfessionalReportRow, table: ProfessionalReportTable, widths: [CGFloat]) -> CGFloat {
                let font = UIFont.systemFont(ofSize: table.columns.count >= 7 ? 6.6 : 7.3, weight: row.emphasis == .normal ? .regular : .semibold)
                var height: CGFloat = 20
                for index in table.columns.indices {
                    let cell = index < row.cells.count ? row.cells[index] : .text("")
                    height = max(height, textHeight(cellString(cell), width: widths[index] - 10, font: font) + 9)
                }
                return min(max(height, 21), 52)
            }

            func drawStandardTable(_ table: ProfessionalReportTable) {
                ensureSpace(64)
                let titleFont = UIFont.systemFont(ofSize: 11.5, weight: .bold)
                let titleHeight = textHeight(table.title, width: contentWidth, font: titleFont)
                drawText(table.title, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: titleHeight + 2), font: titleFont, color: darkGreen)
                cursorY += titleHeight + 4
                if !table.subtitle.isEmpty {
                    let subtitleFont = UIFont.systemFont(ofSize: 7.8)
                    let subtitleHeight = textHeight(table.subtitle, width: contentWidth, font: subtitleFont)
                    drawText(table.subtitle, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: subtitleHeight + 2), font: subtitleFont, color: UIColor(white: 0.38, alpha: 1))
                    cursorY += subtitleHeight + 5
                }
                let widths = columnWidths(for: table)
                drawTableHeader(table, widths: widths)
                for (rowIndex, row) in table.rows.enumerated() {
                    let height = rowHeight(row, table: table, widths: widths)
                    if cursorY + height > pageRect.height - 34 {
                        drawFooter()
                        beginPage()
                        drawText("\(table.title) — continued", rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18), font: .systemFont(ofSize: 10, weight: .bold), color: darkGreen)
                        cursorY += 20
                        drawTableHeader(table, widths: widths)
                    }
                    let fill: UIColor
                    switch row.emphasis {
                    case .section: fill = lightGreen
                    case .subtotal: fill = UIColor(red: 0.90, green: 0.94, blue: 0.92, alpha: 1)
                    case .total: fill = green
                    case .normal: fill = rowIndex.isMultiple(of: 2) ? .white : UIColor(white: 0.975, alpha: 1)
                    }
                    fill.setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: height)).fill()
                    var x = margin
                    for index in table.columns.indices {
                        let width = widths[index]
                        let cell = index < row.cells.count ? row.cells[index] : .text("")
                        let numeric: Bool
                        if case .number = cell { numeric = true } else { numeric = false }
                        let font = UIFont.systemFont(ofSize: table.columns.count >= 7 ? 6.6 : 7.3, weight: row.emphasis == .normal ? .regular : .semibold)
                        drawText(
                            cellString(cell),
                            rect: CGRect(x: x + 5, y: cursorY + 4, width: width - 10, height: height - 7),
                            font: font,
                            color: row.emphasis == .total ? .white : UIColor(white: 0.16, alpha: 1),
                            alignment: numeric ? .right : .left
                        )
                        grid.setFill()
                        UIBezierPath(rect: CGRect(x: x + width - 0.35, y: cursorY, width: 0.35, height: height)).fill()
                        x += width
                    }
                    cursorY += height
                }
                cursorY += 10
            }

            func drawSampleCSummary(_ table: ProfessionalReportTable) {
                ensureSpace(CGFloat(76 + table.rows.count * 18))
                let heading = table.title.replacingOccurrences(of: "Consolidated ", with: "")
                drawText(heading, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18), font: .systemFont(ofSize: 11.5, weight: .bold), color: darkGreen)
                cursorY += 19
                drawText(table.subtitle, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 15), font: .systemFont(ofSize: 7.5), color: UIColor(white: 0.40, alpha: 1))
                cursorY += 18

                let gap: CGFloat = 10
                let panelWidth = (contentWidth - gap) / 2
                let panelHeight = CGFloat(28 + table.rows.count * 18)
                for (panelIndex, currency) in ["QAR", "PKR"].enumerated() {
                    let x = margin + CGFloat(panelIndex) * (panelWidth + gap)
                    lightGreen.setFill()
                    UIBezierPath(roundedRect: CGRect(x: x, y: cursorY, width: panelWidth, height: panelHeight), cornerRadius: 7).fill()
                    drawText(currency, rect: CGRect(x: x + 10, y: cursorY + 8, width: panelWidth - 20, height: 16), font: .systemFont(ofSize: 10.5, weight: .bold), color: darkGreen)
                    for (rowIndex, row) in table.rows.enumerated() {
                        let label = row.cells.indices.contains(0) ? cellString(row.cells[0]) : ""
                        let valueIndex = currency == "QAR" ? 1 : 2
                        let value = row.cells.indices.contains(valueIndex) ? cellString(row.cells[valueIndex]) : "0.00"
                        let y = cursorY + 27 + CGFloat(rowIndex * 18)
                        drawText(label, rect: CGRect(x: x + 10, y: y, width: panelWidth * 0.55, height: 15), font: .systemFont(ofSize: 7.2), color: UIColor(white: 0.30, alpha: 1))
                        drawText(value, rect: CGRect(x: x + panelWidth * 0.55, y: y, width: panelWidth * 0.45 - 10, height: 15), font: .systemFont(ofSize: 7.4, weight: .semibold), color: darkGreen, alignment: .right)
                    }
                }
                cursorY += panelHeight + 8
                if let last = table.rows.last {
                    let label = last.cells.indices.contains(0) ? cellString(last.cells[0]) : "Consolidated Total"
                    let value = last.cells.indices.contains(4) ? cellString(last.cells[4]) : "0.00"
                    UIColor(red: 0.86, green: 0.94, blue: 0.90, alpha: 1).setFill()
                    UIBezierPath(roundedRect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 32), cornerRadius: 7).fill()
                    drawText("Consolidated QAR — \(label)", rect: CGRect(x: margin + 10, y: cursorY + 9, width: contentWidth * 0.58, height: 16), font: .systemFont(ofSize: 8, weight: .semibold), color: darkGreen)
                    drawText("QAR \(value)", rect: CGRect(x: margin + contentWidth * 0.58, y: cursorY + 7, width: contentWidth * 0.42 - 10, height: 18), font: .systemFont(ofSize: 12, weight: .bold), color: darkGreen, alignment: .right)
                    cursorY += 42
                }
            }

            beginPage()
            if !document.subtitle.isEmpty {
                let subtitleFont = UIFont.systemFont(ofSize: 9, weight: .medium)
                let subtitleHeight = textHeight(document.subtitle, width: contentWidth, font: subtitleFont)
                drawText(document.subtitle, rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: subtitleHeight + 2), font: subtitleFont, color: UIColor(white: 0.25, alpha: 1))
                cursorY += subtitleHeight + 10
            }

            for table in visibleTables {
                if table.title.contains("QAR & PKR") && table.columns.count == 5 {
                    drawSampleCSummary(table)
                } else {
                    drawStandardTable(table)
                }
            }

            let conciseNotes = Array(document.notes.prefix(2))
            if !conciseNotes.isEmpty {
                ensureSpace(CGFloat(28 + conciseNotes.count * 22))
                drawText("Report Notes", rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18), font: .systemFont(ofSize: 10.5, weight: .bold), color: darkGreen)
                cursorY += 20
                for note in conciseNotes {
                    let font = UIFont.systemFont(ofSize: 7.4)
                    let height = textHeight("• \(note)", width: contentWidth - 8, font: font)
                    drawText("• \(note)", rect: CGRect(x: margin + 4, y: cursorY, width: contentWidth - 8, height: height + 2), font: font, color: UIColor(white: 0.36, alpha: 1))
                    cursorY += height + 6
                }
            }
            drawFooter()
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func exportExcel(_ document: ProfessionalReportDocument) throws -> URL {
        let url = reportURL(document: document, extension: "xlsx")
        var files: [(String, Data)] = []
        let filteredTables = document.tables.filter(shouldIncludeTable)
        let tables = filteredTables.isEmpty
            ? [ProfessionalReportTable(title: document.title, subtitle: document.subtitle, columns: ["Status"], rows: [ProfessionalReportRow([.text("No data")])])]
            : filteredTables
        let sheetNames = uniqueSheetNames(tables.map(\.title))

        files.append(("[Content_Types].xml", Data(contentTypesXML(sheetCount: tables.count).utf8)))
        files.append(("_rels/.rels", Data(rootRelationshipsXML.utf8)))
        files.append(("xl/workbook.xml", Data(workbookXML(sheetNames: sheetNames).utf8)))
        files.append(("xl/_rels/workbook.xml.rels", Data(workbookRelationshipsXML(sheetCount: tables.count).utf8)))
        files.append(("xl/styles.xml", Data(stylesXML.utf8)))

        for index in tables.indices {
            let xml = worksheetXML(document: document, table: tables[index])
            files.append(("xl/worksheets/sheet\(index + 1).xml", Data(xml.utf8)))
        }

        let archive = StoredZipArchive.make(files: files)
        try archive.write(to: url, options: .atomic)
        return url
    }

    private static func worksheetXML(
        document: ProfessionalReportDocument,
        table: ProfessionalReportTable
    ) -> String {
        let columnCount = max(table.columns.count, 1)
        let lastColumn = excelColumnName(columnCount)
        let headerRow = 6
        var rowNumber = headerRow + 1
        var rowsXML = ""

        rowsXML += excelRow(number: 1, cells: [excelTextCell(reference: "A1", value: document.title, style: 1)])
        rowsXML += excelRow(number: 2, cells: [excelTextCell(reference: "A2", value: document.periodText, style: 2)])
        rowsXML += excelRow(number: 3, cells: [excelTextCell(reference: "A3", value: table.title, style: 1)])
        rowsXML += excelRow(number: 4, cells: [excelTextCell(reference: "A4", value: table.subtitle, style: 2)])

        let headerCells = table.columns.enumerated().map { index, value in
            excelTextCell(reference: "\(excelColumnName(index + 1))\(headerRow)", value: value, style: 3)
        }
        rowsXML += excelRow(number: headerRow, cells: headerCells)

        for row in table.rows {
            var cells: [String] = []
            for index in 0..<columnCount {
                let reference = "\(excelColumnName(index + 1))\(rowNumber)"
                let cell = index < row.cells.count ? row.cells[index] : .text("")
                switch cell {
                case .text(let value):
                    let style: Int
                    switch row.emphasis {
                    case .normal: style = 0
                    case .section: style = 9
                    case .subtotal: style = 5
                    case .total: style = 7
                    }
                    cells.append(excelTextCell(reference: reference, value: value, style: style))
                case .number(let value):
                    let style: Int
                    switch row.emphasis {
                    case .normal: style = 4
                    case .section: style = 9
                    case .subtotal: style = 6
                    case .total: style = 8
                    }
                    cells.append(excelNumberCell(reference: reference, value: value, style: style))
                }
            }
            rowsXML += excelRow(number: rowNumber, cells: cells)
            rowNumber += 1
        }

        if !document.notes.isEmpty {
            rowNumber += 1
            rowsXML += excelRow(number: rowNumber, cells: [excelTextCell(reference: "A\(rowNumber)", value: "Report Notes", style: 5)])
            rowNumber += 1
            for note in document.notes {
                rowsXML += excelRow(number: rowNumber, cells: [excelTextCell(reference: "A\(rowNumber)", value: "• \(note)", style: 2)])
                rowNumber += 1
            }
        }

        let columnsXML = table.columns.enumerated().map { index, title -> String in
            let lowered = title.lowercased()
            let width: Double
            if lowered.contains("reference") { width = 42 }
            else if lowered.contains("account") || lowered.contains("category") { width = 28 }
            else if lowered.contains("date") || lowered.contains("code") { width = 14 }
            else { width = 17 }
            return "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }.joined()

        let lastDataRow = max(rowNumber - 1, headerRow)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="A1:\(lastColumn)\(lastDataRow)"/>
          <sheetViews><sheetView workbookViewId="0"><pane ySplit="6" topLeftCell="A7" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
          <sheetFormatPr defaultRowHeight="18"/>
          <cols>\(columnsXML)</cols>
          <sheetData>\(rowsXML)</sheetData>
          <autoFilter ref="A\(headerRow):\(lastColumn)\(max(headerRow, headerRow + table.rows.count))"/>
          <mergeCells count="4">
            <mergeCell ref="A1:\(lastColumn)1"/>
            <mergeCell ref="A2:\(lastColumn)2"/>
            <mergeCell ref="A3:\(lastColumn)3"/>
            <mergeCell ref="A4:\(lastColumn)4"/>
          </mergeCells>
          <pageMargins left="0.35" right="0.35" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>
          <pageSetup orientation="landscape" fitToWidth="1" fitToHeight="0"/>
        </worksheet>
        """
    }

    private static func excelRow(number: Int, cells: [String]) -> String {
        "<row r=\"\(number)\">\(cells.joined())</row>"
    }

    private static func excelTextCell(reference: String, value: String, style: Int) -> String {
        "<c r=\"\(reference)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">\(xmlEscape(value))</t></is></c>"
    }

    private static func excelNumberCell(reference: String, value: Decimal, style: Int) -> String {
        "<c r=\"\(reference)\" s=\"\(style)\"><v>\(NSDecimalNumber(decimal: value).stringValue)</v></c>"
    }

    private static func contentTypesXML(sheetCount: Int) -> String {
        let sheets = (1...max(sheetCount, 1)).map {
            "<Override PartName=\"/xl/worksheets/sheet\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
          \(sheets)
        </Types>
        """
    }

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static func workbookXML(sheetNames: [String]) -> String {
        let sheets = sheetNames.enumerated().map { index, name in
            "<sheet name=\"\(xmlEscape(name))\" sheetId=\"\(index + 1)\" r:id=\"rId\(index + 1)\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <workbookPr date1904="0"/>
          <sheets>\(sheets)</sheets>
          <calcPr calcId="191029" fullCalcOnLoad="1"/>
        </workbook>
        """
    }

    private static func workbookRelationshipsXML(sheetCount: Int) -> String {
        let sheets = (1...max(sheetCount, 1)).map {
            "<Relationship Id=\"rId\($0)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0).xml\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          \(sheets)
          <Relationship Id="rId\(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
    }

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <numFmts count="1"><numFmt numFmtId="164" formatCode="#,#0.00;[Red]-#,#0.00"/></numFmts>
      <fonts count="4">
        <font><sz val="10"/><name val="Aptos"/></font>
        <font><b/><sz val="16"/><color rgb="FF205A47"/><name val="Aptos Display"/></font>
        <font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>
        <font><b/><sz val="10"/><color rgb="FF183D31"/><name val="Aptos"/></font>
      </fonts>
      <fills count="4">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF205A47"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFE8F3EE"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="2">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><left style="thin"><color rgb="FFD8D2E6"/></left><right style="thin"><color rgb="FFD8D2E6"/></right><top style="thin"><color rgb="FFD8D2E6"/></top><bottom style="thin"><color rgb="FFD8D2E6"/></bottom><diagonal/></border>
      </borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="10">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"><alignment horizontal="right"/></xf>
        <xf numFmtId="0" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
        <xf numFmtId="164" fontId="3" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyNumberFormat="1"><alignment horizontal="right"/></xf>
        <xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
        <xf numFmtId="164" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyNumberFormat="1"><alignment horizontal="right"/></xf>
        <xf numFmtId="0" fontId="3" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """

    private static func uniqueSheetNames(_ values: [String]) -> [String] {
        var used = Set<String>()
        return values.enumerated().map { index, value in
            let forbidden = CharacterSet(charactersIn: "[]:*?/\\")
            let cleaned = value.components(separatedBy: forbidden).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let base = String((cleaned.isEmpty ? "Report \(index + 1)" : cleaned).prefix(31))
            var candidate = base
            var suffix = 2
            while used.contains(candidate.lowercased()) {
                let tail = " \(suffix)"
                candidate = String(base.prefix(max(1, 31 - tail.count))) + tail
                suffix += 1
            }
            used.insert(candidate.lowercased())
            return candidate
        }
    }

    private static func excelColumnName(_ index: Int) -> String {
        var value = max(index, 1)
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        }
        return result
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func reportURL(document: ProfessionalReportDocument, extension fileExtension: String) -> URL {
        let directory = reportsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = ReportDateFormatters.fileDate.string(from: Date())
        let cleanTitle = document.title
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ")).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")
        return directory.appendingPathComponent("NextLedger-\(cleanTitle)-\(date).\(fileExtension)")
    }

    private static var reportsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NextLedgerReports", isDirectory: true)
    }

    private static func cleanupOldFiles() {
        let manager = FileManager.default
        try? manager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        guard let files = try? manager.contentsOfDirectory(
            at: reportsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for file in files {
            let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let date, date < cutoff { try? manager.removeItem(at: file) }
        }
    }
}

private enum ReportDateFormatters {
    static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum ReportNumberFormatters {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()
}

private enum StoredZipArchive {
    private struct CentralEntry {
        let name: Data
        let crc32: UInt32
        let size: UInt32
        let offset: UInt32
        let dosTime: UInt16
        let dosDate: UInt16
    }

    static func make(files: [(String, Data)]) -> Data {
        var output = Data()
        var entries: [CentralEntry] = []
        let dateTime = dosDateTime(Date())

        for (name, content) in files {
            let nameData = Data(name.utf8)
            let crc = crc32(content)
            let offset = UInt32(output.count)
            output.appendLittleEndian(UInt32(0x04034b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(dateTime.time)
            output.appendLittleEndian(dateTime.date)
            output.appendLittleEndian(crc)
            output.appendLittleEndian(UInt32(content.count))
            output.appendLittleEndian(UInt32(content.count))
            output.appendLittleEndian(UInt16(nameData.count))
            output.appendLittleEndian(UInt16(0))
            output.append(nameData)
            output.append(content)
            entries.append(CentralEntry(
                name: nameData,
                crc32: crc,
                size: UInt32(content.count),
                offset: offset,
                dosTime: dateTime.time,
                dosDate: dateTime.date
            ))
        }

        let centralOffset = UInt32(output.count)
        for entry in entries {
            output.appendLittleEndian(UInt32(0x02014b50))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(20))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(entry.dosTime)
            output.appendLittleEndian(entry.dosDate)
            output.appendLittleEndian(entry.crc32)
            output.appendLittleEndian(entry.size)
            output.appendLittleEndian(entry.size)
            output.appendLittleEndian(UInt16(entry.name.count))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt16(0))
            output.appendLittleEndian(UInt32(0))
            output.appendLittleEndian(entry.offset)
            output.append(entry.name)
        }
        let centralSize = UInt32(output.count) - centralOffset
        output.appendLittleEndian(UInt32(0x06054b50))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(0))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(centralSize)
        output.appendLittleEndian(centralOffset)
        output.appendLittleEndian(UInt16(0))
        return output
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var current = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 {
                current = (current & 1) == 1
                    ? (current >> 1) ^ 0xEDB88320
                    : current >> 1
            }
            crc = (crc >> 8) ^ current
        }
        return crc ^ 0xFFFFFFFF
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let year = min(max(components.year ?? 1980, 1980), 2107)
        let month = min(max(components.month ?? 1, 1), 12)
        let day = min(max(components.day ?? 1, 1), 31)
        let hour = min(max(components.hour ?? 0, 0), 23)
        let minute = min(max(components.minute ?? 0, 0), 59)
        let second = min(max(components.second ?? 0, 0), 59)
        let dosDate = UInt16((year - 1980) << 9 | month << 5 | day)
        let dosTime = UInt16(hour << 11 | minute << 5 | second / 2)
        return (dosTime, dosDate)
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { buffer in
            append(contentsOf: buffer.bindMemory(to: UInt8.self))
        }
    }
}
