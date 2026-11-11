import SwiftUI

struct SplitTransactionView: View {
    private enum SplitMode: String, CaseIterable, Identifiable {
        case expense = "Split Expense"
        case paymentSource = "Split Payment Source"
        var id: String { rawValue }
    }
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let transaction: LedgerTransaction
    @State private var firstAccountID: UUID?
    @State private var secondAccountID: UUID?
    @State private var firstAmount = ""
    @State private var secondAmount = ""
    @State private var mode: SplitMode = .expense
    @State private var firstCategory = ""
    @State private var secondCategory = ""
    @FocusState private var focusedAmount: SplitAmountField?
    private enum SplitAmountField { case first, second }

    var body: some View {
        NavigationStack {
            Form {
                Section("Original Transaction") {
                    LabeledContent("Total", value: DisplayFormat.currency(transaction.amount, code: currencyCode))
                    LabeledContent("Date & Time", value: transaction.date.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Category", value: transaction.category)
                }
                if transaction.type == .expense {
                    Picker("Split", selection: $mode) {
                        ForEach(SplitMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if mode == .expense && transaction.type == .expense {
                    expenseSection(title: "First Expense", category: $firstCategory, amount: $firstAmount)
                    expenseSection(title: "Second Expense", category: $secondCategory, amount: $secondAmount)
                } else {
                    splitSection(title: "First Source", accountID: $firstAccountID, amount: $firstAmount)
                    splitSection(title: "Second Source", accountID: $secondAccountID, amount: $secondAmount)
                }
                Section {
                    LabeledContent("Split Total", value: DisplayFormat.currency(splitTotal, code: currencyCode))
                    if splitTotal != transaction.amount {
                        Text("The two amounts must equal the original transaction total.")
                            .font(.caption)
                            .foregroundStyle(AppTheme.red)
                    }
                }
            }
            .navigationTitle("Split Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { save() }
                        .disabled(!isValid)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                        Button(symbol) { appendOperator(symbol) }
                    }
                    Button("=", action: calculateFocusedAmount)
                }
            }
            .onAppear {
                firstAccountID = transaction.accountID ?? store.defaultAccountID
                secondAccountID = store.activeAccounts.first { $0.id != firstAccountID }?.id
                firstAmount = NSDecimalNumber(decimal: transaction.amount / 2).stringValue
                secondAmount = NSDecimalNumber(decimal: transaction.amount - (transaction.amount / 2)).stringValue
                firstCategory = transaction.category
                secondCategory = transaction.category
            }
            .onChange(of: firstAmount) { _ in
                let remaining = max(transaction.amount - firstValue, 0)
                secondAmount = NSDecimalNumber(decimal: remaining).stringValue
            }
        }
    }

    private func expenseSection(title: String, category: Binding<String>, amount: Binding<String>) -> some View {
        Section(title) {
            Picker("Category", selection: category) {
                ForEach(store.categories(for: .expense).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, id: \.self) {
                    Text($0).tag($0)
                }
            }
            TextField("Amount", text: amount)
                .keyboardType(.decimalPad)
                .focused($focusedAmount, equals: title.hasPrefix("First") ? .first : .second)
            inlineCalculator(for: title.hasPrefix("First") ? .first : .second)
        }
    }

    private func splitSection(
        title: String,
        accountID: Binding<UUID?>,
        amount: Binding<String>
    ) -> some View {
        Section(title) {
            Picker("Account", selection: accountID) {
                ForEach(store.activeAccounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            TextField("Amount", text: amount)
                .keyboardType(.decimalPad)
                .focused($focusedAmount, equals: title.hasPrefix("First") ? .first : .second)
            inlineCalculator(for: title.hasPrefix("First") ? .first : .second)
        }
    }

    private func inlineCalculator(for field: SplitAmountField) -> some View {
        HStack(spacing: 8) {
            ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                Button(symbol) {
                    focusedAmount = field
                    appendOperator(symbol)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            Button("=") {
                focusedAmount = field
                calculateFocusedAmount()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .font(.subheadline.weight(.semibold))
    }

    private var firstValue: Decimal { decimal(firstAmount) ?? 0 }
    private var secondValue: Decimal { decimal(secondAmount) ?? 0 }
    private var splitTotal: Decimal { firstValue + secondValue }
    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }
    private var isValid: Bool {
        guard firstValue > 0, secondValue > 0, splitTotal == transaction.amount else { return false }
        if mode == .expense && transaction.type == .expense {
            return !firstCategory.isEmpty && !secondCategory.isEmpty
        }
        return firstAccountID != nil && secondAccountID != nil && firstAccountID != secondAccountID
    }
    private func decimal(_ text: String) -> Decimal? {
        AmountExpression.evaluate(text)
    }
    private func appendOperator(_ symbol: String) {
        if focusedAmount == .second {
            secondAmount = AmountExpression.appending(symbol, to: secondAmount)
        } else {
            firstAmount = AmountExpression.appending(symbol, to: firstAmount)
        }
    }
    private func calculateFocusedAmount() {
        if focusedAmount == .second {
            if let value = AmountExpression.evaluate(secondAmount) {
                secondAmount = NSDecimalNumber(decimal: value).stringValue
            }
        } else if let value = AmountExpression.evaluate(firstAmount) {
            firstAmount = NSDecimalNumber(decimal: value).stringValue
        }
    }
    private func save() {
        if mode == .expense && transaction.type == .expense {
            store.splitExpense(
                transaction, firstCategory: firstCategory, firstAmount: firstValue,
                secondCategory: secondCategory, secondAmount: secondValue
            )
            dismiss()
            return
        }
        guard let firstAccountID, let secondAccountID else { return }
        store.split(
            transaction, firstAccountID: firstAccountID, firstAmount: firstValue,
            secondAccountID: secondAccountID, secondAmount: secondValue
        )
        dismiss()
    }
}
