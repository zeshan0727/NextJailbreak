import SwiftUI

private enum FixedExpenseFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case short = "Short Term"
    case ongoing = "Long Term"
    var id: String { rawValue }
}

private enum EssentialsCategory {
    case grocery, fuel, eatOut
}

private struct FixedBudgetEditorRequest: Identifiable {
    let id = UUID()
    let kind: FixedPlanKind
    var item: FixedPlanItem?
    var suggestedTitle: String = ""
}

/// Native iOS 16+ screen for the personal 26th-to-25th monthly budget.
struct MonthlyBudgetView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedCycle = BudgetCycle.start(containing: Date())
    @State private var expenseFilter: FixedExpenseFilter = .all
    @State private var editor: FixedBudgetEditorRequest?
    @State private var grocery = 45
    @State private var fuel = 25
    @State private var eatOut = 15
    @State private var showAppliedConfirmation = false

    private let blue = Color(red: 0.20, green: 0.30, blue: 0.98)
    private let darkBlue = Color(red: 0.10, green: 0.17, blue: 0.43)
    private let green = Color(red: 0.02, green: 0.61, blue: 0.42)
    private let red = Color(red: 0.79, green: 0.14, blue: 0.25)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    header
                    cycleBanner
                    incomeSummary
                    expensesCard
                    essentialsCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarHidden(true)
            .sheet(item: $editor) { request in
                FixedPlanEditorView(
                    kind: request.kind, item: request.item, suggestedTitle: request.suggestedTitle
                )
                .environmentObject(store)
            }
            .alert("Budget Plan Saved", isPresented: $showAppliedConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your essentials percentages are saved for \(BudgetCycle.title(start: selectedCycle)).")
            }
            .onAppear(perform: loadPercentages)
            .onChange(of: selectedCycle) { _ in loadPercentages() }
        }
    }

    private var incomeItems: [FixedPlanItem] {
        store.fixedBudget.activeItems(.income, in: selectedCycle)
    }

    private var expenseItems: [FixedPlanItem] {
        store.fixedBudget.activeItems(.expense, in: selectedCycle)
    }

    private var displayedExpenses: [FixedPlanItem] {
        switch expenseFilter {
        case .all: return expenseItems
        case .short: return expenseItems.filter { $0.durationCycles != nil }
        case .ongoing: return expenseItems.filter { $0.durationCycles == nil }
        }
    }

    private var totalIncome: Decimal { store.fixedBudget.total(.income, in: selectedCycle) }
    private var totalExpense: Decimal { store.fixedBudget.total(.expense, in: selectedCycle) }
    private var available: Decimal { totalIncome - totalExpense }
    private var allocatable: Decimal { max(Decimal.zero, available) }
    private var otherPercent: Int { max(0, 100 - grocery - fuel - eatOut) }

    private func currency(_ amount: Decimal) -> String {
        DisplayFormat.currency(amount, code: store.currencyCode)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                (
                    Text("Next ").foregroundColor(Color.primary) +
                    Text("Ledger").foregroundColor(blue)
                )
                .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("Plan Today. A Better Tomorrow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chart.pie.fill")
                .foregroundStyle(blue)
                .font(.title3)
                .frame(width: 43, height: 43)
                .background(blue.opacity(0.09), in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 3)
    }

    private var cycleBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Monthly Budget", systemImage: "calendar")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Button {
                        selectedCycle = BudgetCycle.shift(selectedCycle, by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 28, height: 36)
                    }
                    Text(BudgetCycle.title(start: selectedCycle))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Button {
                        selectedCycle = BudgetCycle.shift(selectedCycle, by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 28, height: 36)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(.white.opacity(0.15), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Cycle: \(BudgetCycle.title(start: selectedCycle))")
                    .font(.subheadline.weight(.semibold))
                Text("Your month runs from the 26th to the 25th.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.77))
            }
            .foregroundStyle(.white)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [darkBlue, blue.opacity(0.95), darkBlue],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    @ViewBuilder
    private var incomeSummary: some View {
        if sizeClass == .regular {
            HStack(alignment: .top, spacing: 12) {
                incomeCard
                summaryCard
            }
        } else {
            VStack(spacing: 12) {
                incomeCard
                summaryCard
            }
        }
    }

    private var incomeCard: some View {
        card {
            VStack(alignment: .leading, spacing: 13) {
                cardHeading("Monthly Fixed Income", symbol: "wallet.pass.fill", color: green)
                if incomeItems.isEmpty {
                    Text("Add your and Amara's monthly salary to calculate what is available to spend.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 9) {
                        quickIncome("Salary – Zeeshan")
                        quickIncome("Salary – Amara")
                    }
                } else {
                    ForEach(incomeItems) { item in
                        Button {
                            editor = FixedBudgetEditorRequest(kind: .income, item: item)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.fill")
                                    .foregroundStyle(blue)
                                    .font(.title3)
                                Text(item.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Text(currency(item.amount))
                                    .font(.subheadline.bold())
                                    .foregroundStyle(green)
                                    .minimumScaleFactor(0.8)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                HStack {
                    Text("Total Fixed Income")
                    Spacer()
                    Text(currency(totalIncome))
                }
                .font(.subheadline.bold())
                .foregroundStyle(green)
                .padding(12)
                .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                Button {
                    editor = FixedBudgetEditorRequest(kind: .income)
                } label: {
                    Label("Add Fixed Income", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(green.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                }
                .tint(green)
            }
        }
    }

    private func quickIncome(_ name: String) -> some View {
        Button(name) {
            editor = FixedBudgetEditorRequest(kind: .income, suggestedTitle: name)
        }
        .font(.caption.weight(.medium))
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(green.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .buttonStyle(.plain)
    }

    private var summaryCard: some View {
        card {
            VStack(alignment: .leading, spacing: 13) {
                cardHeading("Monthly Summary", symbol: "chart.bar.fill", color: blue)
                summaryRow("Total Fixed Income", value: totalIncome, color: green)
                summaryRow("Total Fixed Expenses", value: totalExpense, color: red)
                Divider()
                Text("Available Balance This Month")
                    .font(.headline)
                Text(currency(available))
                    .font(.system(size: 33, weight: .bold, design: .rounded))
                    .foregroundStyle(available < 0 ? red : blue)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Label(
                    available >= 0
                        ? "After fixed expenses, you have \(currency(available)) to plan."
                        : "Fixed expenses exceed monthly income by \(currency(-available)).",
                    systemImage: available >= 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(available >= 0 ? green : red)
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    (available >= 0 ? green : red).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            }
        }
    }

    private func summaryRow(_ name: String, value: Decimal, color: Color) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(currency(value))
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.subheadline)
    }

    private var expensesCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 8) {
                    cardHeading("Monthly Fixed Expenses", symbol: "receipt.fill", color: red)
                    Spacer(minLength: 4)
                    Button {
                        editor = FixedBudgetEditorRequest(kind: .expense)
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .frame(width: 35, height: 35)
                            .background(blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityLabel("Add Fixed Expense")
                }
                HStack(spacing: 6) {
                    ForEach(FixedExpenseFilter.allCases) { filter in
                        Button {
                            expenseFilter = filter
                        } label: {
                            Text(filter == .short
                                 ? "Short (\(expenseItems.filter { $0.durationCycles != nil }.count))"
                                 : filter == .ongoing
                                    ? "Long (\(expenseItems.filter { $0.durationCycles == nil }.count))"
                                    : "All")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(expenseFilter == filter ? blue : .secondary)
                                .background(
                                    expenseFilter == filter ? blue.opacity(0.10) : Color(uiColor: .tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                if displayedExpenses.isEmpty {
                    Text(expenseItems.isEmpty
                         ? "Add rent, instalments, subscriptions or other preset monthly expenses."
                         : "No expenses in this group for this cycle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                } else {
                    ForEach(displayedExpenses) { item in
                        expenseRow(item)
                        if item.id != displayedExpenses.last?.id { Divider() }
                    }
                }
                HStack {
                    Text("Total Fixed Expenses")
                    Spacer()
                    Text(currency(totalExpense))
                }
                .font(.subheadline.bold())
                .foregroundStyle(red)
                .padding(12)
                .background(red.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
            }
        }
    }

    private func expenseRow(_ item: FixedPlanItem) -> some View {
        Button {
            editor = FixedBudgetEditorRequest(kind: .expense, item: item)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.durationCycles == nil ? "house.fill" : "calendar.badge.clock")
                    .foregroundStyle(item.durationCycles == nil ? green : blue)
                    .frame(width: 35, height: 35)
                    .background(
                        (item.durationCycles == nil ? green : blue).opacity(0.09),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let duration = item.durationCycles, let last = item.finalDay() {
                        Text("Until \(last.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ProgressView(
                            value: Double(min(duration, item.elapsedCycles(through: selectedCycle))),
                            total: Double(duration)
                        )
                        .tint(blue)
                    } else {
                        Label("Ongoing · Every cycle", systemImage: "infinity")
                            .font(.caption2)
                            .foregroundStyle(green)
                    }
                }
                Spacer(minLength: 4)
                Text(currency(item.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }

    private var essentialsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    cardHeading("1-Click Essentials Budget", symbol: "chart.pie.fill", color: blue)
                    Spacer(minLength: 4)
                    Button {
                        grocery = 45
                        fuel = 25
                        eatOut = 15
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                Text("Allocate your available balance (\(currency(allocatable))) across key categories.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                sliderRow("Grocery", symbol: "cart.fill", color: blue, category: .grocery, percent: grocery)
                sliderRow("Fuel", symbol: "fuelpump.fill", color: .purple, category: .fuel, percent: fuel)
                sliderRow("Eat Out", symbol: "fork.knife", color: .orange, category: .eatOut, percent: eatOut)
                HStack(spacing: 8) {
                    Image(systemName: "ellipsis.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                    Text("Other / Unassigned")
                        .font(.subheadline)
                    Spacer()
                    Text("\(otherPercent)%")
                        .font(.subheadline.weight(.semibold))
                    Text(currency(allocatable * Decimal(otherPercent) / 100))
                        .font(.subheadline.weight(.semibold))
                }
                Button {
                    store.applyFixedBudget(
                        grocery: grocery, fuel: fuel, eatOut: eatOut, cycle: selectedCycle
                    )
                    if store.errorMessage == nil { showAppliedConfirmation = true }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Apply Budget Plan")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [darkBlue, blue], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 15)
                    )
                }
                .disabled(allocatable <= 0)
                .opacity(allocatable <= 0 ? 0.55 : 1)
                if store.fixedBudget.savedAllocation(in: selectedCycle) != nil {
                    Label("Budget saved for this cycle", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(green)
                }
            }
        }
    }

    private func sliderRow(
        _ name: String, symbol: String, color: Color,
        category: EssentialsCategory, percent: Int
    ) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 28)
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(percent)%")
                    .font(.subheadline.bold())
                    .foregroundStyle(color)
                Text(currency(allocatable * Decimal(percent) / 100))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Slider(value: percentageBinding(category), in: 0...100, step: 1)
                .tint(color)
                .accessibilityLabel("\(name) percentage")
                .accessibilityValue("\(percent) percent")
        }
    }

    private func percentageBinding(_ category: EssentialsCategory) -> Binding<Double> {
        Binding(
            get: {
                switch category {
                case .grocery: return Double(grocery)
                case .fuel: return Double(fuel)
                case .eatOut: return Double(eatOut)
                }
            },
            set: { newValue in
                let value = max(0, Int(newValue.rounded()))
                switch category {
                case .grocery: grocery = min(value, 100 - fuel - eatOut)
                case .fuel: fuel = min(value, 100 - grocery - eatOut)
                case .eatOut: eatOut = min(value, 100 - grocery - fuel)
                }
            }
        )
    }

    private func loadPercentages() {
        let saved = store.fixedBudget.savedAllocation(in: selectedCycle)
        grocery = saved?.groceryPercent ?? store.fixedBudget.groceryPercent
        fuel = saved?.fuelPercent ?? store.fixedBudget.fuelPercent
        eatOut = saved?.eatOutPercent ?? store.fixedBudget.eatOutPercent
    }

    private func cardHeading(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
            )
            .shadow(color: .black.opacity(0.045), radius: 9, y: 3)
    }
}

private struct FixedPlanEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let kind: FixedPlanKind
    let existingItem: FixedPlanItem?

    @State private var title: String
    @State private var amountText: String
    @State private var firstCycle: Date
    @State private var durationChoice: Int
    @State private var customDuration: Int
    @State private var confirmDelete = false

    init(kind: FixedPlanKind, item: FixedPlanItem?, suggestedTitle: String = "") {
        self.kind = kind
        self.existingItem = item
        _title = State(initialValue: item?.title ?? suggestedTitle)
        _amountText = State(initialValue: item.map {
            NSDecimalNumber(decimal: $0.amount).stringValue
        } ?? "")
        _firstCycle = State(initialValue: item?.firstCycle ?? BudgetCycle.start(containing: Date()))
        let period = item?.durationCycles
        _durationChoice = State(initialValue: period == nil ? -1 : (
            [1, 3, 6, 12].contains(period!) ? period! : 0
        ))
        _customDuration = State(initialValue: max(1, period ?? 2))
    }

    private var amount: Decimal? {
        Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ""))
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (amount ?? 0) > 0 && (durationChoice != 0 || customDuration > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(kind.title) {
                    TextField("Name (e.g. Rent or Salary)", text: $title)
                        .textInputAutocapitalization(.words)
                    HStack {
                        Text(store.currencyCode)
                            .foregroundStyle(.secondary)
                        TextField("Amount per cycle", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Schedule") {
                    DatePicker("First cycle", selection: $firstCycle, displayedComponents: .date)
                    Text("The selected date is assigned to its 26th–25th budget cycle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Period", selection: $durationChoice) {
                        Text("Ongoing / No end date").tag(-1)
                        Text("1 month").tag(1)
                        Text("3 months").tag(3)
                        Text("6 months").tag(6)
                        Text("12 months").tag(12)
                        Text("Custom").tag(0)
                    }
                    if durationChoice == 0 {
                        Stepper("Number of cycles: \(customDuration)",
                                value: $customDuration, in: 1...600)
                    }
                    if durationChoice != -1 {
                        let cycles = durationChoice == 0 ? customDuration : durationChoice
                        let end = BudgetCycle.shift(
                            BudgetCycle.start(containing: firstCycle), by: cycles
                        ).addingTimeInterval(-24 * 60 * 60)
                        LabeledContent("Last active month",
                            value: end.formatted(.dateTime.day().month(.abbreviated).year()))
                    }
                }
                Section {
                    Text("This is a budget forecast. Adding a fixed item will not create a duplicate ledger transaction or payment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if existingItem != nil {
                    Section {
                        Button("Delete Fixed Item", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }
            }
            .navigationTitle(existingItem == nil ? "Add \(kind.title)" : "Edit \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .alert("Delete this fixed item?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let existingItem {
                        store.deleteFixedPlanItem(existingItem.id)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This removes the preset budget item, but will not change existing ledger transactions.")
            }
        }
    }

    private func save() {
        guard let amount, canSave else { return }
        let item = FixedPlanItem(
            id: existingItem?.id ?? UUID(), kind: kind,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            firstCycle: BudgetCycle.start(containing: firstCycle),
            durationCycles: durationChoice == -1 ? nil : (durationChoice == 0 ? customDuration : durationChoice)
        )
        store.saveFixedPlanItem(item)
        if store.errorMessage == nil { dismiss() }
    }
}
