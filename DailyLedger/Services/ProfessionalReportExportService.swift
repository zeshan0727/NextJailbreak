import CoreGraphics
import Foundation
import UIKit

enum ProfessionalReportType: String, CaseIterable, Identifiable {
    case financialSummary = "Financial Summary"
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
            return "Income, expenses and net result by currency"
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
        store: LedgerStore
    ) -> ProfessionalReportDocument {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let endDay = calendar.startOfDay(for: max(startDate, endDate))
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        let interval = DateInterval(start: start, end: endExclusive)

        switch type {
        case .financialSummary:
            return financialSummary(interval: interval, store: store)
        case .incomeStatement:
            return incomeStatement(interval: interval, store: store)
        case .balanceSheet:
            return balanceSheet(interval: interval, store: store)
        case .payablesAging:
            return agingReport(isPayable: true, detailed: true, asOf: endDay, store: store)
        case .payablesSummary:
            return agingReport(isPayable: true, detailed: false, asOf: endDay, store: store)
        case .receivablesAging:
            return agingReport(isPayable: false, detailed: true, asOf: endDay, store: store)
        case .receivablesSummary:
            return agingReport(isPayable: false, detailed: false, asOf: endDay, store: store)
        }
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
                    .text(section.rawValue), .text(""), .text(""), .text(""), .text("")
                ], emphasis: .section))

                for line in sectionLines {
                    let multiplier: Decimal = section.isLiability ? -1 : 1
                    rows.append(ProfessionalReportRow([
                        .text(line.account.chartCode.flatMap { $0.isEmpty ? nil : $0 } ?? "—"),
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
            let normalized = signedMovement(transaction, accountID: account.id) * polarity
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

    private static func signedMovement(_ transaction: LedgerTransaction, accountID: UUID) -> Decimal {
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
            movement += transaction.destinationAmount ?? transaction.amount
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
        "Each currency is presented separately in its native amount.",
        "The export does not force an exchange-rate conversion between QAR, PKR, USD or other currencies."
    ]
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

    private static func exportPDF(_ document: ProfessionalReportDocument) throws -> URL {
        let url = reportURL(document: document, extension: "pdf")
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Next Ledger",
            kCGPDFContextAuthor as String: "Next Solution – Zeeshan Barvi",
            kCGPDFContextTitle as String: document.title
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let data = renderer.pdfData { context in
            let margin: CGFloat = 34
            let contentWidth = pageRect.width - margin * 2
            var pageNumber = 0
            var cursorY: CGFloat = 0

            func drawText(
                _ text: String,
                rect: CGRect,
                font: UIFont,
                color: UIColor,
                alignment: NSTextAlignment = .left
            ) {
                let style = NSMutableParagraphStyle()
                style.alignment = alignment
                style.lineBreakMode = .byTruncatingTail
                (text as NSString).draw(
                    with: rect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [
                        .font: font,
                        .foregroundColor: color,
                        .paragraphStyle: style
                    ],
                    context: nil
                )
            }

            func drawFooter() {
                let y = pageRect.height - 28
                UIColor(white: 0.82, alpha: 1).setFill()
                UIBezierPath(rect: CGRect(x: margin, y: y - 6, width: contentWidth, height: 0.5)).fill()
                drawText(
                    "Next Ledger • Generated \(ReportDateFormatters.timestamp.string(from: document.generatedAt))",
                    rect: CGRect(x: margin, y: y, width: contentWidth - 60, height: 14),
                    font: .systemFont(ofSize: 7.5),
                    color: UIColor(white: 0.45, alpha: 1)
                )
                drawText(
                    "Page \(pageNumber)",
                    rect: CGRect(x: pageRect.width - margin - 54, y: y, width: 54, height: 14),
                    font: .systemFont(ofSize: 7.5, weight: .semibold),
                    color: UIColor(white: 0.45, alpha: 1),
                    alignment: .right
                )
            }

            func beginPage() {
                context.beginPage()
                pageNumber += 1
                let headerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: 78)
                UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1).setFill()
                UIBezierPath(rect: headerRect).fill()
                drawText(
                    "NEXT LEDGER",
                    rect: CGRect(x: margin, y: 15, width: 180, height: 18),
                    font: .systemFont(ofSize: 10, weight: .heavy),
                    color: .white
                )
                drawText(
                    document.title,
                    rect: CGRect(x: margin, y: 31, width: contentWidth, height: 26),
                    font: .systemFont(ofSize: 20, weight: .bold),
                    color: .white
                )
                drawText(
                    document.periodText,
                    rect: CGRect(x: margin, y: 58, width: contentWidth, height: 14),
                    font: .systemFont(ofSize: 8.5, weight: .medium),
                    color: UIColor.white.withAlphaComponent(0.82)
                )
                cursorY = 94
            }

            func ensureSpace(_ height: CGFloat) {
                if cursorY + height > pageRect.height - 42 {
                    drawFooter()
                    beginPage()
                }
            }

            func columnWidths(for count: Int) -> [CGFloat] {
                let ratios: [CGFloat]
                switch count {
                case 2: ratios = [0.66, 0.34]
                case 3: ratios = [0.49, 0.28, 0.23]
                case 5: ratios = [0.10, 0.34, 0.18, 0.18, 0.20]
                case 6: ratios = [0.34, 0.132, 0.132, 0.132, 0.132, 0.142]
                case 8: ratios = [0.10, 0.16, 0.24, 0.10, 0.10, 0.10, 0.10, 0.10]
                default: ratios = Array(repeating: 1 / CGFloat(max(count, 1)), count: max(count, 1))
                }
                return ratios.map { $0 * contentWidth }
            }

            func cellString(_ cell: ProfessionalReportCell) -> String {
                switch cell {
                case .text(let value): return value
                case .number(let value): return ReportNumberFormatters.decimal.string(from: NSDecimalNumber(decimal: value)) ?? "0.00"
                }
            }

            func drawTableHeader(_ table: ProfessionalReportTable, widths: [CGFloat]) {
                let height: CGFloat = 27
                UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: margin, y: cursorY, width: contentWidth, height: height), cornerRadius: 5).fill()
                var x = margin
                for (index, column) in table.columns.enumerated() {
                    let width = widths[index]
                    drawText(
                        column,
                        rect: CGRect(x: x + 5, y: cursorY + 7, width: width - 10, height: 14),
                        font: .systemFont(ofSize: 7.6, weight: .bold),
                        color: .white,
                        alignment: index >= max(table.columns.count - 3, 1) ? .right : .left
                    )
                    x += width
                }
                cursorY += height
            }

            beginPage()
            drawText(
                document.subtitle,
                rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 28),
                font: .systemFont(ofSize: 11, weight: .medium),
                color: UIColor(white: 0.28, alpha: 1)
            )
            cursorY += 31

            for table in document.tables {
                ensureSpace(72)
                drawText(
                    table.title,
                    rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 22),
                    font: .systemFont(ofSize: 13, weight: .bold),
                    color: UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1)
                )
                cursorY += 20
                if !table.subtitle.isEmpty {
                    drawText(
                        table.subtitle,
                        rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 18),
                        font: .systemFont(ofSize: 8.5),
                        color: UIColor(white: 0.42, alpha: 1)
                    )
                    cursorY += 19
                }

                let widths = columnWidths(for: table.columns.count)
                drawTableHeader(table, widths: widths)

                for (rowIndex, row) in table.rows.enumerated() {
                    let rowHeight: CGFloat = table.columns.count >= 8 ? 31 : 25
                    if cursorY + rowHeight > pageRect.height - 42 {
                        drawFooter()
                        beginPage()
                        drawText(
                            "\(table.title) — continued",
                            rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 19),
                            font: .systemFont(ofSize: 10.5, weight: .bold),
                            color: UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1)
                        )
                        cursorY += 22
                        drawTableHeader(table, widths: widths)
                    }

                    let fillColor: UIColor
                    switch row.emphasis {
                    case .section:
                        fillColor = UIColor(red: 0.94, green: 0.92, blue: 0.98, alpha: 1)
                    case .subtotal:
                        fillColor = UIColor(red: 0.93, green: 0.95, blue: 0.98, alpha: 1)
                    case .total:
                        fillColor = UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1)
                    case .normal:
                        fillColor = rowIndex.isMultiple(of: 2) ? .white : UIColor(white: 0.975, alpha: 1)
                    }
                    fillColor.setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: rowHeight)).fill()

                    var x = margin
                    for index in table.columns.indices {
                        let width = widths[index]
                        let cell = index < row.cells.count ? row.cells[index] : .text("")
                        let isNumber: Bool
                        if case .number = cell { isNumber = true } else { isNumber = false }
                        let textColor: UIColor = row.emphasis == .total ? .white : UIColor(white: 0.18, alpha: 1)
                        let font: UIFont = row.emphasis == .normal
                            ? .systemFont(ofSize: table.columns.count >= 8 ? 6.7 : 7.6)
                            : .systemFont(ofSize: table.columns.count >= 8 ? 6.7 : 7.6, weight: .bold)
                        drawText(
                            cellString(cell),
                            rect: CGRect(x: x + 5, y: cursorY + 7, width: width - 10, height: rowHeight - 8),
                            font: font,
                            color: textColor,
                            alignment: isNumber ? .right : .left
                        )
                        UIColor(white: 0.88, alpha: 1).setFill()
                        UIBezierPath(rect: CGRect(x: x + width - 0.4, y: cursorY, width: 0.4, height: rowHeight)).fill()
                        x += width
                    }
                    cursorY += rowHeight
                }
                cursorY += 16
            }

            if !document.notes.isEmpty {
                ensureSpace(CGFloat(document.notes.count * 19 + 36))
                drawText(
                    "Report Notes",
                    rect: CGRect(x: margin, y: cursorY, width: contentWidth, height: 20),
                    font: .systemFont(ofSize: 11, weight: .bold),
                    color: UIColor(red: 0.22, green: 0.12, blue: 0.48, alpha: 1)
                )
                cursorY += 22
                for note in document.notes {
                    ensureSpace(19)
                    drawText(
                        "• \(note)",
                        rect: CGRect(x: margin + 4, y: cursorY, width: contentWidth - 8, height: 18),
                        font: .systemFont(ofSize: 8),
                        color: UIColor(white: 0.38, alpha: 1)
                    )
                    cursorY += 19
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
        let tables = document.tables.isEmpty
            ? [ProfessionalReportTable(title: document.title, subtitle: document.subtitle, columns: ["Status"], rows: [ProfessionalReportRow([.text("No data")])])]
            : document.tables
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
        <font><b/><sz val="16"/><color rgb="FF3A1E7A"/><name val="Aptos Display"/></font>
        <font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font>
        <font><b/><sz val="10"/><color rgb="FF21163E"/><name val="Aptos"/></font>
      </fonts>
      <fills count="4">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FF3A1E7A"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFEFEAF8"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="2">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><left style="thin"><color rgb="FFD8D2E6"/></left><right style="thin"><color rgb="FFD8D2E6"/></right><top style="thin"><color rgb="FFD8D2E6"/></top><bottom style="thin"><color rgb="FFD8D2E6"/></bottom><diagonal/></border>
      </borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="10">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center"/></xf>
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
