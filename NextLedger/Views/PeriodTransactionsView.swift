import SwiftUI

enum PeriodTransactionKind {
    case income
    case refunds
    case expenses
    case loanIncreased
    case loans

    var title: String {
        switch self {
        case .income: return "Income"
        case .refunds: return "Refunds"
        case .expenses: return "Expenses"
        case .loanIncreased: return "Loans Increased"
        case .loans: return "Loans Paid"
        }
    }
}

struct PeriodTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTransaction: LedgerTransaction?
    @State private var searchText = ""
    let kind: PeriodTransactionKind
    let interval: DateInterval
    /// Optional currency scope supplied by a currency-specific Financial Summary card.
    /// Nil preserves the existing all-currency behavior for other report entry points.
    let currencyCode: String?

    init(
        kind: PeriodTransactionKind,
        interval: DateInterval,
        currencyCode: String? = nil
    ) {
        self.kind = kind
        self.interval = interval
        self.currencyCode = currencyCode
    }

    var body: some View {
        List {
            Section {
                ForEach(transactions) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(
                            transaction: transaction,
                            accountID: (kind == .income || kind == .refunds)
                                ? store.reportIncomeAccountID(transaction)
                                : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .transactionSwipeActions(transaction)
                    .contextMenu {
                        Button(role: .destructive) {
                            store.delete(transaction)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                HStack {
                    Text("Total · \(transactions.count) transactions")
                    Spacer()
                    Text(DisplayFormat.currency(total, code: currencyCode ?? store.currencyCode)).bold()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(currencyCode.map { "\(kind.title) · \($0)" } ?? kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search transactions")
        .overlay {
            if transactions.isEmpty {
                EmptyLedgerView(
                    title: "No \(kind.title.lowercased())",
                    message: "No matching transactions are available for this period."
                )
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionSnapshotView(transaction: transaction)
                .environmentObject(store)
        }
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter { transaction in
            guard interval.contains(transaction.date) else { return false }
            if let currencyCode,
               (kind == .loanIncreased || kind == .loans),
               store.account(withID: transaction.accountID)?.currencyCode != currencyCode {
                return false
            }
            let kindMatches: Bool
            switch kind {
            case .income:
                kindMatches = store.isFinancialSummaryDirectIncome(transaction) &&
                    store.convertedReportIncomeAmount(transaction) != nil
            case .refunds:
                kindMatches = store.isFinancialSummaryRefund(transaction) &&
                    store.convertedReportIncomeAmount(transaction) != nil
            case .expenses:
                kindMatches = store.isFinancialSummaryDirectExpense(transaction) &&
                    store.convertedReportExpenseAmount(transaction) != nil
            case .loanIncreased:
                kindMatches = store.convertedFinancialSummaryLoanIncreaseAmount(transaction) != nil
            case .loans:
                kindMatches = store.convertedFinancialSummaryLoanPaidAmount(transaction) != nil
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return transaction.category.localizedCaseInsensitiveContains(searchText) ||
                (transaction.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                transaction.details.localizedCaseInsensitiveContains(searchText)
        }
        .sorted { $0.date > $1.date }
    }

    private var total: Decimal {
        transactions.reduce(Decimal.zero) {
            switch kind {
            case .income, .refunds:
                return $0 + (store.convertedReportIncomeAmount($1) ?? 0)
            case .expenses:
                return $0 + (store.convertedReportExpenseAmount($1) ?? 0)
            case .loanIncreased:
                if currencyCode != nil {
                    return $0 + store.financialSummaryLoanIncreaseAmount($1)
                }
                return $0 + (store.convertedFinancialSummaryLoanIncreaseAmount($1) ?? 0)
            case .loans:
                if currencyCode != nil {
                    return $0 + store.financialSummaryLoanPaidAmount($1)
                }
                return $0 + (store.convertedFinancialSummaryLoanPaidAmount($1) ?? 0)
            }
        }
    }
}
