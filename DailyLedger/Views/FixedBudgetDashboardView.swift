import SwiftUI
import UIKit

// Match the app's System / Light / Black appearance selection, including
// live iOS light/dark changes. Semantic colors avoid a hard-coded white UI.
private enum LedgerBudgetStyle {
    static let navy = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.96, blue: 1, alpha: 1)
            : UIColor(red: 0.052, green: 0.115, blue: 0.275, alpha: 1)
    })
    static let blue = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.53, green: 0.62, blue: 1, alpha: 1)
            : UIColor(red: 0.21, green: 0.26, blue: 0.94, alpha: 1)
    })
    static let violet = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.70, green: 0.57, blue: 1, alpha: 1)
            : UIColor(red: 0.37, green: 0.28, blue: 0.98, alpha: 1)
    })
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let green = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.88, blue: 0.62, alpha: 1)
            : UIColor(red: 0, green: 0.60, blue: 0.37, alpha: 1)
    })
    static let red = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.45, blue: 0.54, alpha: 1)
            : UIColor(red: 0.80, green: 0.12, blue: 0.24, alpha: 1)
    })
    static let muted = Color(uiColor: .secondaryLabel)
}

private extension View {
    func budgetCard() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LedgerBudgetStyle.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LedgerBudgetStyle.blue.opacity(0.035), lineWidth: 1)
            }
            .shadow(color: LedgerBudgetStyle.navy.opacity(0.055), radius: 14, y: 6)
    }
}

private struct BudgetCircle: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 35

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.11), in: Circle())
    }
}

