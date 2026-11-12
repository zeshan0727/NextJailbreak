import Foundation

/// Small, read-only projection shared between the main app and the WidgetKit
/// extension. Never move the full ledger, account numbers, or iCloud backup
/// into the widget container.
struct UpcomingWidgetPayment: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let remaining: Decimal
    let dueDate: Date
    let hasSpecifiedDueDay: Bool

    func daysUntilDue(on today: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                to: calendar.startOfDay(for: dueDate)).day ?? 0
    }

    func deadlineLabel(on today: Date = Date(), calendar: Calendar = .current) -> String {
        let days = daysUntilDue(on: today, calendar: calendar)
        if !hasSpecifiedDueDay {
            return "By " + dueDate.formatted(.dateTime.day().month(.abbreviated))
        }
        if days < 0 { return "Overdue " + dueDate.formatted(.dateTime.day().month(.abbreviated)) }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }
}

struct UpcomingPaymentsWidgetSnapshot: Codable, Equatable {
    let version: Int
    let generatedAt: Date
    let cycleStart: Date
    /// Exclusive end, the 26th at midnight in the local calendar.
    let nextCycleStart: Date
    let currency: String
    let payments: [UpcomingWidgetPayment]

    var totalOutstanding: Decimal {
        payments.reduce(.zero) { $0 + $1.remaining }
    }

    func isCurrent(on date: Date = Date()) -> Bool {
        cycleStart <= date && date < nextCycleStart
    }

    var closeDay: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: nextCycleStart) ?? nextCycleStart
    }
}

/// Widget and app may access the *same previously provisioned* iCloud Documents
/// container, avoiding any new App Group entitlement on the working app.
/// A separate Widget Extension provisioning profile is still required.
enum UpcomingPaymentsWidgetStorage {
    static let iCloudContainer = "iCloud.com.nextsolution.dailyledger"
    static let widgetKind = "NextLedgerUpcomingPayments"
    /// Small widgets 2 and 3 can be stacked with the original small widget.
    /// iOS 16 users swipe the Home Screen stack, not inside an individual widget.
    static let secondWidgetKind = "NextLedgerUpcomingPaymentTwo"
    static let thirdWidgetKind = "NextLedgerUpcomingPaymentThree"
    static let relativeFilename = "nextledger-upcoming-widget-v1.json"

    static func fileURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: iCloudContainer)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(relativeFilename)
    }

    static func load() -> UpcomingPaymentsWidgetSnapshot? {
        guard let location = fileURL(),
              let data = try? Data(contentsOf: location) else { return nil }
        return try? JSONDecoder().decode(UpcomingPaymentsWidgetSnapshot.self, from: data)
    }

    /// Call off the main thread. Return false if the iCloud container is not
    /// available, or if the projection has not changed.
    @discardableResult
    static func save(_ snapshot: UpcomingPaymentsWidgetSnapshot) throws -> Bool {
        guard let destination = fileURL() else {
            throw NSError(domain: "NextLedgerWidget", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Next Ledger iCloud Documents container unavailable"
            ])
        }
        if let old = load(),
           old.cycleStart == snapshot.cycleStart,
           old.nextCycleStart == snapshot.nextCycleStart,
           old.currency == snapshot.currency,
           old.payments == snapshot.payments {
            return false
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let output = try JSONEncoder().encode(snapshot)
        try output.write(to: destination, options: [.atomic])
        return true
    }
}


/// Pure, deterministic page logic reused by WidgetKit's timeline provider
/// and the iOS 17+ AppIntent. This does not change ledger transactions.
enum UpcomingWidgetPager {
    static func displayIndex(selectedIndex: Int, staticOffset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let normalized = ((selectedIndex % count) + count) % count
        let offset = ((staticOffset % count) + count) % count
        return (normalized + offset) % count
    }

    static func nextIndex(current: Int, count: Int) -> Int {
        displayIndex(selectedIndex: current, staticOffset: 1, count: count)
    }

    /// Widget-extension preferences are independent of the main app and
    /// carry only an index and cycle, never account or transaction data.
    private static let cycleKey = "NextLedger.WidgetPage.CycleV1"
    private static let indexKey = "NextLedger.WidgetPage.IndexV1"

    static func selectedIndex(for snapshot: UpcomingPaymentsWidgetSnapshot,
                              defaults: UserDefaults = .standard) -> Int {
        guard defaults.object(forKey: cycleKey) != nil,
              defaults.double(forKey: cycleKey) == snapshot.cycleStart.timeIntervalSince1970
        else { return 0 }
        return displayIndex(selectedIndex: defaults.integer(forKey: indexKey),
                            staticOffset: 0,
                            count: snapshot.payments.count)
    }

    @discardableResult
    static func advance(snapshot: UpcomingPaymentsWidgetSnapshot,
                        defaults: UserDefaults = .standard) -> Int {
        guard snapshot.payments.count > 0 else { return 0 }
        let current = selectedIndex(for: snapshot, defaults: defaults)
        let next = nextIndex(current: current, count: snapshot.payments.count)
        defaults.set(snapshot.cycleStart.timeIntervalSince1970, forKey: cycleKey)
        defaults.set(next, forKey: indexKey)
        return next
    }
}
