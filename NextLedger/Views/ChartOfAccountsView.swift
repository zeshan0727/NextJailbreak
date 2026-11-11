import Foundation
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

private enum BalanceSheetBucket: String, CaseIterable, Identifiable {
    case bank
    case assets
    case receivables
    case payables
    case liabilitiesOther

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: return "Bank & Cash"
        case .assets: return "Assets"
        case .receivables: return "Receivables"
        case .payables: return "Payables & Loan Liabilities"
        case .liabilitiesOther: return "Liabilities & Other"
        }
    }

    var badge: String {
        switch self {
        case .bank: return "BANK"
        case .assets: return "ASSET"
        case .receivables: return "RECV"
        case .payables: return "PAY"
        case .liabilitiesOther: return "OTHER"
        }
    }

    var icon: String {
        switch self {
        case .bank: return "building.columns.fill"
        case .assets: return "house.fill"
        case .receivables: return "person.crop.circle.badge.clock.fill"
        case .payables: return "creditcard.trianglebadge.exclamationmark"
        case .liabilitiesOther: return "list.bullet.rectangle.portrait.fill"
        }
    }
}

struct ChartOfAccountsView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("ChartOfAccountsHideZeroBalance") private var hideZeroBalanceAccounts = false
    @State private var searchText = ""
    @State private var editor: ChartEditorDestination?
    @State private var incomeStatementExpanded = false
    @State private var balanceSheetExpanded = false
    @State private var expandedMainAccountIDs: Set<UUID> = []

    var body: some View {
        List {
            Section {
                Toggle(isOn: $hideZeroBalanceAccounts) {
                    Label("Hide Zero-Balance Accounts", systemImage: "eye.slash.fill")
                }
            } footer: {
                Text("For main accounts, zero balance is checked across the parent and all direct sub-accounts, with each currency evaluated separately.")
            }

            incomeStatementSection
            balanceSheetSection
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

    private var incomeStatementSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    incomeStatementExpanded.toggle()
                }
            } label: {
                statementDisclosureHeader(
                    title: "Income Statement",
                    subtitle: "Income and expense accounts",
                    icon: "chart.line.uptrend.xyaxis",
                    isExpanded: incomeStatementExpanded
                )
            }
            .buttonStyle(.plain)

            if incomeStatementExpanded {
                statementGroupHeader(
                    title: "Income",
                    icon: "arrow.down.left.circle.fill",
                    total: transactionTypeTotalsText(type: .income),
                    tint: AppTheme.green
                )
                let incomeCategories = filteredCategories(.income)
                if incomeCategories.isEmpty {
                    Text("No matching income categories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(incomeCategories, id: \.self) { category in
                        categoryRow(category, type: .income)
                    }
                }

                statementGroupHeader(
                    title: "Expenses",
                    icon: "arrow.up.right.circle.fill",
                    total: transactionTypeTotalsText(type: .expense),
                    tint: AppTheme.red
                )
                let expenseCategories = filteredCategories(.expense)
                if expenseCategories.isEmpty {
                    Text("No matching expense categories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenseCategories, id: \.self) { category in
                        categoryRow(category, type: .expense)
                    }
                }
            }
        } footer: {
            if incomeStatementExpanded {
                Text("Income and expense categories are presented together as the Income Statement.")
            }
        }
    }

    private var balanceSheetSection: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    balanceSheetExpanded.toggle()
                }
            } label: {
                statementDisclosureHeader(
                    title: "Balance Sheet",
                    subtitle: "Bank, assets, receivables, payables and liabilities",
                    icon: "building.columns.circle.fill",
                    isExpanded: balanceSheetExpanded
                )
            }
            .buttonStyle(.plain)

            if balanceSheetExpanded {
                ForEach(BalanceSheetBucket.allCases) { bucket in
                    let accounts = orderedAccounts(for: bucket)
                    balanceGroupHeader(
                        bucket: bucket,
                        total: accountTotalsText(accounts),
                        count: accounts.count
                    )
                    if accounts.isEmpty {
                        Text("No matching \(bucket.title.lowercased()) accounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        accountHierarchyRows(accounts, bucket: bucket)
                    }
                }
            }
        } footer: {
            if balanceSheetExpanded {
                Text("Payments move automatically: positive balances are Receivables and negative balances are Payables. Native account nature remains unchanged.")
            }
        }
    }

    private func statementDisclosureHeader(
        title: String,
        subtitle: String,
        icon: String,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(AppTheme.purple)
                .frame(width: 18)
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.purple)
                .frame(width: 34, height: 34)
                .background(AppTheme.purple.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(isExpanded ? "Collapse" : "Show all")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.purple)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .textCase(nil)
    }

    private func statementGroupHeader(
        title: String,
        icon: String,
        total: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(title)
                .font(.subheadline.bold())
            Spacer()
            Text(total)
                .font(.caption.bold().monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
        }
        .padding(.vertical, 5)
        .listRowBackground(tint.opacity(0.055))
    }

    private func balanceGroupHeader(
        bucket: BalanceSheetBucket,
        total: String,
        count: Int
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bucket.icon)
                .foregroundStyle(AppTheme.blue)
                .frame(width: 30, height: 30)
                .background(AppTheme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.title)
                    .font(.subheadline.bold())
                Text("\(count) account\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(total)
                .font(.caption.bold().monospacedDigit())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
        }
        .padding(.vertical, 5)
        .listRowBackground(AppTheme.blue.opacity(0.045))
    }

    private func categoryRow(_ category: String, type: TransactionType) -> some View {
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
                        tint: type == .income ? AppTheme.green : AppTheme.red
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category).font(.body.weight(.semibold))
                        let code = store.chartCode(for: category, type: type)
                        Text(code.isEmpty
                            ? "\(transactionCount(category: category, type: type)) transactions"
                            : "\(code) · \(transactionCount(category: category, type: type)) transactions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(categoryTotalsText(category: category, type: type))
                        .font(.caption.bold().monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.62)
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

    @ViewBuilder
    private func accountHierarchyRows(
        _ accounts: [LedgerAccount],
        bucket: BalanceSheetBucket
    ) -> some View {
        ForEach(topLevelAccounts(in: accounts)) { account in
            let children = childAccounts(of: account, in: accounts)
            accountRow(
                account,
                bucket: bucket,
                children: children,
                isChild: false
            )

            if !children.isEmpty && expandedMainAccountIDs.contains(account.id) {
                ForEach(children) { child in
                    accountRow(
                        child,
                        bucket: bucket,
                        children: [],
                        isChild: true
                    )
                }
            }
        }
    }

    private func accountRow(
        _ account: LedgerAccount,
        bucket: BalanceSheetBucket,
        children: [LedgerAccount],
        isChild: Bool
    ) -> some View {
        HStack(spacing: 5) {
            if !children.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleMainAccount(account.id)
                    }
                } label: {
                    Image(systemName: expandedMainAccountIDs.contains(account.id)
                        ? "chevron.down"
                        : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.purple)
                        .frame(width: 25, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    expandedMainAccountIDs.contains(account.id)
                        ? "Collapse \(account.name) sub-accounts"
                        : "Expand \(account.name) sub-accounts"
                )
            } else {
                Color.clear
                    .frame(width: 25, height: 34)
            }

            NavigationLink {
                ChartLinkedTransactionsView(
                    title: account.name,
                    accountID: account.id,
                    category: nil,
                    type: nil
                )
                .environmentObject(store)
            } label: {
                ChartAccountRow(
                    account: account,
                    bucket: bucket,
                    parentName: store.account(withID: account.parentAccountID)?.name,
                    consolidatedTotals: store.consolidatedBalances(for: account),
                    subAccountCount: store.subAccounts(of: account.id).count
                )
                .environmentObject(store)
                .contentShape(Rectangle())
                .padding(.leading, isChild ? 6 : 0)
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
        .listRowInsets(EdgeInsets(
            top: 4,
            leading: isChild ? 28 : 16,
            bottom: 4,
            trailing: 16
        ))
        .listRowBackground(isChild ? AppTheme.purple.opacity(0.025) : Color.clear)
    }

    private func topLevelAccounts(in accounts: [LedgerAccount]) -> [LedgerAccount] {
        let ids = Set(accounts.map(\.id))
        return accounts.filter { account in
            guard let parentID = account.parentAccountID else { return true }
            return !ids.contains(parentID)
        }.sorted(by: accountSort)
    }

    private func childAccounts(
        of account: LedgerAccount,
        in accounts: [LedgerAccount]
    ) -> [LedgerAccount] {
        accounts.filter { $0.parentAccountID == account.id }
            .sorted(by: accountSort)
    }

    private func toggleMainAccount(_ accountID: UUID) {
        if expandedMainAccountIDs.contains(accountID) {
            expandedMainAccountIDs.remove(accountID)
        } else {
            expandedMainAccountIDs.insert(accountID)
        }
    }

    private func orderedAccounts(for bucket: BalanceSheetBucket) -> [LedgerAccount] {
        var items = store.activeAccounts.filter { effectiveBucket(for: $0) == bucket }
        if hideZeroBalanceAccounts {
            items = items.filter { !isEffectivelyZero($0) }
        }

        if !searchText.isEmpty {
            let directMatches = Set(items.filter(matchesSearch).map(\.id))
            var visibleIDs = directMatches
            for account in items {
                if let parentID = account.parentAccountID, directMatches.contains(account.id) {
                    visibleIDs.insert(parentID)
                }
                if let parentID = account.parentAccountID, directMatches.contains(parentID) {
                    visibleIDs.insert(account.id)
                }
            }
            items = items.filter { visibleIDs.contains($0.id) }
        }

        let mains = items.filter { $0.parentAccountID == nil }.sorted(by: accountSort)
        var ordered: [LedgerAccount] = []
        for main in mains {
            ordered.append(main)
            ordered.append(contentsOf: items.filter { $0.parentAccountID == main.id }.sorted(by: accountSort))
        }
        let included = Set(ordered.map(\.id))
        ordered.append(contentsOf: items.filter { !included.contains($0.id) }.sorted(by: accountSort))
        return ordered
    }

    private func effectiveBucket(for account: LedgerAccount) -> BalanceSheetBucket {
        if account.group == .payments {
            return directBucket(for: account)
        }
        if let parent = store.account(withID: account.parentAccountID) {
            return directBucket(for: parent)
        }
        return directBucket(for: account)
    }

    private func directBucket(for account: LedgerAccount) -> BalanceSheetBucket {
        let nature = account.nature ?? .unassigned
        if account.group == .payments {
            let current = store.balance(for: account)
            if current < 0 { return .payables }
            if current > 0 { return .receivables }
            return account.openingBalance < 0 ? .payables : .receivables
        }
        if nature == .loan || nature == .payable { return .payables }
        if nature == .receivable { return .receivables }
        if nature == .asset || account.group == .assets { return .assets }
        if nature == .bank || account.group == .qatar || account.group == .pakistan { return .bank }
        return .liabilitiesOther
    }

    private func accountSort(_ lhs: LedgerAccount, _ rhs: LedgerAccount) -> Bool {
        let left = lhs.chartCode ?? "9999"
        let right = rhs.chartCode ?? "9999"
        return left == right
            ? lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            : left.localizedStandardCompare(right) == .orderedAscending
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
            (account.chartCode ?? "").localizedCaseInsensitiveContains(searchText) ||
            (store.account(withID: account.parentAccountID)?.name.localizedCaseInsensitiveContains(searchText) ?? false)
    }

    private func isEffectivelyZero(_ account: LedgerAccount) -> Bool {
        let totals = account.parentAccountID == nil
            ? store.consolidatedBalances(for: account)
            : [account.currencyCode: store.balance(for: account)]
        return totals.values.allSatisfy { value in
            var input = value
            var rounded = Decimal.zero
            NSDecimalRound(&rounded, &input, 2, .plain)
            return rounded == 0
        }
    }

    private func transactionCount(category: String, type: TransactionType) -> Int {
        store.transactions.lazy.filter {
            $0.type == type && $0.category.caseInsensitiveCompare(category) == .orderedSame
        }.count
    }

    private func accountTotalsText(_ accounts: [LedgerAccount]) -> String {
        var totals: [String: Decimal] = [:]
        for account in accounts {
            totals[account.currencyCode.uppercased(), default: 0] += store.balance(for: account)
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
            totals[currency.uppercased(), default: 0] += amount
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

    private func classificationBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.42)
            .allowsTightening(true)
            .frame(width: 48, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ChartAccountRow: View {
    @EnvironmentObject private var store: LedgerStore
    let account: LedgerAccount
    let bucket: BalanceSheetBucket
    let parentName: String?
    let consolidatedTotals: [String: Decimal]
    let subAccountCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(bucket.badge)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.purple)
                .lineLimit(1)
                .minimumScaleFactor(0.42)
                .allowsTightening(true)
                .frame(width: 48, height: 30)
                .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if parentName != nil {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2.bold())
                            .foregroundStyle(AppTheme.purple)
                    }
                    Text(account.name)
                        .font(.body.weight(.semibold))
                }
                if let parentName {
                    Text("Sub-account of \(parentName) · \(account.currencyCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if subAccountCount > 0 {
                    Text("Main account · \(subAccountCount) sub-account\(subAccountCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(account.group.title) · \(account.currencyCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if parentName != nil || subAccountCount == 0 {
                    Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                } else {
                    ForEach(consolidatedTotals.keys.sorted(), id: \.self) { currency in
                        Text(DisplayFormat.currency(consolidatedTotals[currency] ?? 0, code: currency))
                    }
                    Text("Total incl. sub-accounts")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption.bold().monospacedDigit())
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .minimumScaleFactor(0.58)
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
