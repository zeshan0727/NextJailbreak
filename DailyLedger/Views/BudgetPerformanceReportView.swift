import SwiftUI
import UIKit

// Report-only design tokens. The established Monthly Budget screen is unchanged.
// System surfaces and text remain legible in Light, Dark and Black appearances.
private enum PerformanceStyle {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let primary = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let indigo = Color(red: 0.38, green: 0.40, blue: 0.94)
    static let mint = Color(red: 0.17, green: 0.75, blue: 0.59)
    static let coral = Color(red: 0.92, green: 0.34, blue: 0.40)
    static let amber = Color(red: 0.92, green: 0.61, blue: 0.22)
}

private enum PerformancePage: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case breakdown = "Breakdown"
    case review = "Review"
    var id: String { rawValue }
}

/// Purely visual redesign of Reports > Budget Performance. Financial logic,
/// original category snapshots, assignment persistence and transfers remain
/// delegated to the existing BudgetPerformanceEngine and LedgerStore.
struct BudgetPerformanceReportView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var cycleStart = BudgetCycle.start(containing: Date())
    @State private var selectedPage: PerformancePage = .overview
    @State private var showAllTransactions = false
    @State private var showAssignedTransactions = false
    @State private var showOtherCategoryBreakdown = true

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
                let isPaymentTransfer = transaction.type == .transfer
                let paymentName = destination?.name
                return BudgetSpendRecord(
                    id: transaction.id,
                    amount: transaction.amount,
                    date: transaction.date,
                    category: transaction.category,
                    vendor: isPaymentTransfer ? "Bank → Payments · \(paymentName ?? "Payment")" : transaction.vendor,
                    currencyCode: transaction.accountID.flatMap { currencies[$0] } ?? defaultCurrency,
                    fixedMatchHint: isPaymentTransfer ? paymentName : nil
                )
            }
        return BudgetPerformanceEngine.build(
            plan: store.fixedBudget, cycleStart: cycleStart,
            expenses: transactions, currencyCode: store.currencyCode
        )
    }

    var body: some View {
        let summary = result
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 17) {
                cyclePicker
                if !summary.usesSavedAllocations {
                    Label("Allocations for this cycle are not saved. Current percentages are shown as a preview.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(PerformanceStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(PerformanceStyle.indigo.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                Picker("Report section", selection: $selectedPage) {
                    ForEach(PerformancePage.allCases) { page in
                        Text(page.rawValue).tag(page)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Budget Performance sections")

                switch selectedPage {
                case .overview:
                    overview(summary)
                case .breakdown:
                    breakdown(summary)
                case .review:
                    review(summary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(PerformanceStyle.background.ignoresSafeArea())
        .navigationTitle("Budget Performance")
        .navigationBarTitleDisplayMode(.inline)
        .tint(PerformanceStyle.indigo)
    }

    // MARK: - Cycle navigation

    private var cyclePicker: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR MONTHLY REPORT")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.6)
                    .foregroundStyle(PerformanceStyle.indigo)
                Text(BudgetCycle.title(start: cycleStart))
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(PerformanceStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("26th – 25th · \(store.currencyCode)")
                    .font(.caption)
                    .foregroundStyle(PerformanceStyle.secondary)
            }
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                cycleButton("chevron.left", offset: -1, label: "Previous budget cycle")
                cycleButton("chevron.right", offset: 1, label: "Next budget cycle")
            }
        }
        .padding(.vertical, 4)
    }

    private func cycleButton(_ icon: String, offset: Int, label: String) -> some View {
        Button {
            cycleStart = BudgetCycle.shifted(cycleStart, by: offset)
            showAllTransactions = false
            showAssignedTransactions = false
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(PerformanceStyle.primary)
                .frame(width: 39, height: 39)
                .background(PerformanceStyle.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Overview

    @ViewBuilder
    private func overview(_ summary: BudgetPerformanceResult) -> some View {
        hero(summary)

        HStack(spacing: 11) {
            statisticTile("Paid in budget", value: amount(summary.budgetSpent),
                          symbol: "checkmark.circle.fill", color: PerformanceStyle.indigo)
            statisticTile("Outside budget", value: amount(summary.outsideSpent),
                          symbol: "exclamationmark.circle.fill",
                          color: summary.outsideSpent > 0 ? PerformanceStyle.coral : PerformanceStyle.mint)
        }
        HStack(spacing: 11) {
            statisticTile("Planned", value: amount(summary.totalBudget),
                          symbol: "calendar", color: PerformanceStyle.indigo)
            statisticTile("Total paid", value: amount(summary.actualSpent),
                          symbol: "creditcard.fill", color: PerformanceStyle.amber)
        }

        sectionHeading("Spending at a glance", subtitle: "Your flexible monthly allocations",
                       symbol: "chart.bar.xaxis")
        reportCard {
            let variables = summary.lines.filter { !$0.id.hasPrefix("fixed:") }
            if variables.isEmpty {
                emptyMessage("No flexible allocations for this cycle.")
            } else {
                ForEach(variables) { line in
                    compactAllocationLine(line)
                    if line.id != variables.last?.id {
                        Divider().padding(.vertical, 5)
                    }
                }
            }
        }
        Button {
            selectedPage = .breakdown
        } label: {
            HStack {
                Label("View detailed breakdown", systemImage: "square.grid.2x2")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(PerformanceStyle.indigo)
            .padding(.horizontal, 5)
        }
        .buttonStyle(.plain)

        if summary.totalBudget == 0 {
            reportCard {
                Label("No budget is planned for this cycle. Paid expenses remain visible as outside-budget activity.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(PerformanceStyle.secondary)
            }
        }
    }

    private func hero(_ summary: BudgetPerformanceResult) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "wallet.pass")
                        Text("REMAINING BUDGET").tracking(0.9)
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.78))
                    Text(amount(summary.remaining))
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(summary.overBudget > 0 ? "Budget exceeded" : "Available within your plan")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.74))
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(1, max(0, summary.achievedPercentage / 100))))
                        .stroke(Color(red: 0.68, green: 0.94, blue: 0.83),
                                style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text(percent(summary.achievedPercentage))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("used")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.77))
                    }
                    .foregroundStyle(.white)
                }
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Budget used \(percent(summary.achievedPercentage))")
            }
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
            HStack(spacing: 10) {
                heroMetric("Remaining", percent(summary.remainingPercentage))
                Spacer(minLength: 6)
                heroMetric("Budget used", percent(summary.achievedPercentage))
                Spacer(minLength: 6)
                heroMetric("Over plan", amount(summary.overBudget))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.18, blue: 0.43),
                         Color(red: 0.33, green: 0.29, blue: 0.78)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 25, style: .continuous)
        )
        .shadow(color: PerformanceStyle.indigo.opacity(0.14), radius: 17, y: 7)
    }

    private func heroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func statisticTile(_ title: String, value: String,
                               symbol: String, color: Color) -> some View {
        reportCard {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(PerformanceStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.system(size: 11, weight: .medium))
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(PerformanceStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.63)
                .padding(.top, 4)
        }
    }

    private func compactAllocationLine(_ line: BudgetPerformanceLine) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(line.title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text("\(amount(line.spent)) / \(amount(line.budget))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PerformanceStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            ProgressView(value: min(1, max(0, line.spentPercentage / 100)))
                .tint(line.overBudget > 0 ? PerformanceStyle.coral : PerformanceStyle.indigo)
        }
        .padding(.vertical, 5)
    }

    // MARK: - Breakdown

    @ViewBuilder
    private func breakdown(_ summary: BudgetPerformanceResult) -> some View {
        let fixedLines = summary.lines.filter { $0.id.hasPrefix("fixed:") }
        sectionHeading("Fixed expenses", subtitle: "Paid against recurring commitments",
                       symbol: "calendar.badge.clock")
        reportCard {
            if fixedLines.isEmpty {
                emptyMessage("No fixed expenses are active in this cycle.")
            } else {
                ForEach(fixedLines) { line in
                    budgetLine(line)
                    if line.id != fixedLines.last?.id { Divider().padding(.vertical, 4) }
                }
            }
        }
        sectionHeading("Essentials & allocations",
                       subtitle: "Your variable spending against the plan",
                       symbol: "chart.pie")
        reportCard {
            let variableLines = summary.lines.filter { !$0.id.hasPrefix("fixed:") }
            ForEach(variableLines) { line in
                budgetLine(line)
                if line.id != variableLines.last?.id { Divider().padding(.vertical, 4) }
            }
        }
        if !summary.otherRecordedCategories.isEmpty {
            sectionHeading("Other planned expenses",
                           subtitle: "Grouped by the category you originally recorded",
                           symbol: "square.grid.2x2")
            reportCard {
                DisclosureGroup(isExpanded: $showOtherCategoryBreakdown) {
                    VStack(spacing: 0) {
                        ForEach(summary.otherRecordedCategories) { category in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category.name)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(category.transactionCount) transaction\(category.transactionCount == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(PerformanceStyle.secondary)
                                }
                                Spacer(minLength: 6)
                                Text(amount(category.spent))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .padding(.vertical, 9)
                            if category.id != summary.otherRecordedCategories.last?.id {
                                Divider()
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("Original category breakdown")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 6)
                        Text(amount(summary.otherRecordedCategories.reduce(Decimal.zero) { $0 + $1.spent }))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PerformanceStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .foregroundStyle(PerformanceStyle.primary)
            }
        }
        Text("Original categories remain intact (e.g. Uber recorded as Taxi stays Taxi). Fixed expenses are counted as paid only when a matching transaction exists.")
            .font(.caption)
            .foregroundStyle(PerformanceStyle.secondary)
            .padding(.horizontal, 4)
    }

    private func budgetLine(_ item: BudgetPerformanceLine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PerformanceStyle.primary)
                Spacer(minLength: 10)
                Text(percent(item.spentPercentage))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(item.overBudget > 0 ? PerformanceStyle.coral : PerformanceStyle.indigo)
            }
            ProgressView(value: min(1, max(0, item.spentPercentage / 100)))
                .tint(item.overBudget > 0 ? PerformanceStyle.coral : PerformanceStyle.indigo)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PAID").font(.system(size: 9, weight: .bold)).tracking(1)
                        .foregroundStyle(PerformanceStyle.secondary)
                    Text(amount(item.spent)).font(.caption.weight(.semibold))
                }
                Spacer(minLength: 10)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("PLANNED").font(.system(size: 9, weight: .bold)).tracking(1)
                        .foregroundStyle(PerformanceStyle.secondary)
                    Text(amount(item.budget)).font(.caption.weight(.semibold))
                }
            }
            if item.overBudget > 0 {
                Label("Over by \(amount(item.overBudget))", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PerformanceStyle.coral)
            } else {
                Text("Remaining \(amount(item.remaining))")
                    .font(.caption)
                    .foregroundStyle(PerformanceStyle.secondary)
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Review and recategorization

    @ViewBuilder
    private func review(_ summary: BudgetPerformanceResult) -> some View {
        let pending = summary.unassignedExpenses
        reportCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: pending.isEmpty ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 27))
                    .foregroundStyle(pending.isEmpty ? PerformanceStyle.mint : PerformanceStyle.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pending.isEmpty ? "All caught up" : "\(pending.count) expense\(pending.count == 1 ? "" : "s") to review")
                        .font(.headline)
                        .foregroundStyle(PerformanceStyle.primary)
                    Text(pending.isEmpty ? "Every payment has a budget classification." :
                            "Assign only transactions without an available allocation.")
                        .font(.caption)
                        .foregroundStyle(PerformanceStyle.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        sectionHeading("Outside budget", subtitle: "Expenses not covered by a planned allocation",
                       symbol: "exclamationmark.circle")
        reportCard {
            HStack {
                Text("Outside-budget total")
                    .font(.subheadline)
                Spacer()
                Text(amount(summary.outsideSpent))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(summary.outsideSpent > 0 ? PerformanceStyle.coral : PerformanceStyle.mint)
            }
            if !summary.outsideRecordedCategories.isEmpty {
                Divider().padding(.vertical, 6)
                ForEach(summary.outsideRecordedCategories) { category in
                    HStack {
                        Text(category.name).font(.subheadline)
                        Spacer()
                        Text(amount(category.spent))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PerformanceStyle.secondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }

        sectionHeading("Needs your review", subtitle: "Only expenses without a valid allocation",
                       symbol: "tray.full")
        reportCard {
            let rows = showAllTransactions ? pending : Array(pending.prefix(40))
            if rows.isEmpty {
                emptyMessage("Nothing to assign. Automatically categorized spending is already included.")
            } else {
                ForEach(rows) { expense in
                    expenseRow(expense)
                    if expense.id != rows.last?.id { Divider() }
                }
                if !showAllTransactions && pending.count > 40 {
                    Button("Show all \(pending.count) unassigned expenses") {
                        showAllTransactions = true
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 10)
                }
            }
        }

        if !summary.assignedExpenses.isEmpty {
            sectionHeading("Categorized transactions",
                           subtitle: "View and correct automatic or manual matching",
                           symbol: "checkmark.circle")
            reportCard {
                DisclosureGroup(isExpanded: $showAssignedTransactions) {
                    LazyVStack(spacing: 0) {
                        ForEach(summary.assignedExpenses) { expense in
                            expenseRow(expense)
                            if expense.id != summary.assignedExpenses.last?.id { Divider() }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    HStack {
                        Text("Show categorized expenses")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(summary.assignedExpenses.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(PerformanceStyle.secondary)
                    }
                }
                .foregroundStyle(PerformanceStyle.primary)
            }
        }

        if !summary.unconvertedByCurrency.isEmpty {
            sectionHeading("Other-currency records",
                           subtitle: "Excluded rather than assuming an exchange rate",
                           symbol: "globe")
            reportCard {
                ForEach(summary.unconvertedByCurrency.keys.sorted(), id: \.self) { currency in
                    HStack {
                        Text(currency).font(.subheadline)
                        Spacer()
                        Text(summary.unconvertedByCurrency[currency]?.formatted() ?? "0")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        Text("Assignments update only this report and your saved budget mapping. Your original transactions and backup/sync data remain intact. Bank-to-bank transfers are not spending; bank-to-Payments transfers are.")
            .font(.caption)
            .foregroundStyle(PerformanceStyle.secondary)
            .padding(.horizontal, 4)
    }

    private func expenseRow(_ expense: BudgetPerformanceExpense) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: expense.bucket == .outside ? "questionmark.circle" : "checkmark.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(expense.bucket == .outside ? PerformanceStyle.amber : PerformanceStyle.mint)
                    .frame(width: 24)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(expense.record.vendor?.isEmpty == false
                         ? expense.record.vendor! : expense.record.category)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PerformanceStyle.primary)
                        .lineLimit(2)
                    Text("\(expense.record.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.record.category)")
                        .font(.caption)
                        .foregroundStyle(PerformanceStyle.secondary)
                }
                Spacer(minLength: 8)
                Text(amount(expense.record.amount))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(PerformanceStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 7) {
                Text(bucketTitle(expense.bucket))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(expense.bucket == .outside ? PerformanceStyle.coral : PerformanceStyle.indigo)
                    .lineLimit(1)
                if expense.matchedManually {
                    Text("Manual")
                        .font(.system(size: 10))
                        .foregroundStyle(PerformanceStyle.secondary)
                }
                Spacer(minLength: 5)
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
                    HStack(spacing: 4) {
                        Text(expense.matchedManually ? "Change" : "Assign")
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PerformanceStyle.indigo.opacity(0.09),
                                in: Capsule())
                }
                .accessibilityLabel("Change budget classification")
            }
        }
        .padding(.vertical, 12)
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

    // MARK: - Reusable presentation

    private func sectionHeading(_ title: String, subtitle: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PerformanceStyle.indigo)
                .frame(width: 34, height: 34)
                .background(PerformanceStyle.indigo.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(PerformanceStyle.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(PerformanceStyle.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private func reportCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PerformanceStyle.surface,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(PerformanceStyle.indigo.opacity(0.07), lineWidth: 1)
        }
    }

    private func emptyMessage(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle")
            .font(.subheadline)
            .foregroundStyle(PerformanceStyle.secondary)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func amount(_ value: Decimal) -> String {
        "\(store.currencyCode) \(value.formatted(.number.precision(.fractionLength(2))))"
    }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value) }
}
