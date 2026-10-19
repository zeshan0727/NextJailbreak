import SwiftUI

struct ERPCurrencySettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage(ERPKey.rateSource) private var rateSource = ERPRateSource.customThenLegacy.rawValue
    @AppStorage(ERPKey.rateAllowInverse) private var allowInverse = true
    @AppStorage(ERPKey.rateAllowTriangulation) private var allowTriangulation = true
    @AppStorage(ERPKey.ratePivotCurrency) private var pivot = "QAR"
    @AppStorage(ERPKey.rateMissingPolicy) private var missingPolicy = ERPMissingRatePolicy.exclude.rawValue
    @AppStorage(ERPKey.legacyQARPKR) private var legacyQARPKR = 77.0
    @AppStorage(ERPKey.legacyUSDQAR) private var legacyUSDQAR = 3.65
    @AppStorage(ERPKey.reportAmountDecimals) private var amountDecimals = 2
    @AppStorage(ERPKey.reportRateDecimals) private var rateDecimals = 6
    @AppStorage(ERPKey.reportRoundingMode) private var rounding = ERPRoundingMode.plain.rawValue
    @AppStorage(ERPKey.useTransactionDateForRates) private var historical = true
    @State private var rates = ERPAccountingEngine.currencyRates
    @State private var editingRate: ERPCurrencyRate?
    @State private var creatingRate = false
    @State private var selectedReportingCurrency = "QAR"
    @State private var testFrom = "QAR"
    @State private var testTo = "PKR"
    @State private var testAmount = 1.0

    private var currencies: [String] {
        Array(Set(["QAR", "PKR", "USD", "EUR", "GBP", "AED", "SAR", "INR"] + store.accounts.map { $0.currencyCode.uppercased() } + rates.flatMap { [$0.fromCurrency.uppercased(), $0.toCurrency.uppercased()] })).sorted()
    }

    var body: some View {
        Form {
            Section("Reporting Currency") {
                Picker("Reporting currency", selection: $selectedReportingCurrency) {
                    ForEach(currencies, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: selectedReportingCurrency) { store.updateCurrency($0) }
            }

            Section("Rate Engine") {
                Picker("Rate source", selection: $rateSource) {
                    ForEach(ERPRateSource.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Allow automatic inverse rates", isOn: $allowInverse)
                Toggle("Allow cross-rate triangulation", isOn: $allowTriangulation)
                if allowTriangulation {
                    Picker("Pivot currency", selection: $pivot) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                }
                Picker("Missing rate", selection: $missingPolicy) {
                    ForEach(ERPMissingRatePolicy.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
                Toggle("Use transaction date for report rates", isOn: $historical)
            }

            Section("Editable Legacy Rates") {
                HStack {
                    Text("1 QAR =")
                    Spacer()
                    TextField("77", value: $legacyQARPKR, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("PKR").foregroundStyle(.secondary)
                }
                HStack {
                    Text("1 USD =")
                    Spacer()
                    TextField("3.65", value: $legacyUSDQAR, format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text("QAR").foregroundStyle(.secondary)
                }
                Text("These two rates remain the fallback for old QAR / PKR / USD behavior. Custom dated rates can override them.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Precision") {
                Stepper("Report amount decimals: \(amountDecimals)", value: $amountDecimals, in: 0...6)
                Stepper("Exchange-rate decimals: \(rateDecimals)", value: $rateDecimals, in: 2...12)
                Picker("Rounding", selection: $rounding) {
                    ForEach(ERPRoundingMode.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            }

            Section {
                Button {
                    creatingRate = true
                } label: { Label("Add Exchange Rate", systemImage: "plus.circle.fill") }
            } header: { Text("Dated Exchange Rates") }

            Section {
                if rates.isEmpty {
                    Text("No custom rates. Legacy QAR/PKR/USD fallback is available according to Rate Source.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rates.sorted { $0.pairTitle < $1.pairTitle }) { rate in
                        Button {
                            editingRate = rate
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rate.pairTitle).font(.headline).foregroundStyle(.primary)
                                    Text("1 \(rate.fromCurrency.uppercased()) = \(NSDecimalNumber(decimal: rate.rate).stringValue) \(rate.toCurrency.uppercased())")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(rate.effectiveFrom.formatted(date: .abbreviated, time: .omitted) + (rate.effectiveTo.map { " → \($0.formatted(date: .abbreviated, time: .omitted))" } ?? " → Open"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: rate.enabled ? "checkmark.circle.fill" : "pause.circle")
                                    .foregroundStyle(rate.enabled ? AppTheme.green : .secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRates)
                }
            }

            Section("Rate Calculator") {
                Picker("From", selection: $testFrom) { ForEach(currencies, id: \.self) { Text($0).tag($0) } }
                Picker("To", selection: $testTo) { ForEach(currencies, id: \.self) { Text($0).tag($0) } }
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("1", value: $testAmount, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                LabeledContent("Converted") {
                    if let value = testConverted {
                        Text("\(NSDecimalNumber(decimal: value).stringValue) \(testTo)")
                    } else {
                        Text("No rate").foregroundStyle(AppTheme.red)
                    }
                }
            }
        }
        .navigationTitle("Currencies & FX")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedReportingCurrency = store.currencyCode
            rates = ERPAccountingEngine.currencyRates
        }
        .sheet(isPresented: $creatingRate) {
            NavigationStack {
                ERPCurrencyRateEditor(rate: ERPCurrencyRate(fromCurrency: testFrom, toCurrency: testTo)) { value in
                    rates.append(value)
                    saveRates()
                    creatingRate = false
                }
            }
        }
        .sheet(item: $editingRate) { rate in
            NavigationStack {
                ERPCurrencyRateEditor(rate: rate) { value in
                    if let index = rates.firstIndex(where: { $0.id == value.id }) { rates[index] = value }
                    saveRates()
                    editingRate = nil
                }
            }
        }
        .onDisappear { saveRates(); store.reload() }
    }

    private var testConverted: Decimal? {
        guard let rate = ERPAccountingEngine.rate(from: testFrom, to: testTo, on: Date()) else { return nil }
        return ERPAccountingEngine.round(Decimal(testAmount) * rate)
    }

    private func deleteRates(at offsets: IndexSet) {
        let sorted = rates.sorted { $0.pairTitle < $1.pairTitle }
        let ids = offsets.compactMap { sorted.indices.contains($0) ? sorted[$0].id : nil }
        rates.removeAll { ids.contains($0.id) }
        saveRates()
    }

    private func saveRates() {
        ERPAccountingEngine.currencyRates = rates
    }
}

private struct ERPCurrencyRateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rate: ERPCurrencyRate
    @State private var rateText: String
    @State private var useEndDate: Bool
    let onSave: (ERPCurrencyRate) -> Void

    init(rate: ERPCurrencyRate, onSave: @escaping (ERPCurrencyRate) -> Void) {
        _rate = State(initialValue: rate)
        _rateText = State(initialValue: NSDecimalNumber(decimal: rate.rate).stringValue)
        _useEndDate = State(initialValue: rate.effectiveTo != nil)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Pair") {
                TextField("From currency", text: $rate.fromCurrency).textInputAutocapitalization(.characters)
                TextField("To currency", text: $rate.toCurrency).textInputAutocapitalization(.characters)
                HStack {
                    Text("1 \(rate.fromCurrency.uppercased()) =")
                    Spacer()
                    TextField("Rate", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    Text(rate.toCurrency.uppercased()).foregroundStyle(.secondary)
                }
            }
            Section("Effective Dates") {
                DatePicker("Effective from", selection: $rate.effectiveFrom, displayedComponents: .date)
                Toggle("Set end date", isOn: $useEndDate)
                if useEndDate {
                    DatePicker("Effective through", selection: Binding(
                        get: { rate.effectiveTo ?? Date() },
                        set: { rate.effectiveTo = $0 }
                    ), in: rate.effectiveFrom..., displayedComponents: .date)
                }
            }
            Section("Control") {
                Toggle("Enabled", isOn: $rate.enabled)
                TextField("Note", text: $rate.note)
            }
        }
        .navigationTitle("Exchange Rate")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let value = Decimal(string: rateText), value > 0 else { return }
                    rate.rate = value
                    rate.fromCurrency = rate.fromCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    rate.toCurrency = rate.toCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if !useEndDate { rate.effectiveTo = nil }
                    onSave(rate)
                    dismiss()
                }
                .disabled(rate.fromCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rate.toCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Decimal(string: rateText) == nil)
            }
        }
    }
}
