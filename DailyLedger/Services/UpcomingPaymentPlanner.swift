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
        let interval = plan.reportInterval(for: asOf, calendar: calendar)
        // Apply recorded fixed spending to the earliest scheduled occurrence
        // first, without counting a payment more than once.
        var remainingPaid = fixedSpending
        let items: [UpcomingWidgetPayment] = plan.occurrences(.expense, for: asOf, calendar: calendar)
            .compactMap { occurrence in
                let item = occurrence.item
                let applied = min(item.amount, max(.zero, remainingPaid[item.id, default: 0]))
                remainingPaid[item.id, default: 0] -= applied
                let outstanding = item.amount - applied
                guard outstanding > 0 else { return nil }
                return UpcomingWidgetPayment(
                    id: item.id, title: item.title, remaining: outstanding,
                    dueDate: occurrence.dueDate, hasSpecifiedDueDay: item.dueDay != nil
                )
            }
        return UpcomingPaymentsWidgetSnapshot(
            version: 3,
            generatedAt: asOf,
            cycleStart: interval.start,
            nextCycleStart: interval.end,
            currency: currency,
            payments: items,
            isCustomPeriod: plan.customPeriod?.interval(calendar: calendar) != nil
        )
    }

    /// All due days belong to the selected calendar month. Short months clamp.
    static func dueDate(
        item: FixedPlanItem,
        cycleStart: Date,
        close: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard let day = item.dueDay, (1...31).contains(day) else { return close }
        let monthComponents = calendar.dateComponents([.year, .month], from: cycleStart)
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
