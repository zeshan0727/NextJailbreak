import SwiftUI

struct UncategorizedReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedCategory = "Restaurants & Cafes"
    @State private var categorySearch = ""
    @State private var skippedIDs: Set<UUID> = []
    @State private var splittingTransaction: LedgerTransaction?

    var body: some View {
        Group {
            if let transaction = currentTransaction {
                Form {
                    Section("Transaction") {
                        LabeledContent("Amount") {
                            Text(DisplayFormat.currency(transaction.amount, code: currencyCode(for: transaction)))
                                .fontWeight(.semibold)
                        }
                        LabeledContent("Date", value: transaction.date.formatted(date: .abbreviated, time: .shortened))
                        if let vendor = transaction.vendor, !vendor.isEmpty {
                            LabeledContent("Vendor", value: vendor)
                        }
                        if !transaction.details.isEmpty {
                            Text(transaction.details)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }

                    Section("Choose category") {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search categories", text: $categorySearch)
                        }

                        ForEach(filteredCategories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                HStack {
                                    Label(category, systemImage: AppTheme.categoryIcon(category))
                                    Spacer()
                                    if selectedCategory == category {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppTheme.green)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }

                        Button {
                            save(transaction)
                        } label: {
                            Label("Save Category", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Skip for Now") {
                            skippedIDs.insert(transaction.id)
                            prepareSelection()
                        }
                        Button {
                            splittingTransaction = transaction
                        } label: {
                            Label("Split Between Two Accounts", systemImage: "rectangle.split.2x1")
                                .font(.caption.weight(.semibold))
                        }
                        Button(role: .destructive) {
                            store.delete(transaction)
                            skippedIDs.remove(transaction.id)
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                        }
                    }
                }
                .onAppear { prepareSelection() }
                .onChange(of: currentTransaction?.id) { _ in prepareSelection() }
            } else {
                EmptyLedgerView(
                    title: "Review Complete",
                    message: skippedIDs.isEmpty
                        ? "Every transaction now has a category."
                        : "You reviewed all remaining transactions for this session."
                )
                .padding()
            }
        }
        .navigationTitle("Review Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $splittingTransaction) { transaction in
            SplitTransactionView(transaction: transaction)
                .environmentObject(store)
        }
    }

    private var currentTransaction: LedgerTransaction? {
        store.uncategorizedTransactions.first { !skippedIDs.contains($0.id) }
    }

    private var categories: [String] {
        store.categories(for: currentTransaction?.type ?? .expense).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var filteredCategories: [String] {
        let query = categorySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        return categories.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func prepareSelection() {
        guard let transaction = currentTransaction else { return }
        selectedCategory = store.suggestedCategory(for: transaction)
            ?? (transaction.type == .income ? "Salary" : "Restaurants & Cafes")
        categorySearch = ""
    }

    private func save(_ transaction: LedgerTransaction) {
        var updated = transaction
        updated.category = selectedCategory
        store.learnVendorCategory(from: transaction, category: selectedCategory)
        store.update(updated)
    }

    private func currencyCode(for transaction: LedgerTransaction) -> String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }
}
