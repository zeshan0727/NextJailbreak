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
        let cycleStart = plan.reportPlanMonth(for: asOf, calendar: calendar)
        let interval = plan.reportInterval(for: asOf, calendar: calendar)
        let close = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        let items: [UpcomingWidgetPayment] = plan
            .activeItems(.expense, in: cycleStart)
            .compactMap { item in
                let outstanding = max(Decimal.zero, item.amount - fixedSpending[item.id, default: 0])
                guard outstanding > 0 else { return nil }
                let due = dueDate(item: item, cycleStart: cycleStart, close: close,
                                  calendar: calendar)
                // A fixed due date outside the selected range is not an upcoming payment.
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
