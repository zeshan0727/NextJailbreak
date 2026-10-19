import SwiftUI
import UIKit

private enum DashboardDatePreset: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case year = "This Year"
    case custom = "Custom"
    var id: String { rawValue }
}

private enum SpendingCardKind: String, CaseIterable, Identifiable {
    case today, yesterday, thisWeek, lastWeek
    var id: String { rawValue }
}

private struct NextSolutionHeaderLogo: View {
    var body: some View {
        Group {
            if let logo = NextSolutionLogoAsset.image {
                Image(uiImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.balanceGradient)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.white.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .accessibilityLabel("Next Solution logo")
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: LedgerStore
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void
    @AppStorage("DashboardDatePreset") private var storedDatePreset = DashboardDatePreset.month.rawValue
    @AppStorage("DashboardCustomStart") private var storedCustomStart = Date().timeIntervalSince1970
    @AppStorage("DashboardCustomEnd") private var storedCustomEnd = Date().timeIntervalSince1970
    @State private var showingCustomDates = false
    @State private var draftStartDate = Date()
    @State private var draftEndDate = Date()
    @State private var transactionSearch = ""
    @State private var selectedTransaction: LedgerTransaction?
    @AppStorage("DashboardAccountSelection") private var selectedAccountValue = "all"
    @State private var showingAccountSelection = false
    @State private var spendingDay: SpendingDay?
    @State private var showingCardOrder = false
    @AppStorage("DashboardSpendingCardOrder") private var storedCardOrder = "yesterday,today,thisWeek,lastWeek"
    @AppStorage(DeveloperLabKey.enabled) private var devEnabled = true
    @AppStorage(DeveloperLabKey.dashboardShowHeader) private var devShowHeader = true
    @AppStorage(DeveloperLabKey.dashboardShowSpending) private var devShowSpending = true
    @AppStorage(DeveloperLabKey.dashboardShowDateFilter) private var devShowDateFilter = true
    @AppStorage(DeveloperLabKey.dashboardShowBalance) private var devShowBalance = true
    @AppStorage(DeveloperLabKey.dashboardShowQuickActions) private var devShowQuickActions = true
    @AppStorage(DeveloperLabKey.dashboardShowRecent) private var devShowRecent = true
    @AppStorage(DeveloperLabKey.dashboardColumns) private var devDashboardColumns = 2
    @AppStorage(DeveloperLabKey.dashboardHorizontalPadding) private var devDashboardHorizontalPadding = 18.0
    @AppStorage(DeveloperLabKey.dashboardSectionSpacing) private var devDashboardSectionSpacing = 22.0
    @AppStorage(DeveloperLabKey.dashboardRecentLimit) private var devDashboardRecentLimit = 6
    @State private var dashboardSnapshot = DashboardSnapshot.empty

    private struct SpendingDay: Identifiable {
        let id = UUID()
        let title: String
        let interval: DateInterval
    }

    private struct DashboardSnapshot {
        let balance: Decimal
        let totals: LedgerTotals
        let loanMovements: [LoanNetMovement]
        let spending: [SpendingCardKind: Decimal]
        let recentTransactions: [LedgerTransaction]

        static let empty = DashboardSnapshot(
            balance: 0,
            totals: LedgerTotals(income: 0, expense: 0, loan: 0, transfer: 0, count: 0),
            loanMovements: [],
            spending: [:],
            recentTransactions: []
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: effectiveDashboardSectionSpacing) {
                    if !devEnabled || devShowHeader { header }
                    if !devEnabled || devShowSpending { dailySpending }
                    if !devEnabled || devShowDateFilter { dateFilter }
                    if !devEnabled || devShowBalance {
                        BalanceCard(
                            balance: dashboardSnapshot.balance,
                            income: dashboardSnapshot.totals.income,
                            expense: dashboardSnapshot.totals.expense,
                            loanMovements: dashboardSnapshot.loanMovements,
                            currencyCode: store.currencyCode,
                            accountSummary: accountSelectionTitle,
                            action: { showingAccountSelection = true }
                        )
                    }
                    if !devEnabled || devShowQuickActions { quickActions }
                    if !devEnabled || devShowRecent { recentTransactions }
                }
                .padding(.horizontal, effectiveDashboardHorizontalPadding)
                .padding(.bottom, 28)
            }
            .background(AppTheme.page)
            .navigationBarHidden(true)
            .onAppear(perform: refreshDashboardSnapshot)
            .onReceive(store.$transactions) { _ in refreshDashboardSnapshot() }
            .onChange(of: storedDatePreset) { _ in refreshDashboardSnapshot() }
            .onChange(of: storedCustomStart) { _ in refreshDashboardSnapshot() }
            .onChange(of: storedCustomEnd) { _ in refreshDashboardSnapshot() }
            .onChange(of: selectedAccountValue) { _ in refreshDashboardSnapshot() }
            .onChange(of: transactionSearch) { _ in refreshDashboardSnapshot() }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionSnapshotView(transaction: transaction)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingCustomDates) {
                NavigationStack {
                    Form {
                        DatePicker("From", selection: $draftStartDate, displayedComponents: .date)
                        DatePicker("To", selection: $draftEndDate, displayedComponents: .date)
                    }
                    .navigationTitle("Custom Dashboard Period")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingCustomDates = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                storedCustomStart = draftStartDate.timeIntervalSince1970
                                storedCustomEnd = draftEndDate.timeIntervalSince1970
                                storedDatePreset = DashboardDatePreset.custom.rawValue
                                showingCustomDates = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAccountSelection) {
                NavigationStack {
                    List {
                        Button {
                            selectedAccountValue = "all"
                        } label: {
                            selectionRow(
                                title: "All \(store.currencyCode) Accounts",
                                selected: selectedAccountValue == "all"
                            )
                        }
                        ForEach(selectableAccounts) { account in
                            Button {
                                toggleAccount(account.id)
                            } label: {
                                selectionRow(
                                    title: account.name,
                                    selected: selectedAccountIDs?.contains(account.id) == true
                                )
                            }
                        }
                    }
                    .navigationTitle("Dashboard Accounts")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingAccountSelection = false }
                        }
                    }
                }
            }
            .sheet(item: $spendingDay) { day in
                NavigationStack {
                    PeriodTransactionsView(kind: .expenses, interval: day.interval)
                        .navigationTitle(day.title)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { spendingDay = nil }
                            }
                        }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showingCardOrder) {
                NavigationStack {
                    List {
                        ForEach(cardOrder) { card in Text(cardTitle(card)) }
                            .onMove(perform: moveCards)
                    }
                    .environment(\.editMode, .constant(.active))
                    .navigationTitle("Rearrange Cards")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingCardOrder = false }
                        }
                    }
                }
            }
        }
    }

    private var dailySpending: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Spending shortcuts").font(.headline)
                Spacer()
                Button { showingCardOrder = true } label: {
                    Label("Edit", systemImage: "arrow.up.arrow.down")
                        .font(.caption.bold())
                }
            }
            LazyVGrid(columns: effectiveDashboardGridColumns, spacing: 12) {
                ForEach(cardOrder) { card in
                    DailySpendButton(
                        title: cardTitle(card),
                        amount: dashboardSnapshot.spending[card, default: 0],
                        currencyCode: store.currencyCode,
                        icon: cardIcon(card), colors: cardColors(card)
                    ) { openCard(card) }
                    .contextMenu {
                        Button("Rearrange Cards") { showingCardOrder = true }
                    }
                }
            }
        }
    }

    private var cardOrder: [SpendingCardKind] {
        let saved = storedCardOrder.split(separator: ",").compactMap { SpendingCardKind(rawValue: String($0)) }
        return saved.count == SpendingCardKind.allCases.count ? saved : SpendingCardKind.allCases
    }

    private func moveCards(from source: IndexSet, to destination: Int) {
        var values = cardOrder
        values.move(fromOffsets: source, toOffset: destination)
        storedCardOrder = values.map(\.rawValue).joined(separator: ",")
    }

    private func cardTitle(_ card: SpendingCardKind) -> String {
        switch card { case .today: return "Today"; case .yesterday: return "Yesterday"; case .thisWeek: return "This week"; case .lastWeek: return "Last week" }
    }
    private func cardIcon(_ card: SpendingCardKind) -> String {
        switch card { case .today: return "clock.fill"; case .yesterday: return "sun.haze.fill"; case .thisWeek: return "calendar"; case .lastWeek: return "calendar.badge.clock" }
    }
    private func cardColors(_ card: SpendingCardKind) -> [Color] {
        switch card { case .today: return [AppTheme.orange, AppTheme.red]; case .yesterday: return [AppTheme.purple, AppTheme.blue]; case .thisWeek: return [AppTheme.teal, AppTheme.blue]; case .lastWeek: return [AppTheme.green, AppTheme.teal] }
    }
    private func cardInterval(_ card: SpendingCardKind) -> DateInterval {
        let calendar = Calendar.current
        switch card {
        case .today: return calendar.dateInterval(of: .day, for: Date())!
        case .yesterday: return calendar.dateInterval(of: .day, for: calendar.date(byAdding: .day, value: -1, to: Date())!)!
        case .thisWeek: return calendar.dateInterval(of: .weekOfYear, for: Date())!
        case .lastWeek:
            let date = calendar.date(byAdding: .weekOfYear, value: -1, to: Date())!
            return calendar.dateInterval(of: .weekOfYear, for: date)!
        }
    }
    private func openCard(_ card: SpendingCardKind) {
        spendingDay = SpendingDay(title: cardTitle(card) + " Expenses", interval: cardInterval(card))
    }

    private func openSpendingDay(offset: Int, title: String) {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return }
        spendingDay = SpendingDay(title: title, interval: interval)
    }

    private func expense(on date: Date) -> Decimal {
        let calendar = Calendar.current
        return store.transactions.lazy.filter {
            $0.type == .expense && calendar.isDate($0.date, inSameDayAs: date) &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.reduce(Decimal.zero) { $0 + $1.amount }
    }

    private var dateFilter: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Dashboard period").font(.headline)
                Spacer()
                Text(periodTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.purple)
            }
            Menu {
                ForEach(DashboardDatePreset.allCases) { preset in
                    Button {
                        if preset == .custom {
                            draftStartDate = Date(timeIntervalSince1970: storedCustomStart)
                            draftEndDate = Date(timeIntervalSince1970: storedCustomEnd)
                            showingCustomDates = true
                        } else {
                            storedDatePreset = preset.rawValue
                        }
                    } label: {
                        if selectedDatePreset == preset {
                            Label(preset.rawValue, systemImage: "checkmark")
                        } else {
                            Text(preset.rawValue)
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "calendar")
                    Text(selectedDatePreset.rawValue)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .padding(13)
                .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Next Ledger")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text("Your money at a glance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            NextSolutionHeaderLogo()
        }
        .padding(.top, 16)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick add")
                .font(.headline)
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Income",
                    subtitle: "Money received",
                    icon: "plus",
                    colors: [AppTheme.green, AppTheme.teal]
                ) { onAdd(.income) }

                QuickActionButton(
                    title: "Expense",
                    subtitle: "Money spent",
                    icon: "minus",
                    colors: [AppTheme.orange, AppTheme.red]
                ) { onAdd(.expense) }
            }
            QuickActionButton(
                title: "Transfer",
                subtitle: "Move money between accounts",
                icon: "arrow.left.arrow.right",
                colors: [AppTheme.purple, AppTheme.blue]
            ) { onTransfer() }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent transactions")
                    .font(.headline)
                Spacer()
                Text("\(periodTitle): \(dashboardSnapshot.totals.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search recent transactions", text: $transactionSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !transactionSearch.isEmpty {
                    Button {
                        transactionSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if dashboardSnapshot.recentTransactions.isEmpty {
                EmptyLedgerView(
                    title: "No transactions yet",
                    message: "Use one of the colorful buttons above to add your first entry."
                )
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dashboardSnapshot.recentTransactions.prefix(effectiveDashboardRecentLimit).enumerated()), id: \.element.id) { index, transaction in
                        Button {
                            selectedTransaction = transaction
                        } label: {
                            TransactionRow(transaction: transaction)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .transactionSwipeActions(transaction)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(transaction)
                            } label: {
                                Label("Delete Transaction", systemImage: "trash")
                            }
                        }
                        if index < min(dashboardSnapshot.recentTransactions.count, effectiveDashboardRecentLimit) - 1 {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }

    private var effectiveDashboardSectionSpacing: CGFloat {
        devEnabled ? CGFloat(max(4, min(40, devDashboardSectionSpacing))) : 22
    }

    private var effectiveDashboardHorizontalPadding: CGFloat {
        devEnabled ? CGFloat(max(0, min(32, devDashboardHorizontalPadding))) : 18
    }

    private var effectiveDashboardGridColumns: [GridItem] {
        let count = devEnabled ? max(1, min(3, devDashboardColumns)) : 2
        return Array(repeating: GridItem(.flexible()), count: count)
    }

    private var effectiveDashboardRecentLimit: Int {
        devEnabled ? max(1, min(20, devDashboardRecentLimit)) : 6
    }

    private var selectedDatePreset: DashboardDatePreset {
        DashboardDatePreset(rawValue: storedDatePreset) ?? .month
    }

    private var selectedInterval: DateInterval {
        let calendar = Calendar.current
        switch selectedDatePreset {
        case .today:
            return calendar.dateInterval(of: .day, for: Date())!
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: Date())!
        case .month:
            return calendar.dateInterval(of: .month, for: Date())!
        case .year:
            return calendar.dateInterval(of: .year, for: Date())!
        case .custom:
            let first = Date(timeIntervalSince1970: storedCustomStart)
            let second = Date(timeIntervalSince1970: storedCustomEnd)
            let start = calendar.startOfDay(for: min(first, second))
            let endDay = calendar.startOfDay(for: max(first, second))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: start, end: end)
        }
    }

    private func refreshDashboardSnapshot() {
        let interval = selectedInterval
        let accountIDs = selectedAccountIDs
        let query = transactionSearch
        let recent = store.transactions.filter {
            let accountMatches = accountIDs == nil ||
                accountIDs?.contains($0.accountID ?? LedgerAccount.legacyMainID) == true ||
                accountIDs?.contains($0.destinationAccountID ?? LedgerAccount.legacyMainID) == true
            guard interval.contains($0.date), accountMatches, !query.isEmpty else {
                return interval.contains($0.date) && accountMatches
            }
            return $0.category.localizedCaseInsensitiveContains(query) ||
                ($0.vendor?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(query) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(query)
        }

        var spending: [SpendingCardKind: Decimal] = [:]
        for card in SpendingCardKind.allCases {
            let cardInterval = cardInterval(card)
            spending[card] = store.transactions.lazy.filter {
                $0.type == .expense && cardInterval.contains($0.date) &&
                    store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
            }.reduce(Decimal.zero) { $0 + $1.amount }
        }

        dashboardSnapshot = DashboardSnapshot(
            balance: store.remainingBalance(accountIDs: accountIDs),
            totals: store.totals(in: interval, accountIDs: accountIDs),
            loanMovements: store.loanNetMovements(in: interval, accountIDs: accountIDs),
            spending: spending,
            recentTransactions: recent
        )
    }

    private var selectedAccountIDs: Set<UUID>? {
        guard selectedAccountValue != "all" else { return nil }
        let ids = Set(selectedAccountValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        return ids.isEmpty ? nil : ids
    }

    private var selectableAccounts: [LedgerAccount] {
        store.activeAccounts
            .filter { $0.currencyCode == store.currencyCode }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var accountSelectionTitle: String {
        guard let ids = selectedAccountIDs else { return "All \(store.currencyCode) accounts · Tap to select" }
        let names = selectableAccounts.filter { ids.contains($0.id) }.map(\.name)
        if names.count == 1 { return names[0] + " · Tap to change" }
        return "\(names.count) accounts selected · Tap to change"
    }

    private func toggleAccount(_ id: UUID) {
        var ids = selectedAccountIDs ?? []
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        selectedAccountValue = ids.isEmpty
            ? "all"
            : ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    private func selectionRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.purple)
            }
        }
        .foregroundStyle(.primary)
    }

    private var periodTitle: String {
        switch selectedDatePreset {
        case .today: return "Today"
        case .week: return "This week"
        case .month: return "This month"
        case .year: return "This year"
        case .custom:
            return "\(DisplayFormat.day.string(from: selectedInterval.start)) – \(DisplayFormat.day.string(from: selectedInterval.end.addingTimeInterval(-1)))"
        }
    }

}

private struct DailySpendButton: View {
    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue
    let title: String
    let amount: Decimal
    let currencyCode: String
    let icon: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
        Group {
            if visualTheme == AppVisualTheme.glass.rawValue { cardContent.dailyLedgerGlass(tint: colors.first ?? AppTheme.purple, interactive: true) }
            else { cardContent }
        }
        .developerSurface()
        }
        .buttonStyle(.plain)
    }

    private var cardContent: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(DisplayFormat.currency(amount, code: currencyCode))
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.20), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .developerSurface()
        }
        .buttonStyle(.plain)
    }
}
