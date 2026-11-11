import SwiftUI

private enum TransactionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case income = "Income"
    case expense = "Expenses"
    case transfer = "Transfers"
    var id: String { rawValue }
}

private enum DateFilterPreset: String, CaseIterable, Identifiable {
    case all = "All Dates"
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case custom = "Custom Range"
    var id: String { rawValue }
}

private struct TransactionDayGroup: Identifiable {
    let date: Date
    let title: String
    let transactions: [LedgerTransaction]
    var id: Date { date }
}

struct TransactionsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: TransactionFilter = .all
    @State private var searchText = ""
    @State private var editingTransaction: LedgerTransaction?
    @State private var showingFilters = false
    @State private var dateFilter: DateFilterPreset = .all
    @State private var startDate = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var categoryFilter = ""
    @State private var accountFilter: UUID?
    @State private var minimumAmount = ""
    @State private var maximumAmount = ""
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Transaction type", selection: $filter) {
                    ForEach(TransactionFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if filteredTransactions.isEmpty {
                    Spacer()
                    EmptyLedgerView(
                        title: searchText.isEmpty ? "No transactions" : "No matching transactions",
                        message: searchText.isEmpty
                            ? "Tap + to record income or an expense."
                            : "Try a different category, amount, or description."
                    )
                    Spacer()
                } else {
                    List {
                        ForEach(groupedDays) { group in
                            Section(group.title) {
                                ForEach(group.transactions) { transaction in
                                    Button {
                                        editingTransaction = transaction
                                    } label: {
                                        TransactionRow(
                                            transaction: transaction,
                                            accountID: filter == .income
                                                ? store.reportIncomeAccountID(transaction)
                                                : nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .transactionSwipeActions(transaction)
                                    .contextMenu {
                                        Button {
                                            editingTransaction = transaction
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            store.delete(transaction)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(AppTheme.page)
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search transactions")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filters", systemImage: activeFilterCount > 0
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { onAdd(.expense) } label: {
                            Label("Add Expense", systemImage: "minus.circle.fill")
                        }
                        Button { onAdd(.income) } label: {
                            Label("Add Income", systemImage: "plus.circle.fill")
                        }
                        Button(action: onTransfer) {
                            Label("New Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add transaction")
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                if transaction.type == .transfer {
                    TransferView(transaction: transaction)
                        .environmentObject(store)
                } else {
                    AddTransactionView(transaction: transaction)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showingFilters) {
                NavigationStack {
                    Form {
                        Section("Date") {
                            Picker("Period", selection: $dateFilter) {
                                ForEach(DateFilterPreset.allCases) { Text($0.rawValue).tag($0) }
                            }
                            if dateFilter == .custom {
                                DatePicker("From", selection: $startDate, displayedComponents: .date)
                                DatePicker("To", selection: $endDate, displayedComponents: .date)
                            }
                        }
                        Section("Details") {
                            Picker("Category", selection: $categoryFilter) {
                                Text("All Categories").tag("")
                                ForEach(allCategories, id: \.self) { Text($0).tag($0) }
                            }
                            Picker("Account", selection: $accountFilter) {
                                Text("All Accounts").tag(Optional<UUID>.none)
                                ForEach(store.accounts) { account in
                                    Text(account.name).tag(Optional(account.id))
                                }
                            }
                            TextField("Minimum amount", text: $minimumAmount)
                                .keyboardType(.decimalPad)
                            TextField("Maximum amount", text: $maximumAmount)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .navigationTitle("Transaction Filters")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Reset", action: resetAdvancedFilters)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingFilters = false }
                        }
                    }
                }
            }
        }
    }

    private var filteredTransactions: [LedgerTransaction] {
        store.transactions.filter { transaction in
            let typeMatches: Bool
            switch filter {
            case .all: typeMatches = true
            case .income: typeMatches = store.isReportIncome(transaction)
            case .expense: typeMatches = transaction.type == .expense
            case .transfer: typeMatches = transaction.type == .transfer
            }
            guard typeMatches else { return false }
            guard dateMatches(transaction.date) else { return false }
            if !categoryFilter.isEmpty,
               transaction.category.caseInsensitiveCompare(categoryFilter) != .orderedSame {
                return false
            }
            if let accountFilter,
               transaction.accountID != accountFilter &&
               transaction.destinationAccountID != accountFilter {
                return false
            }
            if let minimum = decimalFilter(minimumAmount), transaction.amount < minimum { return false }
            if let maximum = decimalFilter(maximumAmount), transaction.amount > maximum { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return transaction.category.lowercased().contains(query)
                || (transaction.vendor?.lowercased().contains(query) ?? false)
                || transaction.details.lowercased().contains(query)
                || (store.account(withID: transaction.accountID)?.name.lowercased().contains(query) ?? false)
                || (store.account(withID: transaction.destinationAccountID)?.name.lowercased().contains(query) ?? false)
                || NSDecimalNumber(decimal: transaction.amount).stringValue.contains(query)
        }
    }

    private var allCategories: [String] {
        Array(Set(store.transactions.map(\.category))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if dateFilter != .all { count += 1 }
        if !categoryFilter.isEmpty { count += 1 }
        if accountFilter != nil { count += 1 }
        if !minimumAmount.isEmpty { count += 1 }
        if !maximumAmount.isEmpty { count += 1 }
        return count
    }

    private func dateMatches(_ date: Date) -> Bool {
        let calendar = Calendar.current
        switch dateFilter {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: Date())?.contains(date) ?? true
        case .month:
            return calendar.dateInterval(of: .month, for: Date())?.contains(date) ?? true
        case .custom:
            let lower = calendar.startOfDay(for: min(startDate, endDate))
            let upperDay = calendar.startOfDay(for: max(startDate, endDate))
            let upper = calendar.date(byAdding: .day, value: 1, to: upperDay) ?? upperDay
            return date >= lower && date < upper
        }
    }

    private func decimalFilter(_ text: String) -> Decimal? {
        Decimal(
            string: text.replacingOccurrences(of: ",", with: "."),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func resetAdvancedFilters() {
        dateFilter = .all
        categoryFilter = ""
        accountFilter = nil
        minimumAmount = ""
        maximumAmount = ""
    }

    private var groupedDays: [TransactionDayGroup] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: filteredTransactions) {
            calendar.startOfDay(for: $0.date)
        }
        return groups.keys.sorted(by: >).map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = "Today"
            } else if calendar.isDateInYesterday(date) {
                title = "Yesterday"
            } else {
                title = DisplayFormat.day.string(from: date)
            }
            return TransactionDayGroup(
                date: date,
                title: title,
                transactions: groups[date, default: []].sorted { $0.date > $1.date }
            )
        }
    }
}
