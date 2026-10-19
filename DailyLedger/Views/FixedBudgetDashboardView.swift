import SwiftUI

/// Fixed monthly plan. Uses the ledger's native persistence and JSON backup;
/// no parallel UserDefaults storage or replacement of existing transactions.
struct FixedBudgetDashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var grocery = 45.0
    @State private var fuel = 25.0
    @State private var eatOut = 15.0
    @State private var addingKind: FixedPlanKind = .expense
    @State private var adding = false
    @State private var editing: FixedPlanItem?

    private var plan: MonthlyFixedBudget { store.fixedBudget }
    private var cycle: Date { BudgetCycle.start(containing: Date()) }
    private var income: Decimal { plan.total(.income, in: cycle) }
    private var expenses: Decimal { plan.total(.expense, in: cycle) }
    private var available: Decimal { income - expenses }
    private var allocationTotal: Int { Int(grocery + fuel + eatOut) }
    private var isValidAllocation: Bool { allocationTotal <= 100 }
    private var currency: String { store.currencyCode }

    private var cycleLabel: String {
        BudgetCycle.title(start: cycle)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label(cycleLabel, systemImage: "calendar")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    HStack {
                        summary("Fixed income", value: income, color: .green)
                        Spacer(minLength: 8)
                        summary("Fixed expenses", value: expenses, color: .orange)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Available to Spend")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(DisplayFormat.currency(available, code: currency))
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .foregroundStyle(available < 0 ? .red : .primary)
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("Monthly Overview · 26th to 25th")
            } footer: {
                Text("Only active fixed items for this salary-month cycle are included. Actual ledger transactions are not modified.")
            }

            Section {
                if plan.items.filter({ $0.kind == .income }).isEmpty {
                    Text("Add your salary and Amara's salary as recurring income.")
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.items.filter { $0.kind == .income }.sorted { $0.title < $1.title }) { item in
                    itemRow(item)
                }
                Button {
                    addingKind = .income
                    adding = true
                } label: {
                    Label("Add Fixed Income", systemImage: "plus.circle.fill")
                }
            } header: { Text("Fixed Monthly Income") }

            Section {
                if plan.items.filter({ $0.kind == .expense }).isEmpty {
                    Text("Add recurring bills with a duration, or choose Ongoing.")
                        .foregroundStyle(.secondary)
                }
                ForEach(plan.items.filter { $0.kind == .expense }.sorted { $0.title < $1.title }) { item in
                    itemRow(item)
                }
                Button {
                    addingKind = .expense
                    adding = true
                } label: {
                    Label("Add Fixed Expense", systemImage: "plus.circle.fill")
                }
            } header: { Text("Fixed Monthly Expenses") }
            footer: {
                Text("Limited-duration items expire automatically after their selected number of 26th–25th cycles. Expired items stay in your saved plan for history.")
            }

            Section {
                allocationSlider("Groceries", value: $grocery, symbol: "basket.fill")
                allocationSlider("Fuel", value: $fuel, symbol: "fuelpump.fill")
                allocationSlider("Eat Out", value: $eatOut, symbol: "fork.knife")
                if allocationTotal > 100 {
                    Label("Percentages exceed 100%. Reduce the sliders before applying.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    LabeledContent("Unallocated", value: "\(100 - allocationTotal)%")
                }
                Button {
                    var updated = plan
                    updated.setAllocation(grocery: Int(grocery),
                                          fuel: Int(fuel),
                                          eatOut: Int(eatOut),
                                          cycle: cycle)
                    store.saveFixedBudget(updated)
                } label: {
                    Label("Apply This Cycle's Budget", systemImage: "checkmark.circle.fill")
                        .fontWeight(.semibold)
                }
                .disabled(!isValidAllocation || available <= 0)
            } header: {
                Text("One-Tap Essentials Budget")
            } footer: {
                Text("Based on the available amount after fixed expenses. Each cycle's applied percentages are saved separately.")
            }
        }
        .navigationTitle("Fixed Monthly Budget")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack {
                FixedPlanItemEditor(kind: addingKind, item: nil, currency: currency) { item in
                    saveItem(item)
                }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                FixedPlanItemEditor(kind: item.kind, item: item, currency: currency) { saved in
                    saveItem(saved)
                }
            }
        }
        .onAppear(perform: loadAllocations)
    }

    private func summary(_ title: String, value: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(DisplayFormat.currency(value, code: currency))
                .font(.headline).foregroundStyle(color)
                .minimumScaleFactor(0.65).lineLimit(1)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: FixedPlanItem) -> some View {
        HStack(spacing: 8) {
            Button {
                editing = item
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.subheadline.weight(.semibold))
                    Text(itemStatus(item))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(DisplayFormat.currency(item.amount, code: currency))
                    .font(.subheadline.weight(.semibold))
                Button(role: .destructive) {
                    var updated = plan
                    updated.items.removeAll { $0.id == item.id }
                    store.saveFixedBudget(updated)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .accessibilityLabel("Delete \(item.title)")
            }
        }
    }

    private func itemStatus(_ item: FixedPlanItem) -> String {
        let first = BudgetCycle.start(containing: item.firstCycle)
        if cycle < first { return "Starts \(first.formatted(date: .abbreviated, time: .omitted))" }
        if let duration = item.durationCycles {
            if !item.isActive(in: cycle) { return "Expired after \(duration) cycles" }
            let months = item.elapsedCycles(through: cycle)
            return "Cycle \(months) of \(duration)"
        }
        return "Ongoing"
    }

    private func allocationSlider(_ name: String,
                                  value: Binding<Double>,
                                  symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(name, systemImage: symbol)
                Spacer()
                Text("\(Int(value.wrappedValue))%")
                    .fontWeight(.semibold)
            }
            Slider(value: value, in: 0...100, step: 5)
            if isValidAllocation {
                let proportion = Decimal(Int(value.wrappedValue)) / 100
                Text(DisplayFormat.currency(max(0, available) * proportion, code: currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func loadAllocations() {
        let allocation = plan.savedAllocation(in: cycle)
        grocery = Double(allocation?.groceryPercent ?? plan.groceryPercent)
        fuel = Double(allocation?.fuelPercent ?? plan.fuelPercent)
        eatOut = Double(allocation?.eatOutPercent ?? plan.eatOutPercent)
    }

    private func saveItem(_ item: FixedPlanItem) {
        var updated = plan
        if let index = updated.items.firstIndex(where: { $0.id == item.id }) {
            updated.items[index] = item
        } else {
            updated.items.append(item)
        }
        store.saveFixedBudget(updated)
    }
}

private struct FixedPlanItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    let kind: FixedPlanKind
    let item: FixedPlanItem?
    let currency: String
    let onSave: (FixedPlanItem) -> Void
    @State private var title: String
    @State private var amountText: String
    @State private var firstCycle: Date
    @State private var isLimited: Bool
    @State private var duration: Int

    init(kind: FixedPlanKind, item: FixedPlanItem?, currency: String,
         onSave: @escaping (FixedPlanItem) -> Void) {
        self.kind = kind
        self.item = item
        self.currency = currency
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _amountText = State(initialValue: item.map {
            NSDecimalNumber(decimal: $0.amount).stringValue
        } ?? "")
        _firstCycle = State(initialValue: item?.firstCycle ?? Date())
        _isLimited = State(initialValue: item?.durationCycles != nil)
        _duration = State(initialValue: item?.durationCycles ?? 1)
    }

    private var decimalAmount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        Form {
            Section {
                TextField(kind == .income ? "Salary / income name" : "Expense name", text: $title)
                    .textInputAutocapitalization(.words)
                HStack {
                    Text(currency)
                    TextField("Monthly amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }
                DatePicker("First active month", selection: $firstCycle, displayedComponents: .date)
            }
            Section("Recurrence") {
                Toggle("Limited number of months", isOn: $isLimited)
                if isLimited {
                    Stepper("\(duration) monthly cycles", value: $duration, in: 1...120)
                } else {
                    Label("Ongoing each month", systemImage: "repeat")
                }
            } footer: {
                Text("Each cycle runs from the 26th to the following 25th. Limited entries automatically stop when the selected cycles finish.")
            }
        }
        .navigationTitle(item == nil ? "Add \(kind.title)" : "Edit \(kind.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let amount = decimalAmount, amount > 0 else { return }
                    onSave(FixedPlanItem(id: item?.id ?? UUID(),
                                         kind: kind,
                                         title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                         amount: amount,
                                         firstCycle: BudgetCycle.start(containing: firstCycle),
                                         durationCycles: isLimited ? duration : nil))
                    dismiss()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || decimalAmount == nil || (decimalAmount ?? 0) <= 0)
            }
        }
    }
}
