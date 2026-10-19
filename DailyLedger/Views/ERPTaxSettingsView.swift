import SwiftUI

struct ERPTaxSettingsView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage(ERPKey.taxEnabled) private var enabled = false
    @AppStorage(ERPKey.taxDefaultRatePercent) private var defaultRate = 0.0
    @AppStorage(ERPKey.taxDefaultInclusive) private var defaultInclusive = true
    @AppStorage(ERPKey.taxDefaultRecoverablePercent) private var recoverable = 100.0
    @State private var rules = ERPAccountingEngine.taxRules
    @State private var editing: ERPTaxRule?
    @State private var adding = false

    var body: some View {
        List {
            Section("Tax Engine") {
                Toggle("Enable Tax / VAT reporting", isOn: $enabled)
                HStack {
                    Text("Default tax rate %")
                    Spacer()
                    TextField("0", value: $defaultRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Toggle("Default amount includes tax", isOn: $defaultInclusive)
                HStack {
                    Text("Default recoverable input %")
                    Spacer()
                    TextField("100", value: $recoverable, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }

            Section {
                NavigationLink { ERPTaxReportView() } label: {
                    Label("Open Tax / VAT Report", systemImage: "doc.text.fill")
                }
                Button { adding = true } label: {
                    Label("Add Category Tax Rule", systemImage: "plus.circle.fill")
                }
            }

            Section("Category Rules") {
                if rules.isEmpty {
                    Text("No category-specific rules. The default rate is used when Tax reporting is enabled.")
                        .foregroundStyle(.secondary)
                }
                ForEach(rules) { rule in
                    Button { editing = rule } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name).font(.headline).foregroundStyle(.primary)
                                Text("\(NSDecimalNumber(decimal: rule.ratePercent).stringValue)% · \(rule.inclusive ? "Inclusive" : "Exclusive") · Recoverable \(NSDecimalNumber(decimal: rule.recoverablePercent).stringValue)%")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !rule.categoryContains.isEmpty {
                                    Text("Category contains: \(rule.categoryContains)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: rule.enabled ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(rule.enabled ? AppTheme.green : .secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Tax / VAT")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack {
                ERPTaxRuleEditor(rule: ERPTaxRule()) { value in
                    rules.append(value); save(); adding = false
                }
            }
        }
        .sheet(item: $editing) { rule in
            NavigationStack {
                ERPTaxRuleEditor(rule: rule) { value in
                    if let index = rules.firstIndex(where: { $0.id == value.id }) { rules[index] = value }
                    save(); editing = nil
                }
            }
        }
        .onAppear { rules = ERPAccountingEngine.taxRules }
        .onDisappear { save(); store.reload() }
    }

    private func delete(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        save()
    }

    private func save() { ERPAccountingEngine.taxRules = rules }
}

private struct ERPTaxRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: ERPTaxRule
    @State private var rateText: String
    @State private var recoverableText: String
    let onSave: (ERPTaxRule) -> Void

    init(rule: ERPTaxRule, onSave: @escaping (ERPTaxRule) -> Void) {
        _rule = State(initialValue: rule)
        _rateText = State(initialValue: NSDecimalNumber(decimal: rule.ratePercent).stringValue)
        _recoverableText = State(initialValue: NSDecimalNumber(decimal: rule.recoverablePercent).stringValue)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Rule name", text: $rule.name)
                TextField("Category contains (blank = all)", text: $rule.categoryContains)
                Toggle("Enabled", isOn: $rule.enabled)
            }
            Section("Tax Treatment") {
                HStack { Text("Tax rate %"); Spacer(); TextField("0", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Toggle("Transaction amount includes tax", isOn: $rule.inclusive)
                HStack { Text("Recoverable input %"); Spacer(); TextField("100", text: $recoverableText).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            Section("Applies To") {
                Toggle("Income", isOn: $rule.appliesToIncome)
                Toggle("Expense", isOn: $rule.appliesToExpense)
            }
        }
        .navigationTitle("Tax Rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    rule.ratePercent = Decimal(string: rateText) ?? 0
                    rule.recoverablePercent = max(0, min(100, Decimal(string: recoverableText) ?? 100))
                    rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    rule.categoryContains = rule.categoryContains.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(rule); dismiss()
                }
                .disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Decimal(string: rateText) == nil)
            }
        }
    }
}

struct ERPTaxReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var start = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var end = Date()
    @State private var currency = "QAR"

    private var interval: DateInterval {
        DateInterval(
            start: Calendar.current.startOfDay(for: start),
            end: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(start, end))) ?? end
        )
    }

    private var summary: ERPTaxSummary { store.erpTaxSummary(interval: interval, currencyCode: currency) }
    private var currencies: [String] { Array(Set([store.currencyCode, "QAR", "PKR", "USD", "EUR", "GBP", "AED", "SAR", "INR"] + store.accounts.map { $0.currencyCode.uppercased() })).sorted() }

    var body: some View {
        List {
            Section("Period") {
                DatePicker("From", selection: $start, displayedComponents: .date)
                DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                Picker("Report currency", selection: $currency) { ForEach(currencies, id: \.self) { Text($0).tag($0) } }
            }
            Section("Tax Summary") {
                taxRow("Output tax on income", summary.outputTax)
                taxRow("Input tax on expenses", summary.inputTax)
                taxRow("Recoverable input tax", summary.recoverableInputTax)
                taxRow("Net tax due / (recoverable)", summary.netTaxDue, emphasized: true)
            }
            Section {
                Text("This report applies the configured Tax/VAT rules to ledger transaction amounts. It is a reporting calculation and does not create separate tax journal entries automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tax / VAT Report")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { currency = store.currencyCode }
    }

    private func taxRow(_ title: String, _ value: Decimal, emphasized: Bool = false) -> some View {
        HStack {
            Text(title).font(emphasized ? .headline : .body)
            Spacer()
            Text(DisplayFormat.currency(value, code: currency)).font(emphasized ? .headline : .body)
                .foregroundStyle(value < 0 ? AppTheme.red : .primary)
        }
    }
}
