import SwiftUI

private enum ChartEditorDestination: Identifiable {
    case account(UUID?)
    case category(TransactionType, String?)

    var id: String {
        switch self {
        case .account(let id): return "account-\(id?.uuidString ?? "new")"
        case .category(let type, let name): return "category-\(type.rawValue)-\(name ?? "new")"
        }
    }
}

struct ChartOfAccountsView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("ChartOfAccountsHideZeroBalance") private var hideZeroBalanceAccounts = false
    @State private var searchText = ""
    @State private var editor: ChartEditorDestination?

    var body: some View {
        List {
            Section {
                Toggle(isOn: $hideZeroBalanceAccounts) {
                    Label("Hide Zero-Balance Accounts", systemImage: "eye.slash.fill")
                }
            } footer: {
                Text("Hide accounts whose current balance is zero. Totals remain unchanged because hidden accounts have no balance.")
            }

            accountSections
            categorySection(type: .income, title: "Income", icon: "arrow.down.left.circle.fill")
            categorySection(type: .expense, title: "Expenses", icon: "arrow.up.right.circle.fill")
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chart of Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search accounts or categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editor = .account(nil) } label: {
                        Label("New Account", systemImage: "building.columns.fill")
                    }
                    Button { editor = .category(.income, nil) } label: {
                        Label("New Income Category", systemImage: "arrow.down.left.circle.fill")
                    }
                    Button { editor = .category(.expense, nil) } label: {
                        Label("New Expense Category", systemImage: "arrow.up.right.circle.fill")
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(item: $editor) { destination in
            switch destination {
            case .account(let id):
                AccountEditorView(account: store.account(withID: id))
                    .environmentObject(store)
            case .category(let type, let name):
                ChartCategoryEditorView(type: type, originalName: name)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private var accountSections: some View {
        ForEach(AccountNature.allCases) { nature in
            let items = accounts(for: nature)
            if !items.isEmpty {
                Section {
                    ForEach(items) { account in
                        HStack(spacing: 8) {
                            NavigationLink {
                                ChartLinkedTransactionsView(
                                    title: account.name,
                                    accountID: account.id,
                                    category: nil,
                                    type: nil
                                )
                                .environmentObject(store)
                            } label: {
                                ChartAccountRow(account: account)
                                    .environmentObject(store)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button { editor = .account(account.id) } label: {
                                Image(systemName: "pencil")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Edit \(account.name)")
                        }
                    }
                } header: {
                    accountSectionHeader(nature: nature, accounts: items)
                } footer: {
                    Text("Tap an account to view related transactions. Use the pencil to edit it.")
                }
            }
        }
    }

    private func accountSectionHeader(nature: AccountNature, accounts: [LedgerAccount]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(nature.title) Accounts", systemImage: natureIcon(nature))
            Text("Total: \(accountTotalsText(accounts))")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func categorySection(type: TransactionType, title: String, icon: String) -> some View {
        let categories = filteredCategories(type)
        if !categories.isEmpty {
            Section {
                ForEach(categories, id: \.self) { category in
                    HStack(spacing: 8) {
                        NavigationLink {
                            ChartLinkedTransactionsView(
                                title: category,
                                accountID: nil,
                                category: category,
                                type: type
                            )
                            .environmentObject(store)
                        } label: {
                            HStack(spacing: 12) {
                                classificationBadge(
                                    type == .income ? "INCOME" : "EXPENSE",
                                    tint: type == .income ? .green : .red
                                )
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(category).font(.body.weight(.semibold))
                                    Text("\(transactionCount(category: category, type: type)) transactions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Text(categoryTotalsText(category: category, type: type))
                                    .font(.caption.bold().monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.65)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button { editor = .category(type, category) } label: {
                            Image(systemName: "pencil")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Edit \(category)")
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            store.deleteChartCategory(type: type, name: category)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(title) Categories", systemImage: icon)
                    Text("Total: \(transactionTypeTotalsText(type: type))")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .textCase(nil)
            } footer: {
                Text("Tap a category to view its related transactions. Use the pencil to edit its name or code.")
            }
        }
    }

    private func accounts(for nature: AccountNature) -> [LedgerAccount] {
        store.accounts
            .filter { !$0.isArchived && ($0.nature ?? .unassigned) == nature }
            .filter { !hideZeroBalanceAccounts || store.balance(for: $0) != 0 }
            .filter(matchesSearch)
            .sorted {
                let left = $0.chartCode ?? "9999"
                let right = $1.chartCode ?? "9999"
                return left == right
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : left.localizedStandardCompare(right) == .orderedAscending
            }
    }

    private func filteredCategories(_ type: TransactionType) -> [String] {
        store.categories(for: type)
            .filter { category in
                searchText.isEmpty ||
                    category.localizedCaseInsensitiveContains(searchText) ||
                    store.chartCode(for: category, type: type).localizedCaseInsensitiveContains(searchText)
            }
            .sorted {
                let left = store.chartCode(for: $0, type: type)
                let right = store.chartCode(for: $1, type: type)
                if left.isEmpty != right.isEmpty { return !left.isEmpty }
                return left == right
                    ? $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
                    : left.localizedStandardCompare(right) == .orderedAscending
            }
    }

    private func matchesSearch(_ account: LedgerAccount) -> Bool {
        searchText.isEmpty ||
            account.name.localizedCaseInsensitiveContains(searchText) ||
            account.currencyCode.localizedCaseInsensitiveContains(searchText) ||
            accountBadgeTitle(account).localizedCaseInsensitiveContains(searchText) ||
            (account.chartCode ?? "").localizedCaseInsensitiveContains(searchText)
    }

    private func transactionCount(category: String, type: TransactionType) -> Int {
        store.transactions.lazy.filter {
            $0.type == type && $0.category.caseInsensitiveCompare(category) == .orderedSame
        }.count
    }

    private func accountTotalsText(_ accounts: [LedgerAccount]) -> String {
        var totals: [String: Decimal] = [:]
        for account in accounts {
            totals[account.currencyCode, default: 0] += store.balance(for: account)
        }
        return formattedTotals(totals)
    }

    private func categoryTotalsText(category: String, type: TransactionType) -> String {
        formattedTotals(transactionTotals(type: type, category: category))
    }

    private func transactionTypeTotalsText(type: TransactionType) -> String {
        formattedTotals(transactionTotals(type: type, category: nil))
    }

    private func transactionTotals(type: TransactionType, category: String?) -> [String: Decimal] {
        var totals: [String: Decimal] = [:]
        for transaction in store.transactions where transaction.type == type {
            if let category,
               transaction.category.caseInsensitiveCompare(category) != .orderedSame {
                continue
            }

            let accountID: UUID?
            let amount: Decimal
            if type == .income {
                accountID = store.reportIncomeAccountID(transaction) ?? transaction.accountID
                amount = store.reportIncomeAmount(transaction)
            } else {
                accountID = transaction.accountID
                amount = transaction.amount
            }

            let currency = store.account(withID: accountID)?.currencyCode ?? store.currencyCode
            totals[currency, default: 0] += amount
        }
        return totals
    }

    private func formattedTotals(_ totals: [String: Decimal]) -> String {
        if totals.isEmpty {
            return DisplayFormat.currency(0, code: store.currencyCode)
        }
        return totals.keys.sorted().map { currency in
            DisplayFormat.currency(totals[currency] ?? 0, code: currency)
        }.joined(separator: " • ")
    }

    private func natureIcon(_ nature: AccountNature) -> String {
        switch nature {
        case .bank: return "building.columns.fill"
        case .asset: return "house.fill"
        case .loan: return "creditcard.trianglebadge.exclamationmark"
        case .control: return "arrow.left.arrow.right.circle.fill"
        case .dailyExpense: return "cart.fill"
        case .unassigned: return "questionmark.folder.fill"
        case .receivable, .payable: return "arrow.left.arrow.right.circle.fill"
        case .fixedAsset: return "building.2.fill"
        case .fixedLiability: return "creditcard.trianglebadge.exclamationmark"
        }
    }

    private func accountBadgeTitle(_ account: LedgerAccount) -> String {
        switch account.nature ?? .unassigned {
        case .bank: return "BANK"
        case .asset: return "ASSET"
        case .loan: return "LOAN"
        case .control: return "CONTROL"
        case .dailyExpense: return "EXPENSE"
        case .unassigned: return "OTHER"
        case .receivable: return "RECV"
        case .payable: return "PAY"
        case .fixedAsset: return "ASSET"
        case .fixedLiability: return "LIAB"
        }
    }

    private func classificationBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .frame(width: 48, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ChartAccountRow: View {
    @EnvironmentObject private var store: LedgerStore
    let account: LedgerAccount

    var body: some View {
        HStack(spacing: 12) {
            classificationBadge
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).font(.body.weight(.semibold))
                Text("\(account.group.title) · \(account.currencyCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private var classificationBadge: some View {
        Text(badgeTitle)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(AppTheme.purple)
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .frame(width: 48, height: 30)
            .background(
                AppTheme.purple.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
    }

    private var badgeTitle: String {
        switch account.nature ?? .unassigned {
        case .bank: return "BANK"
        case .asset: return "ASSET"
        case .loan: return "LOAN"
        case .control: return "CONTROL"
        case .dailyExpense: return "EXPENSE"
        case .unassigned: return "OTHER"
        case .receivable: return "RECV"
        case .payable: return "PAY"
        case .fixedAsset: return "ASSET"
        case .fixedLiability: return "LIAB"
        }
    }
}

private struct ChartCategoryEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let type: TransactionType
    let originalName: String?
    @State private var name: String
    @State private var code: String

    init(type: TransactionType, originalName: String?) {
        self.type = type
        self.originalName = originalName
        _name = State(initialValue: originalName ?? "")
        _code = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Chart Entry") {
                    TextField("Code", text: $code)
                        .keyboardType(.numberPad)
                    TextField(type == .income ? "Income category" : "Expense category", text: $name)
                }
                if let originalName {
                    Section {
                        LabeledContent("Transactions", value: "\(usageCount)")
                    } footer: {
                        Text("Renaming updates matching transactions\(type == .expense ? ", vendor rules and budgets" : "").")
                    }
                }
            }
            .navigationTitle(originalName == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveChartCategory(type: type, originalName: originalName, name: name, code: code)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let originalName { code = store.chartCode(for: originalName, type: type) }
            }
        }
    }

    private var usageCount: Int {
        guard let originalName else { return 0 }
        return store.transactions.lazy.filter {
            $0.type == type && $0.category.caseInsensitiveCompare(originalName) == .orderedSame
        }.count
    }
}
