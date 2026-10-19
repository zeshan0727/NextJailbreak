import SwiftUI

private enum PaymentBalanceClass: String, CaseIterable, Identifiable {
    case receivable
    case payable

    var id: String { rawValue }
    var pluralTitle: String { self == .receivable ? "Receivables" : "Payables" }
    var icon: String {
        self == .receivable
            ? "arrow.down.left.circle.fill"
            : "arrow.up.right.circle.fill"
    }
}

struct AccountsView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var editingAccount: LedgerAccount?
    @State private var addingAccount = false
    @State private var showingTransfer = false
    @State private var searchText = ""
    @AppStorage("AccountsHideZeroBalance") private var hideZeroBalanceAccounts = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showingTransfer = true
                    } label: {
                        Label("Transfer Between Accounts", systemImage: "arrow.left.arrow.right.circle.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.purple)
                    }
                    .disabled(store.activeAccounts.count < 2)
                }

                ForEach(AccountGroup.allCases) { group in
                    if group == .payments {
                        let receivables = paymentAccounts(.receivable)
                        let payables = paymentAccounts(.payable)
                        if !receivables.isEmpty || !payables.isEmpty {
                            Section {
                                paymentGroupHeader(.receivable, accounts: receivables)
                                if receivables.isEmpty {
                                    Text("No matching receivable accounts.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(receivables) { account in
                                        accountLink(account)
                                    }
                                }

                                paymentGroupHeader(.payable, accounts: payables)
                                if payables.isEmpty {
                                    Text("No matching payable accounts.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(payables) { account in
                                        accountLink(account)
                                    }
                                }
                            } header: {
                                HStack {
                                    Text("PAYMENTS")
                                    Spacer()
                                    Text(groupBalanceText(receivables + payables))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    } else {
                        let accounts = accounts(in: group)
                        if !accounts.isEmpty {
                            Section {
                                ForEach(accounts) { account in
                                    accountLink(account)
                                }
                            } header: {
                                HStack {
                                    Text(group.title.uppercased())
                                    Spacer()
                                    Text(groupBalanceText(accounts))
                                        .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Accounts")
            .searchable(text: $searchText, prompt: "Search accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        hideZeroBalanceAccounts.toggle()
                    } label: {
                        Image(systemName: hideZeroBalanceAccounts
                            ? "eye.slash.circle.fill"
                            : "eye.circle")
                    }
                    .tint(hideZeroBalanceAccounts ? AppTheme.purple : .primary)
                    .accessibilityLabel(hideZeroBalanceAccounts
                        ? "Show zero-balance accounts"
                        : "Hide zero-balance accounts")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { addingAccount = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add account")
                }
            }
            .sheet(isPresented: $addingAccount) {
                AccountEditorView()
                    .environmentObject(store)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorView(account: account)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingTransfer) {
                TransferView()
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private func accountLink(_ account: LedgerAccount) -> some View {
        NavigationLink {
            AccountDetailView(accountID: account.id)
        } label: {
            AccountRow(
                account: account,
                ownBalance: store.balance(for: account),
                parentName: store.account(withID: account.parentAccountID)?.name,
                consolidatedTotals: store.consolidatedBalances(for: account),
                subAccountCount: store.subAccounts(of: account.id, includeArchived: true).count
            )
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                editingAccount = account
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(AppTheme.blue)
        }
    }

    private func paymentClass(for account: LedgerAccount) -> PaymentBalanceClass {
        let current = store.balance(for: account)
        if current < 0 { return .payable }
        if current > 0 { return .receivable }
        return account.openingBalance < 0 ? .payable : .receivable
    }

    private func paymentAccounts(_ type: PaymentBalanceClass) -> [LedgerAccount] {
        accounts(in: .payments).filter { paymentClass(for: $0) == type }
    }

    private func paymentGroupHeader(
        _ type: PaymentBalanceClass,
        accounts: [LedgerAccount]
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: type.icon)
                .foregroundStyle(type == .receivable ? AppTheme.green : AppTheme.orange)
                .frame(width: 30, height: 30)
                .background(
                    (type == .receivable ? AppTheme.green : AppTheme.orange).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(type.pluralTitle)
                    .font(.subheadline.bold())
                Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(groupBalanceText(accounts))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
        }
        .padding(.vertical, 5)
        .listRowBackground(
            (type == .receivable ? AppTheme.green : AppTheme.orange).opacity(0.055)
        )
    }

    private func accounts(in group: AccountGroup) -> [LedgerAccount] {
        let matching = store.activeAccounts.filter {
            guard $0.group == group else { return false }
            guard !hideZeroBalanceAccounts || shouldShowWithZeroFilter($0) else { return false }
            return searchText.isEmpty ||
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.currencyCode.localizedCaseInsensitiveContains(searchText) ||
                (store.account(withID: $0.parentAccountID)?.name.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        let mainAccounts = matching.filter { $0.parentAccountID == nil }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        var ordered: [LedgerAccount] = []
        for main in mainAccounts {
            ordered.append(main)
            ordered.append(contentsOf: matching.filter { $0.parentAccountID == main.id }.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        }
        let included = Set(ordered.map(\.id))
        ordered.append(contentsOf: matching.filter { !included.contains($0.id) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        return ordered
    }

    private func shouldShowWithZeroFilter(_ account: LedgerAccount) -> Bool {
        if account.parentAccountID != nil {
            return store.balance(for: account) != 0
        }
        if store.balance(for: account) != 0 {
            return true
        }
        return store.subAccounts(of: account.id).contains {
            store.balance(for: $0) != 0
        }
    }

    private func groupBalanceText(_ accounts: [LedgerAccount]) -> String {
        let grouped = Dictionary(grouping: accounts, by: \.currencyCode)
        return grouped.keys.sorted().map { code in
            let total = grouped[code, default: []].reduce(Decimal.zero) {
                $0 + store.balance(for: $1)
            }
            return DisplayFormat.currency(total, code: code)
        }.joined(separator: " · ")
    }
}

private struct AccountRow: View {
    let account: LedgerAccount
    let ownBalance: Decimal
    let parentName: String?
    let consolidatedTotals: [String: Decimal]
    let subAccountCount: Int

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: account.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(parentName == nil ? AppTheme.blue : AppTheme.purple)
                .frame(width: 40, height: 40)
                .background(
                    (parentName == nil ? AppTheme.blue : AppTheme.purple).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12)
                )
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
                    Text(account.currencyCode)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if parentName != nil || subAccountCount == 0 {
                    Text(DisplayFormat.currency(ownBalance, code: account.currencyCode))
                        .foregroundStyle(ownBalance < 0 ? AppTheme.red : .primary)
                } else {
                    ForEach(consolidatedTotals.keys.sorted(), id: \.self) { currency in
                        let amount = consolidatedTotals[currency] ?? 0
                        Text(DisplayFormat.currency(amount, code: currency))
                            .foregroundStyle(amount < 0 ? AppTheme.red : .primary)
                    }
                    Text("Total incl. sub-accounts")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.bold().monospacedDigit())
            .multilineTextAlignment(.trailing)
            .lineLimit(2)
            .minimumScaleFactor(0.58)
        }
        .padding(.vertical, 4)
    }
}

private struct AccountDetailView: View {
    @EnvironmentObject private var store: LedgerStore
    let accountID: UUID
    @State private var editingTransaction: LedgerTransaction?
    @State private var addingExpense = false
    @State private var addingIncome = false
    @State private var transferring = false
    @State private var searchText = ""

    var body: some View {
        List {
            if let account {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(hasSubAccounts ? "CONSOLIDATED BALANCE" : "CURRENT BALANCE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        ForEach(consolidatedBalanceCodes, id: \.self) { currency in
                            Text(DisplayFormat.currency(
                                consolidatedBalances[currency] ?? 0,
                                code: currency
                            ))
                            .font(.system(size: consolidatedBalanceCodes.count > 1 ? 23 : 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        }
                        if hasSubAccounts {
                            Text("Includes this account and \(subAccounts.count) direct sub-account\(subAccounts.count == 1 ? "" : "s")")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(AppTheme.balanceGradient, in: RoundedRectangle(cornerRadius: 20))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Actions") {
                    Button { addingExpense = true } label: {
                        Label("Add Expense", systemImage: "minus.circle.fill")
                    }
                    Button { addingIncome = true } label: {
                        Label("Add Income", systemImage: "plus.circle.fill")
                    }
                    Button { transferring = true } label: {
                        Label("Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                    }
                }
            }

            Section("Transactions") {
                if transactions.isEmpty {
                    Text("No transactions in this account.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(transactions) { transaction in
                        Button { editingTransaction = transaction } label: {
                            TransactionRow(transaction: transaction, accountID: accountID)
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
                    }
                }
            }
        }
        .navigationTitle(account?.name ?? "Account")
        .searchable(text: $searchText, prompt: "Search transactions")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                AccountStatementDownloadButton(accountID: accountID)
            }
        }
        .sheet(isPresented: $addingExpense) {
            AddTransactionView(initialType: .expense, accountID: accountID)
                .environmentObject(store)
        }
        .sheet(isPresented: $addingIncome) {
            AddTransactionView(initialType: .income, accountID: accountID)
                .environmentObject(store)
        }
        .sheet(isPresented: $transferring) {
            TransferView(sourceAccountID: accountID)
                .environmentObject(store)
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
    }

    private var account: LedgerAccount? { store.account(withID: accountID) }

    private var subAccounts: [LedgerAccount] {
        store.subAccounts(of: accountID, includeArchived: true)
    }

    private var hasSubAccounts: Bool {
        !subAccounts.isEmpty
    }

    private var consolidatedBalances: [String: Decimal] {
        guard let account else { return [:] }
        return store.consolidatedBalances(for: account)
    }

    private var consolidatedBalanceCodes: [String] {
        consolidatedBalances.keys.sorted()
    }

    private var relatedAccountIDs: Set<UUID> {
        store.relatedAccountIDs(for: accountID)
    }

    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            let belongs = $0.accountID.map(relatedAccountIDs.contains) == true ||
                $0.destinationAccountID.map(relatedAccountIDs.contains) == true
            guard belongs, !searchText.isEmpty else { return belongs }
            return $0.category.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText)
        }
    }
}

struct AccountEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currencyCode = "QAR"
    @State private var group: AccountGroup = .qatar
    @State private var icon = "creditcard.fill"
    @State private var openingBalance = "0"
    @State private var nature: AccountNature = .unassigned
    @State private var chartCode = ""
    @State private var parentAccountID: UUID?
    private let account: LedgerAccount?
    private let onSaved: ((LedgerAccount) -> Void)?

    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]
    private let icons = ["creditcard.fill", "banknote.fill", "wallet.pass.fill", "building.columns.fill", "car.fill", "house.fill", "person.2.fill", "iphone.gen3"]

    init(
        account: LedgerAccount? = nil,
        initialGroup: AccountGroup? = nil,
        initialCurrency: String? = nil,
        initialParentAccountID: UUID? = nil,
        onSaved: ((LedgerAccount) -> Void)? = nil
    ) {
        self.account = account
        self.onSaved = onSaved
        _name = State(initialValue: account?.name ?? "")
        _currencyCode = State(initialValue: account?.currencyCode ?? initialCurrency ?? "QAR")
        _group = State(initialValue: account?.group ?? initialGroup ?? .qatar)
        _icon = State(initialValue: account?.icon ?? "creditcard.fill")
        _openingBalance = State(initialValue: account.map {
            NSDecimalNumber(decimal: $0.openingBalance).stringValue
        } ?? "0")
        _nature = State(initialValue: account?.nature ?? .unassigned)
        _chartCode = State(initialValue: account?.chartCode ?? "")
        _parentAccountID = State(initialValue: account?.parentAccountID ?? initialParentAccountID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Chart of accounts code", text: $chartCode)
                        .keyboardType(.numberPad)
                    TextField("Name", text: $name)
                    Picker("Currency", selection: $currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Group", selection: $group) {
                        ForEach(AccountGroup.allCases) { Text($0.title).tag($0) }
                    }
                    .disabled(parentAccountID != nil)
                    Picker("Parent Account", selection: $parentAccountID) {
                        Text("Main Account (No Parent)").tag(Optional<UUID>.none)
                        ForEach(parentCandidates) { candidate in
                            Text("\(candidate.name) · \(candidate.group.title)")
                                .tag(Optional(candidate.id))
                        }
                    }
                    .disabled(hasSubAccounts)
                    if hasSubAccounts {
                        Text("This account already has sub-accounts, so it must remain a main account.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let parent = selectedParent {
                        Text("This sub-account will appear under \(parent.name). Its currency and opening balance remain independent.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Account Nature", selection: $nature) {
                        ForEach(AccountNature.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Icon", selection: $icon) {
                        ForEach(icons, id: \.self) { value in
                            Label(value.replacingOccurrences(of: ".fill", with: ""), systemImage: value)
                                .tag(value)
                        }
                    }
                    TextField("Opening balance", text: $openingBalance)
                        .keyboardType(.numbersAndPunctuation)
                }

                if let account {
                    Section {
                        Button("Archive Account", role: .destructive) {
                            store.archiveAccount(account)
                            dismiss()
                        }
                    } footer: {
                        Text("Existing transactions remain available after archiving.")
                    }
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .onChange(of: parentAccountID) { _ in
                if let parent = selectedParent {
                    group = parent.group
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(cleanedName.isEmpty || parsedOpeningBalance == nil)
                }
            }
        }
    }

    private var cleanedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var parentCandidates: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.parentAccountID == nil && $0.id != account?.id
        }.sorted {
            if $0.group != $1.group { return $0.group.title < $1.group.title }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var selectedParent: LedgerAccount? {
        store.account(withID: parentAccountID)
    }

    private var hasSubAccounts: Bool {
        guard let account else { return false }
        return store.accounts.contains { $0.parentAccountID == account.id }
    }

    private var parsedOpeningBalance: Decimal? {
        Decimal(
            string: openingBalance.replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func save() {
        guard let balance = parsedOpeningBalance else { return }
        if var account {
            account.name = cleanedName
            account.currencyCode = currencyCode
            account.group = group
            account.icon = icon
            account.openingBalance = balance
            account.nature = nature == .unassigned ? nil : nature
            account.chartCode = cleanedChartCode.nilIfEmpty
            account.parentAccountID = hasSubAccounts ? nil : parentAccountID
            if let parent = store.account(withID: account.parentAccountID) {
                account.group = parent.group
            }
            store.updateAccount(account)
            onSaved?(account)
        } else {
            var newAccount = LedgerAccount(
                name: cleanedName,
                currencyCode: currencyCode,
                group: group,
                icon: icon,
                openingBalance: balance,
                nature: nature == .unassigned ? nil : nature,
                chartCode: cleanedChartCode.nilIfEmpty,
                parentAccountID: parentAccountID
            )
            if let parent = store.account(withID: parentAccountID) {
                newAccount.group = parent.group
            }
            store.addAccount(newAccount)
            onSaved?(newAccount)
        }
        dismiss()
    }

    private var cleanedChartCode: String {
        chartCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
