import SwiftUI

struct ChartLinkedTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    let title: String
    let accountID: UUID?
    let category: String?
    let type: TransactionType?

    @State private var selectedTransaction: LedgerTransaction?
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                ForEach(transactions) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(transaction: transaction, accountID: accountID)
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
                Text("\(transactions.count) related transaction\(transactions.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search related transactions")
        .overlay {
            if transactions.isEmpty {
                EmptyLedgerView(
                    title: "No related transactions",
                    message: "No transactions are linked to \(title)."
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
            guard matchesAccount(transaction), matchesCategory(transaction) else { return false }
            guard !searchText.isEmpty else { return true }
            return transaction.category.localizedCaseInsensitiveContains(searchText) ||
                (transaction.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                transaction.details.localizedCaseInsensitiveContains(searchText) ||
                transaction.type.title.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: transaction.amount).stringValue.contains(searchText)
        }
        .sorted { $0.date > $1.date }
    }

    private func matchesAccount(_ transaction: LedgerTransaction) -> Bool {
        guard let accountID else { return true }
        let relatedIDs = store.relatedAccountIDs(for: accountID)
        return transaction.accountID.map(relatedIDs.contains) == true ||
            transaction.destinationAccountID.map(relatedIDs.contains) == true ||
            store.reportIncomeAccountID(transaction).map(relatedIDs.contains) == true
    }

    private func matchesCategory(_ transaction: LedgerTransaction) -> Bool {
        guard let category, let type else { return true }
        return transaction.type == type &&
            transaction.category.caseInsensitiveCompare(category) == .orderedSame
    }
}
