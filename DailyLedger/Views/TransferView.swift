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


    // Design 2: native, accessible and compact without changing transfer posting logic.
    private enum TransferDesign {
        static let canvas = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let blue = Color(red: 0.18, green: 0.37, blue: 0.96)
        static let navy = Color(uiColor: .label)
        static let muted = Color(uiColor: .secondaryLabel)
        static let line = Color(uiColor: .separator)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    transferHeading
                    transferRoute
                    transferAmountCard
                    if isCrossCurrency {
                        exchangeCard
                    }
                    transferDetailsCard
                    ERPTransactionDimensionsEditor(values: $erpDimensions, type: .transfer)
                    if let saveValidationMessage {
                        Label(saveValidationMessage, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(TransferDesign.muted)
                            .padding(.horizontal, 7)
                    }
                    if let editingTransaction {
                        editActions(for: editingTransaction)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            .background(TransferDesign.canvas.ignoresSafeArea())
            .navigationTitle(editingTransaction == nil ? "New Transfer" : "Edit Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    ForEach(["+", "−", "×", "÷"], id: \.self) { symbol in
                        Button(symbol) { appendOperator(symbol) }
                    }
                    Button("=", action: calculateFocusedAmount)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                transferActionBar
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


    private var transferHeading: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(TransferDesign.blue,
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(editingTransaction == nil ? "Transfer" : "Edit Transfer")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(TransferDesign.navy)
                Text("Move money between your accounts")
                    .font(.subheadline)
                    .foregroundStyle(TransferDesign.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    private var transferRoute: some View {
        VStack(spacing: 0) {
            routeAccount(
                label: "From Account", role: .source,
                account: sourceAccount, selection: $sourceAccountID,
                currencySelection: $sourceCurrencySelection
            )
            HStack {
                Spacer()
                Button(action: swapAccounts) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TransferDesign.blue)
                        .frame(width: 40, height: 40)
                        .background(TransferDesign.canvas, in: Circle())
                        .overlay(Circle().stroke(TransferDesign.blue.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Swap source and destination accounts")
                Spacer()
            }
            .padding(.vertical, -2)
            .zIndex(1)
            routeAccount(
                label: "To Account", role: .destination,
                account: destinationAccount, selection: $destinationAccountID,
                currencySelection: $destinationCurrencySelection
            )
            HStack {
                addAccountButton(for: .source)
                Spacer(minLength: 8)
                addAccountButton(for: .destination)
            }
            .padding(.top, 14)
        }
        .padding(14)
        .background(TransferDesign.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func routeAccount(label: String, role: TransferAccountRole,
                              account: LedgerAccount?,
                              selection: Binding<UUID?>,
                              currencySelection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TransferDesign.muted)
                Spacer()
                Menu {
                    ForEach(availableCurrencies, id: \.self) { currency in
                        Button(currency) { currencySelection.wrappedValue = currency }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(normalizedCurrency(currencySelection.wrappedValue))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TransferDesign.blue)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(TransferDesign.blue.opacity(0.08), in: Capsule())
                }
                .accessibilityLabel(label + " currency")
            }
            Picker(label, selection: selection) {
                Text("Select Account").tag(Optional<UUID>.none)
                ForEach(filteredAccounts(currency: currencySelection.wrappedValue)) { item in
                    Text(accountDisplayName(item)).tag(Optional(item.id))
                }
            }
            .pickerStyle(.menu)
            .tint(TransferDesign.navy)
            .labelsHidden()
            .accessibilityLabel(label)
            HStack(spacing: 7) {
                Image(systemName: role == .source ? "wallet.bifold.fill" : "building.columns.fill")
                    .foregroundStyle(TransferDesign.blue)
                if let account {
                    Text(account.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(TransferDesign.navy)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(DisplayFormat.currency(store.balance(for: account),
                                               code: account.currencyCode))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TransferDesign.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                } else {
                    Text("Select an account to continue")
                        .font(.footnote)
                        .foregroundStyle(TransferDesign.muted)
                    Spacer(minLength: 0)
                }
            }
            accountAvailabilityMessage(for: role)
        }
        .padding(14)
        .background(TransferDesign.canvas,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(TransferDesign.blue.opacity(0.08), lineWidth: 1)
        }
    }

    private var transferAmountCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Amount")
                    .font(.headline)
                Spacer()
                Text(sourceCurrency)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TransferDesign.blue)
            }
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .foregroundStyle(TransferDesign.blue)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .focused($focusedAmount, equals: .source)
                    .accessibilityLabel("Amount sent in " + sourceCurrency)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 70)
            .background(TransferDesign.canvas,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(TransferDesign.blue.opacity(0.18), lineWidth: 1)
            }
            HStack(spacing: 6) {
                ForEach(["100", "500", "1000", "5000", "10000"], id: \.self) { amount in
                    Button {
                        amountText = amount
                        focusedAmount = nil
                    } label: {
                        Text(Decimal(string: amount)?.formatted(.number) ?? amount)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(TransferDesign.blue)
                            .background(TransferDesign.blue.opacity(0.08),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Set amount to " + amount)
                }
            }
        }
        .padding(16)
        .background(TransferDesign.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var exchangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Currency Conversion", systemImage: "arrow.left.arrow.right.circle.fill")
                .font(.headline)
                .foregroundStyle(TransferDesign.navy)
            if let fixedRate {
                Toggle("Use Custom Rate", isOn: $useCustomRate)
                    .tint(TransferDesign.blue)
                if !useCustomRate {
                    LabeledContent("Conversion Rate",
                                   value: "1 \(sourceCurrency) = \(rateString(fixedRate)) \(destinationCurrency)")
                }
            }
            if fixedRate == nil {
                Label("Custom conversion rate required", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(TransferDesign.muted)
            }
            if useCustomRate || fixedRate == nil { rateField }
            Divider()
            LabeledContent("Amount Sent",
                           value: sourceAmount.map { DisplayFormat.currency($0, code: sourceCurrency) } ?? "—")
            LabeledContent("Amount Received",
                           value: receivedAmount.map { DisplayFormat.currency($0, code: destinationCurrency) } ?? "—")
            Text(conversionFooter)
                .font(.caption)
                .foregroundStyle(TransferDesign.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(TransferDesign.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var transferDetailsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Details", systemImage: "note.text")
                .font(.headline)
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(TransferDesign.blue)
                TextField("Note (optional)", text: $details)
                    .textInputAutocapitalization(.sentences)
            }
            .padding(.vertical, 12)
            Divider()
            DatePicker("Date", selection: $date, displayedComponents: [.date])
                .font(.subheadline.weight(.medium))
            Divider()
            DatePicker("Time", selection: $date, displayedComponents: [.hourAndMinute])
                .font(.subheadline.weight(.medium))
        }
        .padding(16)
        .background(TransferDesign.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var transferActionBar: some View {
        Button(action: save) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                Text(editingTransaction == nil ? "Transfer" : "Update Transfer")
            }
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(TransferDesign.blue.opacity(canSave ? 1 : 0.38),
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(.regularMaterial)
    }

    private func editActions(for transaction: LedgerTransaction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Change transaction type")
                .font(.caption.weight(.medium))
                .foregroundStyle(TransferDesign.muted)
            HStack {
                Button("Convert to Income") { convertingTo = .income }
                Spacer()
                Button("Convert to Expense") { convertingTo = .expense }
            }
            .font(.subheadline)
            Divider()
            Button(role: .destructive) {
                store.delete(transaction)
                dismiss()
            } label: {
                Label("Delete Transfer", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.subheadline)
        }
        .padding(16)
        .background(TransferDesign.surface,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func swapAccounts() {
        let oldSource = sourceAccountID
        let oldCurrency = sourceCurrencySelection
        sourceAccountID = destinationAccountID
        destinationAccountID = oldSource
        sourceCurrencySelection = destinationCurrencySelection
        destinationCurrencySelection = oldCurrency
        configureConversion(preserveEditingRate: false)
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
