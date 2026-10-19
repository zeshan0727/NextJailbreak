import SwiftUI

private struct TransactionSwipeActionsModifier: ViewModifier {
    @EnvironmentObject private var store: LedgerStore
    let transaction: LedgerTransaction

    @State private var editingTransaction: LedgerTransaction?
    @State private var refundingTransaction: LedgerTransaction?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    store.delete(transaction)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                if canRefund {
                    Button {
                        refundingTransaction = transaction
                    } label: {
                        Label("Refund", systemImage: "arrow.uturn.backward.circle")
                    }
                    .tint(AppTheme.green)
                }

                Button {
                    editingTransaction = transaction
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(AppTheme.blue)
            }
            .sheet(item: $editingTransaction) { item in
                if item.type == .transfer {
                    TransferView(transaction: item)
                        .environmentObject(store)
                } else {
                    AddTransactionView(transaction: item)
                        .environmentObject(store)
                }
            }
            .sheet(item: $refundingTransaction) { item in
                RefundTransactionView(transaction: item)
                    .environmentObject(store)
            }
    }

    private var canRefund: Bool {
        transaction.type != .transfer &&
            transaction.refundOfTransactionID == nil &&
            store.refundableAmount(for: transaction) > 0
    }
}

extension View {
    func transactionSwipeActions(_ transaction: LedgerTransaction) -> some View {
        modifier(TransactionSwipeActionsModifier(transaction: transaction))
    }
}
