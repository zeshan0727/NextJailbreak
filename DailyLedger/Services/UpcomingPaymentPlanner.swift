import Foundation

/// Converts saved fixed expenses and real payment allocations into the
/// upcoming-payments display. This does not create transactions or infer
/// paid status from installment sequence numbers.
enum UpcomingPaymentPlanner {
    static func snapshot(
        plan: MonthlyFixedBudget,
        fixedSpending: [UUID: Decimal],
        currency: String,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> UpcomingPaymentsWidgetSnapshot {
        let cycleStart = BudgetCycle.start(containing: asOf, calendar: calendar)
        let interval = BudgetCycle.interval(start: cycleStart, calendar: calendar)
        let close = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let items: [UpcomingWidgetPayment] = plan
            .activeItems(.expense, in: cycleStart)
            .compactMap { item in
                let outstanding = max(Decimal.zero, item.amount - fixedSpending[item.id, default: 0])
                guard outstanding > 0 else { return nil }
                let due = dueDate(item: item, cycleStart: cycleStart, close: close,
                                  calendar: calendar)
                guard due >= interval.start && due < interval.end else { return nil }
                return UpcomingWidgetPayment(
                    id: item.id,
                    title: item.title,
                    remaining: outstanding,
                    dueDate: due,
                    hasSpecifiedDueDay: item.dueDay != nil
                )
            }
            .sorted {
                if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        return UpcomingPaymentsWidgetSnapshot(
            version: 1,
            generatedAt: asOf,
            cycleStart: interval.start,
            nextCycleStart: interval.end,
            currency: currency,
            payments: items
        )
    }

    /// For 26th–25th cycles, days 26–31 belong to the starting month and
    /// days 1–25 belong to the next month. Months with fewer days clamp.
    static func dueDate(
        item: FixedPlanItem,
        cycleStart: Date,
        close: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard let day = item.dueDay, (1...31).contains(day) else { return close }
        let monthAnchor: Date
        if day >= 26 {
            monthAnchor = cycleStart
        } else {
            monthAnchor = calendar.date(byAdding: .month, value: 1, to: cycleStart)!
        }
        let monthComponents = calendar.dateComponents([.year, .month], from: monthAnchor)
        let first = calendar.date(from: DateComponents(
            year: monthComponents.year, month: monthComponents.month, day: 1
        ))!
        let lastAvailableDay = calendar.range(of: .day, in: .month, for: first)!.count
        return calendar.date(from: DateComponents(
            year: monthComponents.year,
            month: monthComponents.month,
            day: min(day, lastAvailableDay)
        ))!
    }
}
