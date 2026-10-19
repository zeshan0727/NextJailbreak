import SwiftUI

struct RefundTransactionView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction

    @State private var amountText = ""
    @State private var selectedAccountID: UUID?
    @State private var refundDate = Date()
    @State private var note = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Original Transaction") {
                    LabeledContent("Type", value: transaction.type.title)
                    LabeledContent(
                        "Original Amount",
                        value: DisplayFormat.currency(transaction.amount, code: currencyCode)
                    )
                    if refundedAmount > 0 {
                        LabeledContent(
                            "Already Refunded",
                            value: DisplayFormat.currency(refundedAmount, code: currencyCode)
                        )
                    }
                    LabeledContent(
                        "Available to Refund",
                        value: DisplayFormat.currency(remainingAmount, code: currencyCode)
                    )
                    LabeledContent(
                        "Original Account",
                        value: store.account(withID: transaction.accountID)?.name ?? "Unknown"
                    )
                }

                Section {
                    Picker("Refund To Account", selection: $selectedAccountID) {
                        ForEach(availableRefundAccounts) { account in
                            HStack {
                                Text(account.name)
                                Spacer()
                                Text(account.currencyCode)
                            }
                            .tag(Optional(account.id))
                        }
                    }
                    TextField("Refund amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    DatePicker("Refund Date", selection: $refundDate, displayedComponents: .date)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Refund Details")
                } footer: {
                    Text("Next Ledger records a new \(reverseType.title.lowercased()) transaction for this amount on the selected refund date. The original transaction date is not changed.")
                }
            }
            .navigationTitle("Record Refund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRefund() }
                        .disabled(!isValidAmount)
                }
            }
            .onAppear {
                if selectedAccountID == nil {
                    selectedAccountID = availableRefundAccounts.first(where: {
                        $0.id == transaction.accountID
                    })?.id ?? availableRefundAccounts.first?.id
                }
                if amountText.isEmpty {
                    amountText = NSDecimalNumber(decimal: remainingAmount).stringValue
                }
            }
            .alert(
                "Refund Not Recorded",
                isPresented: Binding(
                    get: { localError != nil },
                    set: { if !$0 { localError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { localError = nil }
            } message: {
                Text(localError ?? "Please check the refund details.")
            }
        }
    }

    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }

    private var availableRefundAccounts: [LedgerAccount] {
        store.accounts
            .filter {
                $0.currencyCode == currencyCode &&
                (!$0.isArchived || $0.id == transaction.accountID)
            }
            .sorted {
                if $0.group != $1.group { return $0.group.title < $1.group.title }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var refundedAmount: Decimal {
        store.refundedAmount(for: transaction)
    }

    private var remainingAmount: Decimal {
        store.refundableAmount(for: transaction)
    }

    private var reverseType: TransactionType {
        transaction.type == .expense ? .income : .expense
    }

    private var parsedAmount: Decimal? {
        let cleaned = amountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    private var isValidAmount: Bool {
        guard let amount = parsedAmount,
              let selectedAccountID,
              availableRefundAccounts.contains(where: { $0.id == selectedAccountID }) else { return false }
        return amount > 0 && amount <= remainingAmount
    }

    private func saveRefund() {
        guard let amount = parsedAmount else {
            localError = "Enter a valid refund amount."
            return
        }
        guard let selectedAccountID else {
            localError = "Choose the account receiving the refund."
            return
        }
        if store.addRefund(
            for: transaction,
            amount: amount,
            date: refundDate,
            accountID: selectedAccountID,
            details: note
        ) {
            dismiss()
        } else {
            localError = store.errorMessage ?? "The refund could not be recorded."
        }
    }
}
