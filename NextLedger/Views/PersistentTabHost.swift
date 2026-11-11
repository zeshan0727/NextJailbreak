import SwiftUI
import UIKit

struct PersistentTabHost: UIViewControllerRepresentable {
    @Binding var selectedTab: AppTab
    let store: LedgerStore
    let onAdd: (TransactionType) -> Void
    let onTransfer: () -> Void

    func makeUIViewController(context: Context) -> PersistentTabViewController {
        let controller = PersistentTabViewController()
        controller.install([
            .home: host(DashboardView(onAdd: onAdd, onTransfer: onTransfer)),
            .budget: host(NavigationStack { FixedBudgetDashboardView() }),
            .ledger: host(LedgerWorkspaceView(onAdd: onAdd, onTransfer: onTransfer)),
            .reports: host(ReportsView()),
            .settings: host(SettingsView())
        ])
        controller.show(selectedTab)
        return controller
    }

    func updateUIViewController(_ controller: PersistentTabViewController, context: Context) {
        controller.show(selectedTab)
    }

    private func host<Content: View>(_ content: Content) -> UIViewController {
        UIHostingController(rootView: content.environmentObject(store))
    }
}

final class PersistentTabViewController: UIViewController {
    private var controllers: [AppTab: UIViewController] = [:]
    private var visibleTab: AppTab?

    func install(_ controllers: [AppTab: UIViewController]) {
        guard self.controllers.isEmpty else { return }
        self.controllers = controllers
    }

    func show(_ tab: AppTab) {
        guard tab != visibleTab, let next = controllers[tab] else { return }

        if let visibleTab, let current = controllers[visibleTab] {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        addChild(next)
        next.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(next.view)
        NSLayoutConstraint.activate([
            next.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            next.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            next.view.topAnchor.constraint(equalTo: view.topAnchor),
            next.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        next.didMove(toParent: self)
        visibleTab = tab
    }
}
