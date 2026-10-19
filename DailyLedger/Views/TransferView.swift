import Foundation
import SwiftUI

private enum TransferAccountRole: String, Identifiable {
    case source
    case destination

    var id: String { rawValue }
    var title: String { self == .source ? "Source" : "Destination" }
}

struct TransferView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var sourceAccountID: UUID?
    @State private var destinationAccountID: UUID?
    @State private var sourceCurrencySelection = ""
    @State private var destinationCurrencySelection = ""
    @State private var amountText = ""
    @State private var exchangeRateText = ""
    @State private var useCustomRate = false
    @State private var date = Date()
    @State private var details = ""
    @State private var erpDimensions: [String: String] = [:]
    @State private var addingAccountFor: TransferAccountRole?
    @State private var convertingTo: TransactionType?
    @FocusState private var focusedAmount: AmountField?
    private let editingTransaction: LedgerTransaction?
    private let onSaved: (() -> Void)?

    private enum AmountField {
        case source
        case rate
    }

    init(sourceAccountID: UUID? = nil, onSaved: (() -> Void)? = nil) {
        editingTransaction = nil
        self.onSaved = onSaved
        _sourceAccountID = State(initialValue: sourceAccountID)
    }

    init(transaction: LedgerTransaction, onSaved: (() -> Void)? = nil) {
        editingTransaction = transaction
        self.onSaved = onSaved
        _sourceAccountID = State(initialValue: transaction.accountID)
        _destinationAccountID = State(initialValue: transaction.destinationAccountID)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _date = State(initialValue: transaction.date)
        _details = State(initialValue: transaction.details)
        _erpDimensions = State(initialValue: ERPAccountingEngine.dimensionDictionary(transaction))
    }

    var body: some View {
        NavigationStack {
            Form {
                if editingTransaction != nil {
                    Section("Transaction Nature") {
                        LabeledContent("Current", value: "Transfer")
                        HStack(spacing: 12) {
                            Button("Income") { convertingTo = .income }
                            Button("Expense") { convertingTo = .expense }
                        }
                        Text("Choose Income or Expense to convert this existing transfer. Account balances are recalculated when the converted transaction is saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("From") {
                    currencyPicker("From Currency", selection: $sourceCurrencySelection)
                    accountPicker(
                        "Source Account",
                        selection: $sourceAccountID,
                        currency: sourceCurrencySelection
                    )
                    accountAvailabilityMessage(for: .source)
                    addAccountButton(for: .source)
                    amountField("Amount Sent", text: $amountText, currency: sourceCurrency)
                }

                Section("To") {
                    currencyPicker("To Currency", selection: $destinationCurrencySelection)
                    accountPicker(
                        "Destination Account",
                        selection: $destinationAccountID,
                        currency: destinationCurrencySelection
                    )
                    accountAvailabilityMessage(for: .destination)
                    addAccountButton(for: .destination)
                    if !isCrossCurrency, let receivedAmount {
                        LabeledContent(
                            "Amount Received",
                            value: DisplayFormat.currency(receivedAmount, code: destinationCurrency)
                        )
                    }
                }

                if isCrossCurrency {
                    Section {
                        if let fixedRate {
                            Toggle("Use Custom Rate", isOn: $useCustomRate)
                            if !useCustomRate {
                                LabeledContent(
                                    "Fixed Rate",
                                    value: "1 \(sourceCurrency) = \(rateString(fixedRate)) \(destinationCurrency)"
                                )
                            }
                        } else {
                            Label("Custom rate required", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }

                        if useCustomRate || fixedRate == nil {
                            rateField
                        }

                        LabeledContent("Amount Sent") {
                            Text(sourceAmount.map {
                                DisplayFormat.currency($0, code: sourceCurrency)
                            } ?? "—")
                        }
                        LabeledContent("Amount Received") {
                            Text(receivedAmount.map {
                                DisplayFormat.currency($0, code: destinationCurrency)
                            } ?? "—")
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Currency Conversion")
                    } footer: {
                        Text(conversionFooter)
                    }
                }

                ERPTransactionDimensionsEditor(values: $erpDimensions, type: .transfer)

                Section("Details") {
                    TextField("Description (optional)", text: $details)
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    if let saveValidationMessage {
                        Label(saveValidationMessage, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let editingTransaction {
                    Section {
                        Button("Delete Transfer", role: .destructive) {
                            store.delete(editingTransaction)
                            dismiss()
                        }
                    } footer: {
                        Text("Deleting reverses this transfer’s effect on both account balances.")
                    }
                }
            }
            .navigationTitle(editingTransaction == nil ? "New Transfer" : "Edit Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingTransaction == nil ? "Transfer" : "Update", action: save)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                        Button(symbol) { appendOperator(symbol) }
                    }
                    Button("=", action: calculateFocusedAmount)
                }
            }
            .onAppear {
                chooseDefaults()
                configureConversion(preserveEditingRate: true)
            }
            .onChange(of: sourceAccountID) { value in
                if let account = store.account(withID: value) {
                    sourceCurrencySelection = account.currencyCode.uppercased()
                }
                if destinationAccountID == value {
                    destinationAccountID = filteredAccounts(currency: destinationCurrencySelection)
                        .first(where: { $0.id != value })?.id
                }
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: destinationAccountID) { value in
                if let account = store.account(withID: value) {
                    destinationCurrencySelection = account.currencyCode.uppercased()
                }
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: sourceCurrencySelection) { value in
                selectSourceAccount(for: value)
                configureConversion(preserveEditingRate: false)
            }
            .onChange(of: destinationCurrencySelection) { value in
                selectDestinationAccount(for: value)
                configureConversion(preserveEditingRate: false)
            }
            .sheet(item: $addingAccountFor) { role in
                AccountEditorView(
                    initialGroup: .other,
                    initialCurrency: role == .source
                        ? normalizedCurrency(sourceCurrencySelection)
                        : normalizedCurrency(destinationCurrencySelection)
                ) { account in
                    selectNewAccount(account, for: role)
                }
                .environmentObject(store)
            }
            .sheet(item: $convertingTo) { newType in
                if let editingTransaction, newType != .transfer {
                    AddTransactionView(transaction: editingTransaction, convertTo: newType, onSaved: {
                        onSaved?()
                        dismiss()
                    })
                    .environmentObject(store)
                }
            }
        }
    }

    private func currencyPicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(availableCurrencies, id: \.self) { currency in
                Text(currency).tag(currency)
            }
        }
        .pickerStyle(.menu)
    }

    private func accountPicker(
        _ title: String,
        selection: Binding<UUID?>,
        currency: String
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Select Account").tag(Optional<UUID>.none)
            ForEach(filteredAccounts(currency: currency)) { account in
                Text(accountDisplayName(account))
                    .tag(Optional(account.id))
            }
        }
    }

    @ViewBuilder
    private func accountAvailabilityMessage(for role: TransferAccountRole) -> some View {
        let currency = role == .source ? sourceCurrencySelection : destinationCurrencySelection
        if filteredAccounts(currency: currency).isEmpty {
            Label(
                "No \(normalizedCurrency(currency)) account is available.",
                systemImage: "exclamationmark.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func addAccountButton(for role: TransferAccountRole) -> some View {
        Button {
            addingAccountFor = role
        } label: {
            Label("Add \(role.title) Account", systemImage: "plus.circle.fill")
        }
    }

    private func amountField(_ title: String, text: Binding<String>, currency: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(currency)
                    .foregroundStyle(.secondary)
                TextField(title, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedAmount, equals: .source)
            }
            calculatorButtons(for: .source)
        }
    }

    private var rateField: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("1 \(sourceCurrency) =")
                    .foregroundStyle(.secondary)
                TextField("Rate", text: $exchangeRateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedAmount, equals: .rate)
                Text(destinationCurrency)
                    .foregroundStyle(.secondary)
            }
            calculatorButtons(for: .rate)
        }
    }

    private func calculatorButtons(for field: AmountField) -> some View {
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

    private var availableCurrencies: [String] {
        let standard = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]
        return Array(Set(standard + store.activeAccounts.map { $0.currencyCode.uppercased() })).sorted()
    }

    private func filteredAccounts(currency: String) -> [LedgerAccount] {
        store.activeAccounts
            .filter { currency.isEmpty || $0.currencyCode.caseInsensitiveCompare(currency) == .orderedSame }
            .sorted {
                if $0.group != $1.group { return $0.group.title < $1.group.title }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private func accountDisplayName(_ account: LedgerAccount) -> String {
        if let parent = store.account(withID: account.parentAccountID) {
            return "↳ \(parent.name) / \(account.name)"
        }
        return account.name
    }

    private func normalizedCurrency(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return cleaned.isEmpty ? "QAR" : cleaned
    }

    private func selectNewAccount(_ account: LedgerAccount, for role: TransferAccountRole) {
        let currency = account.currencyCode.uppercased()
        if role == .source {
            sourceCurrencySelection = currency
            sourceAccountID = account.id
            if destinationAccountID == account.id {
                destinationAccountID = filteredAccounts(currency: destinationCurrencySelection)
                    .first(where: { $0.id != account.id })?.id
            }
        } else {
            destinationCurrencySelection = currency
            destinationAccountID = account.id
            if sourceAccountID == account.id {
                sourceAccountID = filteredAccounts(currency: sourceCurrencySelection)
                    .first(where: { $0.id != account.id })?.id
            }
        }
        configureConversion(preserveEditingRate: false)
    }

    private var sourceAccount: LedgerAccount? {
        store.account(withID: sourceAccountID)
    }

    private var destinationAccount: LedgerAccount? {
        store.account(withID: destinationAccountID)
    }

    private var sourceCurrency: String {
        if let sourceAccount { return sourceAccount.currencyCode.uppercased() }
        return sourceCurrencySelection.isEmpty ? "—" : sourceCurrencySelection.uppercased()
    }

    private var destinationCurrency: String {
        if let destinationAccount { return destinationAccount.currencyCode.uppercased() }
        return destinationCurrencySelection.isEmpty ? "—" : destinationCurrencySelection.uppercased()
    }

    private var isCrossCurrency: Bool {
        guard sourceAccount != nil, destinationAccount != nil else { return false }
        return sourceCurrency != destinationCurrency
    }

    private var sourceAmount: Decimal? {
        positiveDecimal(amountText)
    }

    private var fixedRate: Decimal? {
        guard isCrossCurrency else { return Decimal(1) }
        return defaultRate(from: sourceCurrency, to: destinationCurrency)
    }

    private var selectedRate: Decimal? {
        guard isCrossCurrency else { return Decimal(1) }
        if useCustomRate || fixedRate == nil {
            return positiveDecimal(exchangeRateText)
        }
        return fixedRate
    }

    private var receivedAmount: Decimal? {
        guard let sourceAmount else { return nil }
        guard isCrossCurrency else { return sourceAmount }
        guard let selectedRate else { return nil }
        return rounded(sourceAmount * selectedRate, scale: 2)
    }

    private var canSave: Bool {
        guard let sourceAccountID,
              let destinationAccountID,
              sourceAccountID != destinationAccountID,
              sourceAccount != nil,
              destinationAccount != nil,
              sourceAmount != nil else { return false }
        return receivedAmount != nil
    }

    private var saveValidationMessage: String? {
        if sourceAccountID == nil { return "Select a source account." }
        if destinationAccountID == nil { return "Select a destination account." }
        if sourceAccountID == destinationAccountID { return "Source and destination accounts must be different." }
        if sourceAmount == nil { return "Enter a valid amount greater than zero." }
        if isCrossCurrency && receivedAmount == nil {
            return "Enter a conversion rate for this currency pair."
        }
        return nil
    }

    private var conversionFooter: String {
        if fixedRate == nil {
            return "Enter how much \(destinationCurrency) equals 1 \(sourceCurrency). The source account is reduced in \(sourceCurrency), and the destination account is increased in \(destinationCurrency)."
        }
        return "Fixed rates: 1 QAR = 77 PKR and 1 USD = 3.65 QAR. Reverse and USD↔PKR rates are calculated automatically. Enable Custom Rate to override the fixed rate for this transfer."
    }

    private func positiveDecimal(_ text: String) -> Decimal? {
        guard let value = AmountExpression.evaluate(text), value > 0 else { return nil }
        return value
    }

    private func appendOperator(_ symbol: String) {
        if focusedAmount == .rate {
            exchangeRateText = AmountExpression.appending(symbol, to: exchangeRateText)
        } else {
            amountText = AmountExpression.appending(symbol, to: amountText)
        }
    }

    private func calculateFocusedAmount() {
        if focusedAmount == .rate {
            if let value = AmountExpression.evaluate(exchangeRateText) {
                exchangeRateText = NSDecimalNumber(decimal: value).stringValue
            }
        } else if let value = AmountExpression.evaluate(amountText) {
            amountText = NSDecimalNumber(decimal: value).stringValue
        }
    }

    private func chooseDefaults() {
        if sourceAccountID == nil {
            sourceAccountID = store.defaultAccountID ?? store.activeAccounts.first?.id
        }
        if let sourceAccount {
            sourceCurrencySelection = sourceAccount.currencyCode.uppercased()
        } else if let first = availableCurrencies.first {
            sourceCurrencySelection = first
            sourceAccountID = filteredAccounts(currency: first).first?.id
        }

        if destinationAccountID == nil || destinationAccountID == sourceAccountID {
            destinationAccountID = store.activeAccounts.first(where: { $0.id != sourceAccountID })?.id
        }
        if let destinationAccount {
            destinationCurrencySelection = destinationAccount.currencyCode.uppercased()
        } else if let first = availableCurrencies.first {
            destinationCurrencySelection = first
            destinationAccountID = filteredAccounts(currency: first)
                .first(where: { $0.id != sourceAccountID })?.id
        }
    }

    private func selectSourceAccount(for currency: String) {
        guard !currency.isEmpty else { return }
        if sourceAccount?.currencyCode.caseInsensitiveCompare(currency) != .orderedSame {
            sourceAccountID = filteredAccounts(currency: currency)
                .first(where: { $0.id != destinationAccountID })?.id
                ?? filteredAccounts(currency: currency).first?.id
        }
    }

    private func selectDestinationAccount(for currency: String) {
        guard !currency.isEmpty else { return }
        if destinationAccount?.currencyCode.caseInsensitiveCompare(currency) != .orderedSame ||
            destinationAccountID == sourceAccountID {
            destinationAccountID = filteredAccounts(currency: currency)
                .first(where: { $0.id != sourceAccountID })?.id
        }
    }

    private func configureConversion(preserveEditingRate: Bool) {
        guard let sourceAccount, let destinationAccount else { return }
        guard sourceAccount.currencyCode.caseInsensitiveCompare(destinationAccount.currencyCode) != .orderedSame else {
            useCustomRate = false
            exchangeRateText = "1"
            return
        }

        if preserveEditingRate,
           let transaction = editingTransaction,
           transaction.accountID == sourceAccount.id,
           transaction.destinationAccountID == destinationAccount.id,
           transaction.amount > 0,
           let destinationAmount = transaction.destinationAmount,
           destinationAmount > 0 {
            let storedRate = destinationAmount / transaction.amount
            if let fixedRate, approximatelyEqual(storedRate, fixedRate) {
                useCustomRate = false
                exchangeRateText = rateString(fixedRate)
            } else {
                useCustomRate = true
                exchangeRateText = rateString(storedRate)
            }
            return
        }

        if let fixedRate {
            useCustomRate = false
            exchangeRateText = rateString(fixedRate)
        } else {
            useCustomRate = true
            exchangeRateText = ""
        }
    }

    private func defaultRate(from source: String, to destination: String) -> Decimal? {
        if ERPAccountingEngine.isEnabled && ERPStorage.bool(ERPKey.transferUseConfiguredRate, true) {
            return ERPAccountingEngine.rate(from: source, to: destination, on: date)
        }
        return store.fixedReportConversionRate(from: source, to: destination)
    }

    private func rounded(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var output = Decimal.zero
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    private func rateString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: rounded(value, scale: 6)).stringValue
    }

    private func approximatelyEqual(_ lhs: Decimal, _ rhs: Decimal) -> Bool {
        let tolerance = Decimal(string: "0.000001")!
        let difference = lhs >= rhs ? lhs - rhs : rhs - lhs
        return difference <= tolerance
    }

    private func save() {
        guard let sourceAccountID,
              let destinationAccountID,
              let sourceAmount,
              let receivedAmount else { return }
        let dimensions = ERPAccountingEngine.dimensions(from: erpDimensions)
        let saved: Bool
        if var transaction = editingTransaction {
            transaction.type = .transfer
            transaction.amount = sourceAmount
            transaction.destinationAmount = receivedAmount
            transaction.accountID = sourceAccountID
            transaction.destinationAccountID = destinationAccountID
            transaction.category = "Transfer"
            transaction.vendor = nil
            transaction.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
            transaction.date = date
            transaction.dimensions = dimensions
            saved = store.update(transaction)
        } else {
            saved = store.addTransfer(
                from: sourceAccountID,
                to: destinationAccountID,
                amount: sourceAmount,
                destinationAmount: receivedAmount,
                date: date,
                details: details,
                dimensions: dimensions
            )
        }
        guard saved else { return }
        onSaved?()
        dismiss()
    }
}
