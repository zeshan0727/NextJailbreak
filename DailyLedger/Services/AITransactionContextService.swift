import Foundation
import SwiftUI

@MainActor
final class AITransactionContextService: ObservableObject {
    static let shared = AITransactionContextService()
    static let fetchStep = 10

    @Published private(set) var loadedTransactionIDs: [UUID] = []
    @Published private(set) var initialized = false

    private init() {}

    func ensureDefault(from transactions: [LedgerTransaction]) {
        guard !initialized else { return }
        initialized = true
        fetchLatest10(from: transactions)
    }

    func fetchLatest10(from transactions: [LedgerTransaction]) {
        initialized = true
        loadedTransactionIDs = Array(sorted(transactions).prefix(Self.fetchStep).map(\.id))
    }

    func load10More(from transactions: [LedgerTransaction]) {
        initialized = true
        let ordered = sorted(transactions)
        let target = min(max(loadedTransactionIDs.count, 0) + Self.fetchStep, ordered.count)
        loadedTransactionIDs = Array(ordered.prefix(target).map(\.id))
    }

    func clear() {
        initialized = true
        loadedTransactionIDs = []
    }

    func transactions(from all: [LedgerTransaction]) -> [LedgerTransaction] {
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        return loadedTransactionIDs.compactMap { byID[$0] }
    }

    private func sorted(_ transactions: [LedgerTransaction]) -> [LedgerTransaction] {
        transactions.sorted {
            if $0.date == $1.date { return $0.id.uuidString > $1.id.uuidString }
            return $0.date > $1.date
        }
    }
}

struct AITransactionContextControls: View {
    @EnvironmentObject private var store: LedgerStore
    @ObservedObject private var context = AITransactionContextService.shared

    private var loadedCount: Int { context.loadedTransactionIDs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "tray.full.fill")
                    .foregroundStyle(AppTheme.purple)
                    .frame(width: 34, height: 34)
                    .background(AppTheme.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Transaction Data")
                        .font(.subheadline.weight(.semibold))
                    Text(loadedCount == 0 ? "No transaction data fetched" : "\(loadedCount) transaction\(loadedCount == 1 ? "" : "s") loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text("Only the fetched snapshot can be sent to server AI. The default is the latest 10 transactions. More data requires your action.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                if loadedCount == 0 {
                    Button {
                        context.fetchLatest10(from: store.transactions)
                    } label: {
                        Label("Fetch Latest 10", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else if loadedCount < store.transactions.count {
                    Button {
                        context.load10More(from: store.transactions)
                    } label: {
                        Label("Load 10 More", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                }

                if loadedCount > 0 {
                    Button(role: .destructive) {
                        context.clear()
                    } label: {
                        Label("Clear Fetched Data", systemImage: "trash.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
