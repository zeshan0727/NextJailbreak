import SwiftUI

private struct SpendingSuggestion: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
}

struct InsightsView: View {
    @EnvironmentObject private var store: LedgerStore
    @StateObject private var aiContext = AITransactionContextService.shared
    @StateObject private var deepSeekUsage = DeepSeekService.shared
    @AppStorage("DeepSeekModel") private var deepSeekModel = "deepseek-v4-flash"
    @AppStorage("DeepSeekLastRecommendation") private var serverAdvice = ""
    @State private var followUp = ""
    @State private var conversation: [DeepSeekMessage] = []
    @State private var loadingAdvice = false
    @State private var serverError: String?
    @AppStorage("DeepSeekTokenBudget") private var tokenBudget = 50_000
    @State private var localInsightRefresh = Date()
    @State private var fixedSuggestions: [SpendingSuggestion] = []
    @State private var refreshVariant = 0
    @AppStorage("MonthlyIncomePrimary") private var primaryIncome = 0.0
    @AppStorage("MonthlyIncomeSecondary") private var secondaryIncome = 0.0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Month")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(DisplayFormat.currency(currentExpense, code: store.currencyCode))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(monthComparisonText)
                            .font(.subheadline)
                            .foregroundStyle(monthChange > 0 ? AppTheme.red : AppTheme.green)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button {
                        localInsightRefresh = Date()
                        refreshVariant += 1
                        fixedSuggestions = makeSuggestions()
                    } label: {
                        Label("Update Fixed Insights", systemImage: "arrow.clockwise")
                    }
                    if fixedSuggestions.isEmpty {
                        Text("Add more expenses this month to receive useful suggestions.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(fixedSuggestions) { suggestion in
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: suggestion.icon)
                                    .foregroundStyle(suggestion.color)
                                    .frame(width: 36, height: 36)
                                    .background(suggestion.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.title).font(.headline)
                                    Text(suggestion.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                } header: {
                    HStack {
                        Text("Suggestions to Cut Expenses")
                        Spacer()
                        Text(localInsightRefresh, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Monthly AI Budget") {
                    Stepper("Primary income: \(DisplayFormat.currency(Decimal(primaryIncome), code: store.currencyCode))", value: $primaryIncome, in: 0...1_000_000, step: 500)
                    Stepper("Other fixed income: \(DisplayFormat.currency(Decimal(secondaryIncome), code: store.currencyCode))", value: $secondaryIncome, in: 0...1_000_000, step: 500)
                    if monthlyBudgetIncome > 0 {
                        BudgetLine(title: "Essentials", amount: monthlyBudgetIncome * Decimal(string: "0.45")!, color: AppTheme.blue, currencyCode: store.currencyCode)
                        BudgetLine(title: "Savings & goals", amount: monthlyBudgetIncome * Decimal(string: "0.20")!, color: AppTheme.green, currencyCode: store.currencyCode)
                        BudgetLine(title: "Family & flexible", amount: monthlyBudgetIncome * Decimal(string: "0.20")!, color: AppTheme.purple, currencyCode: store.currencyCode)
                        BudgetLine(title: "Personal spending", amount: monthlyBudgetIncome * Decimal(string: "0.10")!, color: AppTheme.orange, currencyCode: store.currencyCode)
                        BudgetLine(title: "Safety buffer", amount: monthlyBudgetIncome * Decimal(string: "0.05")!, color: AppTheme.teal, currencyCode: store.currencyCode)
                    }
                    Text("Income amounts stay in this app on your device. Refresh DeepSeek Recommendations for a plan adjusted to current spending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("AI Data Access") {
                    AITransactionContextControls()
                }

                Section("DeepSeek Recommendations") {
                    if !DeepSeekService.shared.hasAPIKey {
                        Label("Connect DeepSeek in Settings to receive server-generated recommendations.", systemImage: "key.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            generateServerAdvice()
                        } label: {
                            HStack {
                                Label(
                                    serverAdvice.isEmpty ? "Generate Recommendations" : "Refresh Recommendations",
                                    systemImage: "sparkles"
                                )
                                Spacer()
                                if loadingAdvice { ProgressView() }
                            }
                        }
                        .disabled(loadingAdvice || aiContext.loadedTransactionIDs.isEmpty)
                    }

                    if let serverError {
                        Label(serverError, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.red)
                    }

                    if !serverAdvice.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(AppTheme.purple)
                                Text("Your Spending Plan")
                                    .font(.headline)
                            }
                            Text(serverAdvice)
                                .font(.body)
                                .textSelection(.enabled)
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 8)

                        HStack(spacing: 8) {
                            TextField("Ask about this recommendation", text: $followUp, axis: .vertical)
                                .lineLimit(1...4)
                            Button {
                                sendFollowUp()
                            } label: {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                            }
                            .disabled(followUp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loadingAdvice)
                        }
                    }
                }

                Section("DeepSeek Token Usage") {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("\(deepSeekUsage.totalTokens.formatted()) tokens")
                                .font(.headline)
                            Spacer()
                            Text("Target: \(tokenBudget.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(Double(deepSeekUsage.totalTokens) / Double(max(tokenBudget, 1)), 1))
                            .tint(deepSeekUsage.totalTokens >= tokenBudget ? AppTheme.red : AppTheme.purple)
                        HStack {
                            Text("Input \(deepSeekUsage.promptTokens.formatted())")
                            Spacer()
                            Text("Output \(deepSeekUsage.completionTokens.formatted())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Stepper("Usage target: \(tokenBudget.formatted())", value: $tokenBudget, in: 5_000...500_000, step: 5_000)
                    Button("Reset Usage Counter", role: .destructive) {
                        deepSeekUsage.resetUsage()
                    }
                    .disabled(deepSeekUsage.totalTokens == 0)
                }

                Section("General AI Chat") {
                    NavigationLink {
                        OpenAIChatView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("OpenAI Chat").font(.headline)
                                Text("Separate persistent text chat")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bubble.left.fill").foregroundStyle(AppTheme.green)
                        }
                    }
                    NavigationLink {
                        DeepSeekChatView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("DeepSeek Chat").font(.headline)
                                Text("Separate DeepSeek window and history")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(AppTheme.blue)
                        }
                    }
                }

                Section {
                    Text("Local suggestions stay on this iPhone. DeepSeek is contacted only when you press Generate or send a follow-up, using summarized categories and totals without raw transaction descriptions, account numbers, or individual vendor descriptions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AI Insights")
            .listStyle(.insetGrouped)
            .onAppear {
                aiContext.ensureDefault(from: store.transactions)
                if fixedSuggestions.isEmpty { fixedSuggestions = makeSuggestions() }
            }
        }
    }

    private var currentMonth: DateInterval {
        Calendar.current.dateInterval(of: .month, for: Date())!
    }

    private var monthlyBudgetIncome: Decimal {
        Decimal(primaryIncome + secondaryIncome)
    }

    private var previousMonth: DateInterval {
        let date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        return Calendar.current.dateInterval(of: .month, for: date)!
    }

    private var currentExpenses: [LedgerTransaction] {
        expenses(in: currentMonth)
    }

    private var currentExpense: Decimal {
        currentExpenses.reduce(0) { $0 + $1.amount }
    }

    private var previousExpense: Decimal {
        expenses(in: previousMonth).reduce(0) { $0 + $1.amount }
    }

    private var monthChange: Decimal { currentExpense - previousExpense }

    private var monthComparisonText: String {
        if previousExpense == 0 { return "No previous-month comparison yet" }
        let direction = monthChange > 0 ? "more" : "less"
        return "\(DisplayFormat.currency(abs(monthChange), code: store.currencyCode)) \(direction) than last month"
    }

    private func makeSuggestions() -> [SpendingSuggestion] {
        guard currentExpense > 0 else { return [] }
        var result: [SpendingSuggestion] = []
        let grouped = Dictionary(grouping: currentExpenses, by: \.category)
        if let top = grouped.max(by: { left, right in
            expenseTotal(left.value) < expenseTotal(right.value)
        }) {
            let amount = top.value.reduce(Decimal.zero) { $0 + $1.amount }
            let target = amount / 10
            result.append(SpendingSuggestion(
                id: "top-category",
                title: "Reduce \(top.key) by 10%",
                detail: "Your largest category is \(DisplayFormat.currency(amount, code: store.currencyCode)). A 10% reduction could save \(DisplayFormat.currency(target, code: store.currencyCode)) this month.",
                icon: "chart.pie.fill",
                color: AppTheme.orange
            ))
        }
        let small = currentExpenses.filter { $0.amount <= 50 }
        if small.count >= 5 {
            let total = small.reduce(Decimal.zero) { $0 + $1.amount }
            result.append(SpendingSuggestion(
                id: "small-purchases",
                title: "Watch frequent small purchases",
                detail: "\(small.count) purchases of \(store.currencyCode) 50 or less total \(DisplayFormat.currency(total, code: store.currencyCode)). Combining or skipping a few can make a visible difference.",
                icon: "cup.and.saucer.fill",
                color: AppTheme.purple
            ))
        }
        if monthChange > 0, previousExpense > 0 {
            result.append(SpendingSuggestion(
                id: "month-growth",
                title: "Spending is above last month",
                detail: "You have spent \(DisplayFormat.currency(monthChange, code: store.currencyCode)) more. Review the top category before making non-essential purchases.",
                icon: "arrow.up.right.circle.fill",
                color: AppTheme.red
            ))
        }
        let day = max(Calendar.current.component(.day, from: Date()), 1)
        let dailyAverage = currentExpense / Decimal(day)
        result.append(SpendingSuggestion(
            id: "daily-pace-\(day)",
            title: "Current daily pace",
            detail: "You are averaging \(DisplayFormat.currency(dailyAverage, code: store.currencyCode)) per day; keep the next seven days below this level to improve the month.",
            icon: "speedometer",
            color: AppTheme.teal
        ))
        let rotating = [
            ("Plan one low-spend day", "Choose one day this week for essentials only and compare it with your current daily average.", "calendar.badge.minus"),
            ("Review the top three purchases", "Open this month's largest purchases and confirm each one still matches your priorities.", "list.number"),
            ("Protect tomorrow's balance", "Delay one optional purchase for 24 hours and keep that amount available in your selected account.", "shield.checkered")
        ][refreshVariant % 3]
        result.append(SpendingSuggestion(
            id: "rotating-\(refreshVariant)", title: rotating.0, detail: rotating.1,
            icon: rotating.2, color: AppTheme.purple
        ))
        return result
    }

    private func expenses(in interval: DateInterval) -> [LedgerTransaction] {
        store.transactions.filter {
            $0.type == .expense && interval.contains($0.date) &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }
    }

    private func expenseTotal(_ transactions: [LedgerTransaction]) -> Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private func generateServerAdvice() {
        let messages = recommendationBaseMessages
        conversation = messages
        performRequest(messages)
    }

    private var recommendationBaseMessages: [DeepSeekMessage] {
        [
            DeepSeekMessage(
                role: "system",
                content: "You are a careful personal spending coach. Return only 3 or 4 prioritized bullet points. Each bullet must be one short, specific sentence with an action and, where possible, an estimated monthly saving. No introduction, conclusion, headings, disclaimers, risky investments, or borrowing advice."
            ),
            DeepSeekMessage(role: "user", content: serverSummary)
        ]
    }

    private func sendFollowUp() {
        let question = followUp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        followUp = ""
        let base = conversation.count >= 2
            ? Array(conversation.prefix(2))
            : recommendationBaseMessages
        let messages = base + [
            DeepSeekMessage(role: "assistant", content: serverAdvice),
            DeepSeekMessage(role: "user", content: question)
        ]
        conversation = messages
        performRequest(messages)
    }

    private func performRequest(_ messages: [DeepSeekMessage]) {
        loadingAdvice = true
        serverError = nil
        Task {
            do {
                let response = try await DeepSeekService.shared.request(
                    messages: messages,
                    model: deepSeekModel,
                    maxTokens: 320
                )
                await MainActor.run {
                    serverAdvice = response
                    loadingAdvice = false
                }
            } catch {
                await MainActor.run {
                    serverError = error.localizedDescription
                    loadingAdvice = false
                }
            }
        }
    }

    private var serverSummary: String {
        let fetched = aiContext.transactions(from: store.transactions)
        let expenseSample = fetched.filter {
            $0.type == .expense && store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }
        let grouped = Dictionary(grouping: expenseSample, by: \.category)
        let ranked = grouped.map { category, transactions in
            (category: category, amount: expenseTotal(transactions), count: transactions.count)
        }
        .sorted { $0.amount > $1.amount }
        let categoryLines = ranked.prefix(10).map { item in
            "- \(item.category): \(NSDecimalNumber(decimal: item.amount).stringValue) \(store.currencyCode) across \(item.count) fetched transactions"
        }
        .joined(separator: "\n")
        let fetchedExpenseTotal = expenseSample.reduce(Decimal.zero) { $0 + $1.amount }
        return """
        Analyze only this user-fetched Next Ledger transaction snapshot. Do not infer or request the rest of the ledger.
        Currency: \(store.currencyCode)
        Fetched transactions: \(fetched.count)
        Fetched expenses in selected currency: \(NSDecimalNumber(decimal: fetchedExpenseTotal).stringValue)
        Fixed monthly income entered by user: \(NSDecimalNumber(decimal: monthlyBudgetIncome).stringValue)
        Categories inside fetched snapshot:
        \(categoryLines.isEmpty ? "- No fetched expenses in selected currency" : categoryLines)
        Return only 3 or 4 concise bullets and keep the complete response under 180 words.
        """
    }
}

private struct BudgetLine: View {
    let title: String
    let amount: Decimal
    let color: Color
    let currencyCode: String

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(title)
            Spacer()
            Text(DisplayFormat.currency(amount, code: currencyCode)).bold()
        }
    }
}
