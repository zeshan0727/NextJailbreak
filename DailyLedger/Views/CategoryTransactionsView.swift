import SwiftUI

struct CategoryTransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedTransaction: LedgerTransaction?
    @State private var searchText = ""
    let category: String
    let interval: DateInterval

    var body: some View {
        List {
            Section {
                ForEach(transactions) { transaction in
                    Button {
                        selectedTransaction = transaction
                    } label: {
                        TransactionRow(transaction: transaction)
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
                    Text(DisplayFormat.currency(total, code: store.currencyCode)).bold()
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search transactions")
        .overlay {
            if transactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions",
                    message: "No \(category) transactions are available in this report period."
                )
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionSnapshotView(transaction: transaction)
                .environmentObject(store)
        }
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            interval.contains($0.date) &&
            $0.type == .expense &&
            $0.category.caseInsensitiveCompare(category) == .orderedSame &&
            store.convertedReportExpenseAmount($0) != nil &&
            (searchText.isEmpty ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText))
        }
        .sorted { $0.date > $1.date }
    }

    private var total: Decimal {
        transactions.reduce(Decimal.zero) {
            $0 + (store.convertedReportExpenseAmount($1) ?? 0)
        }
    }
}

struct TransactionSnapshotView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var splitting = false
    @State private var refunding = false
    let transaction: LedgerTransaction

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    LabeledContent("Type", value: transaction.type.title)
                    LabeledContent("Amount", value: DisplayFormat.currency(
                        transaction.amount,
                        code: store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
                    ))
                    LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Category", value: transaction.category)
                    if let vendor = transaction.vendor, !vendor.isEmpty {
                        LabeledContent("Vendor", value: vendor)
                    }
                    LabeledContent("Account", value: store.account(withID: transaction.accountID)?.name ?? "Unknown")
                    if transaction.type == .transfer {
                        LabeledContent(
                            "Destination",
                            value: store.account(withID: transaction.destinationAccountID)?.name ?? "Unknown"
                        )
                    }
                }
                if !transaction.details.isEmpty {
                    Section("Description") {
                        Text(transaction.details)
                            .textSelection(.enabled)
                    }
                }

                if transaction.refundOfTransactionID != nil {
                    Section("Refund") {
                        Label("Refund transaction", systemImage: "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(AppTheme.green)
                        Text("This entry reverses an earlier transaction on this refund date.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if transaction.type != .transfer {
                    Section {
                        if refundedAmount > 0 {
                            LabeledContent(
                                "Refunded",
                                value: DisplayFormat.currency(refundedAmount, code: currencyCode)
                            )
                            LabeledContent(
                                "Remaining",
                                value: DisplayFormat.currency(refundableAmount, code: currencyCode)
                            )
                        }
                        Button {
                            refunding = true
                        } label: {
                            Label(
                                refundableAmount > 0 ? "Record Refund" : "Fully Refunded",
                                systemImage: "arrow.uturn.backward.circle.fill"
                            )
                        }
                        .disabled(refundableAmount <= 0)
                    } header: {
                        Text("Refund")
                    } footer: {
                        Text("A refund creates a new opposite transaction using the refund amount and refund date. The original transaction and its original date remain unchanged.")
                    }
                }
                Section {
                    Button("Delete Transaction", role: .destructive) {
                        store.delete(transaction)
                        dismiss()
                    }
                } footer: {
                    Text("Deleting removes this entry from all reports and account balances. Linked refunds are also removed when deleting the original transaction.")
                }
            }
            .navigationTitle("Transaction Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack {
                        if transaction.type != .transfer &&
                            transaction.refundOfTransactionID == nil && refundedAmount == 0 {
                            Button {
                                splitting = true
                            } label: {
                                Label("Split", systemImage: "rectangle.split.2x1")
                            }
                        }
                        Button("Edit") { editing = true }
                    }
                }
            }
            .sheet(isPresented: $splitting) {
                SplitTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $refunding) {
                RefundTransactionView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $editing) {
                if transaction.type == .transfer {
                    TransferView(transaction: transaction)
                        .environmentObject(store)
                } else {
                    AddTransactionView(transaction: transaction)
                        .environmentObject(store)
                }
            }
        }
    }

    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }

    private var refundedAmount: Decimal {
        store.refundedAmount(for: transaction)
    }

    private var refundableAmount: Decimal {
        store.refundableAmount(for: transaction)
    }
}
