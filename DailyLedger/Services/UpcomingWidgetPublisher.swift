import Foundation
import WidgetKit

/// The app is the only writer. Publish a lightweight summary after ledger or
/// budget changes and at app activation; disk + iCloud work stays off the main
/// thread so widget updates never block scrolling or transaction entry.
@MainActor
enum UpcomingWidgetPublisher {
    static func publish(store: LedgerStore) {
        let today = Date()
        let report = store.performanceSnapshot(for: today)
        var paid: [UUID: Decimal] = [:]
        for line in report.lines where line.id.hasPrefix("fixed:") {
            if let id = UUID(uuidString: String(line.id.dropFirst("fixed:".count))) {
                paid[id] = line.spent
            }
        }
        let snapshot = UpcomingPaymentPlanner.snapshot(
            plan: store.fixedBudget,
            fixedSpending: paid,
            currency: store.currencyCode,
            asOf: today
        )
        DispatchQueue.global(qos: .utility).async {
            do {
                if try UpcomingPaymentsWidgetStorage.save(snapshot) {
                    WidgetCenter.shared.reloadTimelines(
                        ofKind: UpcomingPaymentsWidgetStorage.widgetKind
                    )
                }
            } catch {
                // iCloud can be unavailable while logged out or offline. The
                // main ledger must stay usable; refresh again at next activation.
            }
        }
    }
}
