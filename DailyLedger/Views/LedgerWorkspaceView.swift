import SwiftUI

/// Keeps every original financial screen accessible while matching the 5-tab
/// reference navigation: Home / Budget / Ledger / Reports / Settings.
struct LedgerWorkspaceView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case accounts = "Accounts"
        case transactions = "Transactions"
        case insights = "AI"
        var id: String { rawValue }
    }

    @State private var section: Section = .accounts
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("Ledger area", selection: $section) {
                ForEach(Section.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color(uiColor: .systemBackground))

            Group {
                switch section {
                case .accounts:
                    AccountsView()
                case .transactions:
                    TransactionsView(onAdd: onAdd, onTransfer: onTransfer)
                case .insights:
                    InsightsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