/// Designed from the user-approved Next Ledger screenshot, not from Form/List defaults.
struct FixedBudgetDashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayedCycle = BudgetCycle.start(containing: Date())
    @State private var grocery = 45.0
    @State private var fuel = 25.0
    @State private var eatOut = 15.0
    @State private var filter = 0 // 0 all, 1 limited, 2 ongoing
    @State private var addingKind: FixedPlanKind = .expense
    @State private var adding = false
    @State private var editing: FixedPlanItem?
    @State private var showBudgetNotice = false
    @State private var appliedNotice = false

    private var plan: MonthlyFixedBudget { store.fixedBudget }
    private var income: Decimal { plan.total(.income, in: displayedCycle) }
    private var expenses: Decimal { plan.total(.expense, in: displayedCycle) }
    private var available: Decimal { income - expenses }
    private var currency: String { store.currencyCode }
    private var safeAvailable: Decimal { max(Decimal.zero, available) }
    private var allocated: Int { Int(grocery + fuel + eatOut) }
    private var validAllocations: Bool { allocated <= 100 }
    private var incomes: [FixedPlanItem] { plan.activeItems(.income, in: displayedCycle) }
    private var shortExpenses: [FixedPlanItem] {
        plan.activeItems(.expense, in: displayedCycle).filter { $0.durationCycles != nil }
    }
    private var longExpenses: [FixedPlanItem] {
        plan.activeItems(.expense, in: displayedCycle).filter { $0.durationCycles == nil }
    }
    private var visibleExpenses: [FixedPlanItem] {
        switch filter {
        case 1: return shortExpenses
        case 2: return longExpenses
        default: return shortExpenses + longExpenses
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                heading
                cycleHero
                HStack(alignment: .top, spacing: 10) {
                    fixedIncomeCard
                    summaryCard
                }
                expenseCard
                essentialsCard
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .background(LedgerBudgetStyle.canvas.ignoresSafeArea())
        .foregroundStyle(LedgerBudgetStyle.navy)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $adding) {
            NavigationStack {
                FixedPlanItemEditor(kind: addingKind, item: nil, currency: currency) { value in
                    save(value)
                }
            }
        }
        .sheet(item: $editing) { item in
            NavigationStack {
                FixedPlanItemEditor(kind: item.kind, item: item, currency: currency) { value in
                    save(value)
                }
            }
        }
        .alert("Budget Overview", isPresented: $showBudgetNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Current salary-month: \(BudgetCycle.title(start: displayedCycle)). Active income: \(money(income)). Fixed expenses: \(money(expenses)).")
        }
        .alert("Budget Plan Saved", isPresented: $appliedNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Grocery, Fuel and Eat Out allocations were saved for \(BudgetCycle.title(start: displayedCycle)).")
        }
        .onAppear(perform: loadAllocations)
        .onChange(of: displayedCycle) { _ in loadAllocations() }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                (
                    Text("Next ").foregroundColor(LedgerBudgetStyle.navy) +
                    Text("Ledger").foregroundColor(LedgerBudgetStyle.blue)
                )
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.8)
                Text("Plan Today. A Better Tomorrow.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(LedgerBudgetStyle.muted)
            }
            Spacer(minLength: 4)
            Button { showBudgetNotice = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(LedgerBudgetStyle.navy)
                        .frame(width: 39, height: 39)
                        .background(LedgerBudgetStyle.surface, in: Circle())
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                        .offset(x: -5, y: 3)
                }
            }
            .accessibilityLabel("Budget overview")
            Text("Z")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 39, height: 39)
                .background(
                    LinearGradient(colors: [Color(red: 0.31, green: 0.52, blue: 0.77),
                                            Color(red: 0.23, green: 0.36, blue: 0.58)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
        }
        .padding(.horizontal, 3)
    }

    private var cycleHero: some View {
        HStack(spacing: 11) {
            Image(systemName: "calendar")
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(Color(red: 0.33, green: 0.96, blue: 0.70))
            VStack(alignment: .leading, spacing: 5) {
                Text("Monthly Budget")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                Text("Cycle: \(BudgetCycle.title(start: displayedCycle))")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                Text("Your month runs from the 26th to the 25th.")
                    .font(.system(size: 10.3))
                    .foregroundStyle(.white.opacity(0.70))
            }
            Spacer(minLength: 1)
            HStack(spacing: 6) {
                Button {
                    displayedCycle = BudgetCycle.shifted(displayedCycle, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 19, height: 40)
                }
                Text(BudgetCycle.title(start: displayedCycle))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Button {
                    displayedCycle = BudgetCycle.shifted(displayedCycle, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 19, height: 40)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .stroke(.white.opacity(0.25), lineWidth: 0.8))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.21, green: 0.29, blue: 0.65),
                                   Color(red: 0.16, green: 0.23, blue: 0.59)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 19, style: .continuous)
        )
    }

    private var fixedIncomeCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            cardTitle("Monthly Fixed Income", icon: "wallet.pass.fill", color: LedgerBudgetStyle.green)
            if incomes.isEmpty {
                Text("Add your fixed salary or monthly income")
                    .font(.system(size: 11))
                    .foregroundStyle(LedgerBudgetStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 67, alignment: .leading)
            }
            ForEach(incomes) { item in
                Button { editing = item } label: {
                    HStack(spacing: 5) {
                        BudgetCircle(symbol: "person.fill", color: LedgerBudgetStyle.blue, size: 25)
                        Text(item.title).font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(money(item.amount))
                            .font(.system(size: 10.2, weight: .bold))
                            .foregroundStyle(LedgerBudgetStyle.green)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                if item.id != incomes.last?.id {
                    Divider().overlay(LedgerBudgetStyle.canvas)
                }
            }
            HStack {
                Text("Total Fixed Income")
                    .font(.system(size: 11.5, weight: .bold))
                Spacer(minLength: 0)
                Text(money(income))
                    .font(.system(size: 12.2, weight: .bold))
            }
            .foregroundStyle(LedgerBudgetStyle.green)
            .padding(9)
            .background(LedgerBudgetStyle.green.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            Button {
                addingKind = .income
                adding = true
            } label: {
                Label("Add Fixed Income", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .foregroundStyle(LedgerBudgetStyle.green)
                    .background(LedgerBudgetStyle.green.opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
        }
        .budgetCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Monthly Summary", icon: "chart.bar.fill", color: LedgerBudgetStyle.blue)
            HStack {
                Text("Total Fixed Income")
                Spacer(minLength: 0)
                Text(money(income)).foregroundStyle(LedgerBudgetStyle.green).bold()
            }
            .font(.system(size: 10.5))
            HStack {
                Text("Total Fixed Expenses")
                Spacer(minLength: 0)
                Text(money(expenses)).foregroundStyle(LedgerBudgetStyle.red).bold()
            }
            .font(.system(size: 10.5))
            Rectangle()
                .fill(LedgerBudgetStyle.canvas)
                .frame(height: 1)
            Text("Available Balance This Month")
                .font(.system(size: 13, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(money(available))
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(LedgerBudgetStyle.blue)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(LedgerBudgetStyle.green)
                Text("After fixed expenses, you have \(money(available)) to plan for this month.")
                    .foregroundStyle(LedgerBudgetStyle.green)
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LedgerBudgetStyle.green.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
        }
        .budgetCard()
    }

    private var expenseCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                cardTitle("Monthly Fixed Expenses", icon: "receipt.fill",
                          color: Color(red: 0.88, green: 0.33, blue: 0.39))
                Spacer(minLength: 3)
                Button {
                    addingKind = .expense
                    adding = true
                } label: {
                    Label("Add Fixed Expense", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LedgerBudgetStyle.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(LedgerBudgetStyle.blue.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 4) {
                filterButton("All (\(shortExpenses.count + longExpenses.count))", value: 0)
                filterButton("Short Term (\(shortExpenses.count))", value: 1)
                filterButton("Long Term (\(longExpenses.count))", value: 2)
            }
            if visibleExpenses.isEmpty {
                Text("No fixed expenses for this cycle. Tap Add Fixed Expense to get started.")
                    .font(.system(size: 12))
                    .foregroundStyle(LedgerBudgetStyle.muted)
                    .frame(maxWidth: .infinity, minHeight: 65, alignment: .leading)
            }
            ForEach(visibleExpenses) { item in
                Button { editing = item } label: {
                    expenseRow(item)
                }
                .buttonStyle(.plain)
                if item.id != visibleExpenses.last?.id {
                    Divider().overlay(LedgerBudgetStyle.canvas)
                }
            }
            HStack {
                Text("Total Fixed Expenses")
                Spacer()
                Text(money(expenses))
            }
            .font(.system(size: 12.5, weight: .bold))
            .foregroundStyle(LedgerBudgetStyle.red)
            .padding(12)
            .background(LedgerBudgetStyle.red.opacity(0.075),
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .budgetCard()
    }

    private func expenseRow(_ item: FixedPlanItem) -> some View {
        HStack(spacing: 8) {
            BudgetCircle(symbol: expenseSymbol(item.title),
                         color: expenseColor(item.title),
                         size: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .bold))
                    .lineLimit(1)
                if let count = item.durationCycles {
                    Text("\(item.elapsedCycles(through: displayedCycle)) / \(count) months")
                        .font(.system(size: 9.5))
                        .foregroundStyle(LedgerBudgetStyle.muted)
                } else {
                    Text("Long term · recurring monthly")
                        .font(.system(size: 9.5))
                        .foregroundStyle(LedgerBudgetStyle.muted)
                }
            }
            Spacer(minLength: 3)
            Text(money(item.amount))
                .font(.system(size: 11.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.74)
            if let count = item.durationCycles {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: min(1, Double(item.elapsedCycles(through: displayedCycle)) / Double(max(count, 1))))
                        .tint(LedgerBudgetStyle.blue)
                        .frame(width: 38)
                    Text("\(item.elapsedCycles(through: displayedCycle))/\(count)")
                        .font(.system(size: 8.5))
                        .foregroundStyle(LedgerBudgetStyle.muted)
                }
            } else {
                Image(systemName: "infinity")
                    .foregroundStyle(LedgerBudgetStyle.green)
                    .font(.system(size: 14, weight: .bold))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(LedgerBudgetStyle.muted)
        }
        .padding(.vertical, 6)
    }

    private var essentialsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 9) {
                BudgetCircle(symbol: "chart.pie.fill",
                             color: LedgerBudgetStyle.blue, size: 39)
                VStack(alignment: .leading, spacing: 3) {
                    Text("1-Click Essentials Budget")
                        .font(.system(size: 15.5, weight: .bold))
                    Text("Allocate your available balance (\(money(available))) across key categories.")
                        .font(.system(size: 10.3))
                        .foregroundStyle(LedgerBudgetStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    grocery = 45
                    fuel = 25
                    eatOut = 15
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                            LedgerBudgetStyle.muted.opacity(0.22)))
                }
                .buttonStyle(.plain)
            }
            sliderRow("Grocery", symbol: "cart.fill", color: LedgerBudgetStyle.blue, value: $grocery)
            sliderRow("Fuel", symbol: "fuelpump.fill", color: LedgerBudgetStyle.violet, value: $fuel)
            sliderRow("Eat Out", symbol: "fork.knife", color: Color(red: 1, green: 0.48, blue: 0.13),
                      value: $eatOut)
            HStack(spacing: 8) {
                BudgetCircle(symbol: "ellipsis", color: LedgerBudgetStyle.muted, size: 30)
                Text("Other / Unassigned")
                    .font(.system(size: 11))
                Spacer(minLength: 3)
                Text("\(max(0, 100 - allocated))%")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LedgerBudgetStyle.muted)
                Text(money(safeAvailable * Decimal(max(0, 100 - allocated)) / 100))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LedgerBudgetStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if !validAllocations {
                Label("Allocation percentages exceed 100%. Reduce a slider.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(LedgerBudgetStyle.red)
            }
            Button {
                guard validAllocations, available > 0 else { return }
                var updated = plan
                updated.setAllocation(grocery: Int(grocery), fuel: Int(fuel),
                                      eatOut: Int(eatOut), cycle: displayedCycle)
                store.saveFixedBudget(updated)
                appliedNotice = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                    Text("Apply Budget Plan")
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 47)
                .background(
                    LinearGradient(colors: [LedgerBudgetStyle.blue,
                                            Color(red: 0.30, green: 0.39, blue: 0.99)],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .shadow(color: LedgerBudgetStyle.blue.opacity(0.2), radius: 7, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(!validAllocations || available <= 0)
            .opacity(validAllocations && available > 0 ? 1 : 0.55)
        }
        .budgetCard()
    }

    private func sliderRow(_ title: String, symbol: String, color: Color,
                           value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            BudgetCircle(symbol: symbol, color: color, size: 30)
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 48, alignment: .leading)
            Text("\(Int(value.wrappedValue))%")
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 36, alignment: .trailing)
            Slider(value: value, in: 0...100, step: 5)
                .tint(color)
                .controlSize(.mini)
                .frame(minWidth: 48)
            Text(money(safeAvailable * Decimal(Int(value.wrappedValue)) / 100))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LedgerBudgetStyle.blue)
                .frame(minWidth: 68, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 2)
    }

    private func filterButton(_ title: String, value: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                filter = value
            }
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .foregroundStyle(filter == value ? LedgerBudgetStyle.blue : LedgerBudgetStyle.muted)
                .background(filter == value ? LedgerBudgetStyle.blue.opacity(0.12)
                                            : LedgerBudgetStyle.canvas,
                            in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func cardTitle(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(.system(size: 12.1, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func expenseSymbol(_ title: String) -> String {
        let v = title.lowercased()
        if v.contains("school") || v.contains("education") { return "graduationcap.fill" }
        if v.contains("car") || v.contains("auto") { return "car.fill" }
        if v.contains("rent") || v.contains("house") { return "house.fill" }
        if v.contains("internet") || v.contains("wifi") { return "wifi" }
        if v.contains("phone") || v.contains("mobile") { return "iphone" }
        if v.contains("fuel") { return "fuelpump.fill" }
        return "receipt.fill"
    }

    private func expenseColor(_ title: String) -> Color {
        let v = title.lowercased()
        if v.contains("school") { return LedgerBudgetStyle.blue }
        if v.contains("car") { return LedgerBudgetStyle.red }
        if v.contains("rent") { return LedgerBudgetStyle.green }
        if v.contains("phone") { return LedgerBudgetStyle.blue }
        return LedgerBudgetStyle.violet
    }

    private func money(_ amount: Decimal) -> String {
        DisplayFormat.currency(amount, code: currency)
    }

    private func loadAllocations() {
        let saved = plan.savedAllocation(in: displayedCycle)
        grocery = Double(saved?.groceryPercent ?? plan.groceryPercent)
        fuel = Double(saved?.fuelPercent ?? plan.fuelPercent)
        eatOut = Double(saved?.eatOutPercent ?? plan.eatOutPercent)
    }

    private func save(_ item: FixedPlanItem) {
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
            Section {
                Toggle("Limited number of months", isOn: $isLimited)
                if isLimited {
                    Stepper("\(duration) monthly cycles", value: $duration, in: 1...120)
                } else {
                    Label("Ongoing each month", systemImage: "repeat")
                }
            } header: {
                Text("Recurrence")
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
