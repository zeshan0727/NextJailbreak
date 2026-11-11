import SwiftUI

enum AppTab: String, Hashable, CaseIterable {
    case home, budget, ledger, reports, settings

    var title: String {
        switch self {
        case .home: return "Home"
        case .budget: return "Budget"
        case .ledger: return "Ledger"
        case .reports: return "Reports"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .budget: return "chart.pie.fill"
        case .ledger: return "list.bullet.rectangle"
        case .reports: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct AddSheet: Identifiable {
    let id = UUID()
    let type: TransactionType
}

struct AppRootView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home
    @State private var addSheet: AddSheet?
    @State private var showingTransfer = false
    @AppStorage("DailyLedgerTabOrder") private var tabOrder = LedgerTabOrder.defaultValue

    var body: some View {
        VStack(spacing: 0) {
            PersistentTabHost(
                selectedTab: $selectedTab,
                store: store,
                onAdd: presentAdd,
                onTransfer: { showingTransfer = true }
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                ForEach(LedgerTabOrder.resolve(tabOrder), id: \.self) { tab in
                    Button {
                        select(tab)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(tab.title)
                                .font(.caption2.weight(.medium))
                            Capsule()
                                .fill(selectedTab == tab ? Color(red: 0.21, green: 0.26, blue: 0.94) : .clear)
                                .frame(width: 30, height: 2)
                        }
                        .foregroundStyle(selectedTab == tab ? Color(red: 0.21, green: 0.26, blue: 0.94) : .secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 5)
            .background(.ultraThinMaterial)
        }
        .sheet(item: $addSheet) { sheet in
            AddTransactionView(initialType: sheet.type)
                .environmentObject(store)
        }
        .sheet(isPresented: $showingTransfer) {
            TransferView()
                .environmentObject(store)
        }
        .onAppear(perform: consumeShortcutRequest)
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            store.reload()
            consumeShortcutRequest()
        }
        .alert("Next Ledger", isPresented: errorBinding) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .overlay(alignment: .top) {
            if let transaction = store.recordingCards.first {
                RecordingSuccessCard(transaction: transaction) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.dismissRecordingCard(transaction.id)
                    }
                }
                .id(transaction.id)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(20)
            }
        }
    }

    private func select(_ tab: AppTab) {
        selectedTab = tab
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private func presentAdd(_ type: TransactionType) {
        addSheet = AddSheet(type: type)
    }

    private func consumeShortcutRequest() {
        guard let type = ShortcutRouter.consumePendingType() else { return }
        selectedTab = .home
        addSheet = AddSheet(type: type)
    }
}

private struct RecordingSuccessCard: View {
    @EnvironmentObject private var store: LedgerStore
    let transaction: LedgerTransaction
    let onDismiss: () -> Void
    @State private var offset: CGFloat = 0
    @State private var opacity = 1.0
    @State private var dismissing = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(AppTheme.green, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Transaction Recorded")
                    .font(.headline)
                Text(transaction.vendor ?? transaction.category)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(
                    DisplayFormat.currency(transaction.amount, code: currencyCode) +
                    " · " + transaction.date.formatted(date: .abbreviated, time: .shortened)
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "hand.draw.fill")
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.green.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
        .offset(x: offset)
        .opacity(opacity)
        .rotationEffect(.degrees(Double(offset / 35)))
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { offset = $0.translation.width }
                .onEnded {
                    if abs($0.translation.width) > 80 {
                        dismiss(toward: $0.translation.width)
                    } else {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { offset = 0 }
                    }
                }
        )
        .allowsHitTesting(!dismissing)
        .accessibilityAction(named: "Dismiss") { dismiss(toward: 500) }
    }

    private var currencyCode: String {
        store.account(withID: transaction.accountID)?.currencyCode ?? store.currencyCode
    }

    private func dismiss(toward translation: CGFloat) {
        guard !dismissing else { return }
        dismissing = true
        withAnimation(.easeOut(duration: 0.2)) {
            offset = translation < 0 ? -600 : 600
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) {
            onDismiss()
        }
    }
}
