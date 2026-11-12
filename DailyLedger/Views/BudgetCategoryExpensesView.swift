import SwiftUI

/// Transaction-level drill-down from Budget Performance's original category breakdown.
/// Recorded accounting categories and budget allocations are independent controls.
struct BudgetCategoryExpensesView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let recordIDs: Set<UUID>
    let categoryName: String
    let cycleStart: Date

    private var records: [LedgerTransaction] {
        store.transactions.filter { recordIDs.contains($0.id) }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }

    private var activePlans: [FixedPlanItem] {
        store.fixedBudget.activeItems(.expense, in: cycleStart)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.title2)
                            .foregroundStyle(Color.indigo)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(categoryName)
                                .font(.headline)
                            Text("\(records.count) transactions · \(BudgetCycle.title(start: cycleStart))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Changing the recorded category does not change the amount or account. Assigning a fixed installment changes the budget report only.")
                }
                Section {
                    Menu {
                        Button("Unassigned — Review Later") {
                            assignAll(BudgetSpendAssignment(kind: .unassigned))
                        }
                        if !activePlans.isEmpty {
                            Section("Fixed expenses & installments") {
                                ForEach(activePlans) { item in
                                    Button("Fixed · \(item.title)") {
                                        assignAll(BudgetSpendAssignment(kind: .fixed, fixedItemID: item.id))
                                    }
                                }
                            }
                        }
                        Section("Planned allocations") {
                            Button("Grocery") { assignAll(BudgetSpendAssignment(kind: .grocery)) }
                            Button("Fuel") { assignAll(BudgetSpendAssignment(kind: .fuel)) }
                            Button("Eat Out") { assignAll(BudgetSpendAssignment(kind: .eatOut)) }
                            Button("Other Planned Expenses") {
                                assignAll(BudgetSpendAssignment(kind: .other))
                            }
                        }
                    } label: {
                        Label("Assign all \(records.count) expenses to a budget", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(records.isEmpty)
                } footer: {
                    Text("A category-wide assignment can be overridden on any individual expense below.")
                }
                Section("Individual expenses") {
                    ForEach(records) { transaction in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(transaction.vendor?.isEmpty == false
                                         ? transaction.vendor! : transaction.category)
                                        .font(.subheadline.weight(.semibold))
                                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 10)
                                Text(DisplayFormat.currency(transaction.amount,
                                    code: store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode))
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }

                            if transaction.type == .expense {
                                Menu {
                                    ForEach(store.categories(for: .expense).sorted {
                                        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                                    }, id: \.self) { saved in
                                        Button(saved) {
                                            changeRecordedCategory(transaction, to: saved)
                                        }
                                    }
                                } label: {
                                    editableRow(label: "Recorded category",
                                                value: transaction.category,
                                                symbol: "tag")
                                }
                                .accessibilityLabel("Change original category for \(transaction.category)")
                            } else {
                                editableRow(label: "Recorded category",
                                            value: transaction.category,
                                            symbol: "tag")
                            }

                            Menu {
                                Button("Unassigned — Review Later") {
                                    saveAssignment(transaction.id, BudgetSpendAssignment(kind: .unassigned))
                                }
                                Button("Automatic matching") { saveAssignment(transaction.id, nil) }
                                if !activePlans.isEmpty {
                                    Section("Fixed expenses & installments") {
                                        ForEach(activePlans) { fixed in
                                            Button("\(fixed.title) · \(fixed.amount.formatted())") {
                                                saveAssignment(transaction.id,
                                                    BudgetSpendAssignment(kind: .fixed, fixedItemID: fixed.id))
                                            }
                                        }
                                    }
                                }
                                Section("Planned variable allocations") {
                                    Button("Grocery") { saveAssignment(transaction.id, BudgetSpendAssignment(kind: .grocery)) }
                                    Button("Fuel") { saveAssignment(transaction.id, BudgetSpendAssignment(kind: .fuel)) }
                                    Button("Eat Out") { saveAssignment(transaction.id, BudgetSpendAssignment(kind: .eatOut)) }
                                    Button("Other Planned Expenses") { saveAssignment(transaction.id, BudgetSpendAssignment(kind: .other)) }
                                }
                                Button("Outside Budget") { saveAssignment(transaction.id, BudgetSpendAssignment(kind: .outside)) }
                            } label: {
                                editableRow(label: "Budget assignment",
                                            value: assignmentTitle(for: transaction.id),
                                            symbol: "chart.pie")
                            }
                            .accessibilityLabel("Change budget assignment")
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Category Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Color.indigo)
    }

    private func editableRow(label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(Color.indigo)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private func assignmentTitle(for id: UUID) -> String {
        guard let saved = store.fixedBudget.spendAssignments[id] else { return "Automatic matching" }
        switch saved.kind {
        case .unassigned: return "Unassigned — Review Later"
        case .fixed:
            return "Fixed · " + (store.fixedBudget.items.first { $0.id == saved.fixedItemID }?.title ?? "Inactive plan")
        case .grocery: return "Grocery"
        case .fuel: return "Fuel"
        case .eatOut: return "Eat Out"
        case .other: return "Other Planned Expenses"
        case .outside: return "Outside Budget"
        }
    }

    private func assignAll(_ assignment: BudgetSpendAssignment) {
        guard !records.isEmpty else { return }
        var plan = store.fixedBudget
        for item in records { plan.spendAssignments[item.id] = assignment }
        store.saveFixedBudget(plan) // One atomic write, not one write per expense.
    }

    private func saveAssignment(_ id: UUID, _ assignment: BudgetSpendAssignment?) {
        var plan = store.fixedBudget
        plan.spendAssignments[id] = assignment
        store.saveFixedBudget(plan)
    }

    private func changeRecordedCategory(_ transaction: LedgerTransaction, to category: String) {
        guard transaction.type == .expense && transaction.category != category else { return }
        var corrected = transaction
        corrected.category = category
        _ = store.update(corrected) // Recalculates account reports; budget mapping is preserved.
    }
}
