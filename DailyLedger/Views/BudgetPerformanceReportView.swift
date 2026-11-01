import SwiftUI

/// A separate report. The approved Budget tab is intentionally unchanged.
struct BudgetPerformanceReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var cycleStart = BudgetCycle.start(containing: Date())
    @State private var showAllTransactions = false
    @State private var showAssignedTransactions = false

    private var activeExpenses: [FixedPlanItem] {
        store.fixedBudget.activeItems(.expense, in: cycleStart)
    }

    private var result: BudgetPerformanceResult {
        let currencies = Dictionary(uniqueKeysWithValues: store.accounts.map {
            ($0.id, $0.currencyCode)
        })
        let defaultCurrency = currencies[store.defaultAccountID ?? LedgerAccount.legacyMainID]
            ?? store.currencyCode
        let accountLookup = Dictionary(uniqueKeysWithValues: store.accounts.map {
            ($0.id, $0)
        })
        let transactions = store.transactions
            .compactMap { transaction -> BudgetSpendRecord? in
                let source = transaction.accountID.flatMap { accountLookup[$0] }
                let destination = transaction.destinationAccountID.flatMap { accountLookup[$0] }
                let sourceIsBank = source?.nature == .bank ||
                    (source?.nature == nil && (source?.group == .qatar || source?.group == .pakistan))
                guard BudgetPerformanceEngine.includesInSpending(
                    isExpense: transaction.type == .expense,
                    isTransfer: transaction.type == .transfer,
                    sourceIsBank: sourceIsBank,
                    sourceIsPayments: source?.group == .payments,
                    destinationIsPayments: destination?.group == .payments
                ) else { return nil }
                // Report using the source account currency, without guessed FX.
                BudgetSpendRecord(
                    id: transaction.id,
                    amount: transaction.amount,
                    date: transaction.date,
                    category: transaction.category,
                    vendor: transaction.vendor,
                    currencyCode: transaction.accountID.flatMap { currencies[$0] } ?? defaultCurrency
                )
            }
        return BudgetPerformanceEngine.build(
            plan: store.fixedBudget, cycleStart: cycleStart,
            expenses: transactions, currencyCode: store.currencyCode
        )
    }

    var body: some View {
        let summary = result
        List {
            Section {
                HStack {
                    Button {
                        cycleStart = BudgetCycle.shifted(cycleStart, by: -1)
                        showAllTransactions = false
                        showAssignedTransactions = false
                    } label: { Image(systemName: "chevron.left").frame(minWidth: 38, minHeight: 42) }
                    .accessibilityLabel("Previous budget cycle")
                    Spacer()
                    VStack(spacing: 4) {
                        Text(BudgetCycle.title(start: cycleStart))
                            .font(.headline)
                        Text("26th to 25th · \(store.currencyCode)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        cycleStart = BudgetCycle.shifted(cycleStart, by: 1)
                        showAllTransactions = false
                        showAssignedTransactions = false
                    } label: { Image(systemName: "chevron.right").frame(minWidth: 38, minHeight: 42) }
                    .accessibilityLabel("Next budget cycle")
                }
                .buttonStyle(.borderless)
                if !summary.usesSavedAllocations {
                    Label("Essentials allocations for this cycle are not yet applied. Showing current allocation percentages as a preview.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Salary-month cycle")
            }

            Section("Budget vs Actual") {
                VStack(alignment: .leading, spacing: 10) {
                    metricRow("Planned expenses", amount(summary.totalBudget))
                    metricRow("Paid within budget", amount(summary.budgetSpent))
                    ProgressView(value: min(1, max(0, summary.achievedPercentage / 100)))
                        .tint(.purple)
                    HStack {
                        Text("Budget used")
                        Spacer()
                        Text(percent(summary.achievedPercentage)).bold()
                    }
                    HStack {
                        Text("Remaining budget")
                        Spacer()
                        Text(amount(summary.remaining)).bold()
                    }
                    HStack {
                        Text("Remaining percentage")
                        Spacer()
                        Text(percent(summary.remainingPercentage)).bold()
                            .foregroundStyle(.green)
                    }
                    if summary.overBudget > 0 {
                        metricRow("Over budget", amount(summary.overBudget))
                            .foregroundStyle(.red)
                    }
                    Divider()
                    metricRow("Outside-budget spending", amount(summary.outsideSpent))
                    metricRow("Total recorded spending", amount(summary.actualSpent))
                }
                .padding(.vertical, 7)
                if summary.totalBudget == 0 {
                    Label("No planned budget is available for this cycle. Recorded expenses appear outside budget until you create a plan.", systemImage: "info.circle")
                        .font(.caption)
                }
            }

            Section {
                ForEach(summary.lines.filter { $0.id.hasPrefix("fixed:") }) { item in
                    budgetLine(item)
                }
                if activeExpenses.isEmpty {
                    Text("No fixed expense plans are active in this cycle.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Fixed Expenses — Paid vs Planned")
            } footer: {
                Text("A fixed expense counts as paid when an expense transaction has an exact matching category or you explicitly assign it below. Planned recurring bills are not assumed to be paid.")
            }

            Section("Essentials & Allocations") {
                ForEach(summary.lines.filter { !$0.id.hasPrefix("fixed:") }) { item in
                    budgetLine(item)
                }
            }

            Section {
                if summary.outsideExpenses.isEmpty {
                    Label("No outside-budget expenses in this cycle.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                } else {
                    metricRow("Unplanned / outside", amount(summary.outsideSpent))
                    let pendingOutside = summary.outsideExpenses.filter { !$0.matchedManually }
                    ForEach(pendingOutside.prefix(40)) { expense in
                        expenseRow(expense)
                    }
                    if pendingOutside.isEmpty {
                        Text("All outside-budget expenses have been reviewed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if pendingOutside.count > 40 {
                        Text("Showing 40 of \(pendingOutside.count) unassigned outside-budget transactions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Outside Budget")
            } footer: {
                Text("Ordinary unmatched spending goes to Other / Unassigned when an Other budget is available. Zero-allocation expenses remain outside budget.")
            }

            Section {
                let pending = summary.unassignedExpenses
                let rows = showAllTransactions ? pending : Array(pending.prefix(45))
                if rows.isEmpty {
                    Label("All expenses reviewed for this cycle.", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { expense in
                    expenseRow(expense)
                }
                if !showAllTransactions && pending.count > 45 {
                    Button("Show all \(pending.count) unassigned expenses") {
                        showAllTransactions = true
                    }
                }
                if !summary.assignedExpenses.isEmpty {
                    DisclosureGroup(isExpanded: $showAssignedTransactions) {
                        ForEach(summary.assignedExpenses) { expense in
                            expenseRow(expense)
                        }
                    } label: {
                        Label("Assigned expenses (\(summary.assignedExpenses.count))", systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
            } header: {
                Text("Unassigned Expenses — Assign to Budget")
            } footer: {
                Text("Assigned expenses disappear from the unassigned list. Bank-to-bank transfers are excluded; bank-to-Payments transfers count as spending. Assignments are saved without changing the transaction.")
            }

            if !summary.unconvertedByCurrency.isEmpty {
                Section {
                    ForEach(summary.unconvertedByCurrency.keys.sorted(), id: \.self) { currency in
                        metricRow("Excluded \(currency)", summary.unconvertedByCurrency[currency]?
                            .formatted() ?? "0")
                    }
                } header: {
                    Text("Other-Currency Expenses")
                } footer: {
                    Text("Other account currencies are excluded rather than applying an invented exchange rate. Select a common currency in the ledger if you want a comparable budget.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Budget Performance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func budgetLine(_ item: BudgetPerformanceLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(percent(item.spentPercentage)).font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.overBudget > 0 ? Color.red : Color.primary)
            }
            HStack {
                Text("Paid \(amount(item.spent))")
                Spacer()
                Text("Plan \(amount(item.budget))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, item.spentPercentage / 100)))
                .tint(item.overBudget > 0 ? .red : .purple)
            HStack {
                Text(item.overBudget > 0 ? "Over by \(amount(item.overBudget))" : "Remaining \(amount(item.remaining))")
                    .font(.caption)
                    .foregroundStyle(item.overBudget > 0 ? Color.red : Color.secondary)
                Spacer()
            }
        }
        .padding(.vertical, 5)
    }

    private func expenseRow(_ expense: BudgetPerformanceExpense) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.record.vendor?.isEmpty == false
                         ? expense.record.vendor! : expense.record.category)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    Text("\(expense.record.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.record.category)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(amount(expense.record.amount))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack {
                Text(bucketTitle(expense.bucket))
                    .font(.caption)
                    .foregroundStyle(expense.bucket == .outside ? Color.red : Color.secondary)
                if expense.matchedManually {
                    Text("Manual").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Automatic matching") { setAssignment(expense.id, nil) }
                    ForEach(activeExpenses) { fixed in
                        Button("Fixed: \(fixed.title) · \(amount(fixed.amount))") {
                            setAssignment(expense.id, BudgetSpendAssignment(kind: .fixed, fixedItemID: fixed.id))
                        }
                    }
                    Button("Grocery") { setAssignment(expense.id, BudgetSpendAssignment(kind: .grocery)) }
                    Button("Fuel") { setAssignment(expense.id, BudgetSpendAssignment(kind: .fuel)) }
                    Button("Eat Out") { setAssignment(expense.id, BudgetSpendAssignment(kind: .eatOut)) }
                    Button("Other Allocation") { setAssignment(expense.id, BudgetSpendAssignment(kind: .other)) }
                    Button("Outside Budget") { setAssignment(expense.id, BudgetSpendAssignment(kind: .outside)) }
                } label: {
                    Label(expense.matchedManually ? "Change" : "Assign", systemImage: "tag")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func setAssignment(_ id: UUID, _ classification: BudgetSpendAssignment?) {
        var next = store.fixedBudget
        next.spendAssignments[id] = classification
        store.saveFixedBudget(next)
    }

    private func bucketTitle(_ bucket: BudgetPerformanceBucket) -> String {
        switch bucket {
        case .fixed(let id):
            return "Fixed · " + (activeExpenses.first(where: { $0.id == id })?.title ?? "Inactive")
        case .grocery: return "Grocery"
        case .fuel: return "Fuel"
        case .eatOut: return "Eat Out"
        case .other: return "Other / Unassigned"
        case .outside: return "Outside Budget"
        }
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private func amount(_ value: Decimal) -> String {
        "\(store.currencyCode) \(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
}
