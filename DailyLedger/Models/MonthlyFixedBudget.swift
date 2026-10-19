import Foundation

/// The personal budget month starts on the 26th and ends on the 25th (inclusive).
enum BudgetCycle {
    static func start(containing date: Date, calendar: Calendar = .current) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: startOfDay)
        let thisMonth26 = calendar.date(from: DateComponents(
            year: components.year, month: components.month, day: 26
        ))!
        return startOfDay >= thisMonth26
            ? thisMonth26
            : calendar.date(byAdding: .month, value: -1, to: thisMonth26)!
    }

    static func shifted(_ start: Date, by months: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: months, to: start(containing: start, calendar: calendar))!
    }

    static func interval(start: Date, calendar: Calendar = .current) -> DateInterval {
        let normalized = self.start(containing: start, calendar: calendar)
        return DateInterval(start: normalized, end: shifted(normalized, by: 1, calendar: calendar))
    }

    static func title(start: Date, calendar: Calendar = .current) -> String {
        let range = interval(start: start, calendar: calendar)
        let finalDay = calendar.date(byAdding: .day, value: -1, to: range.end)!
        let first = range.start.formatted(.dateTime.day().month(.abbreviated()))
        let last = finalDay.formatted(.dateTime.day().month(.abbreviated()))
        return "\(first) – \(last)"
    }
}

enum FixedPlanKind: String, Codable, CaseIterable, Identifiable {
    case income
    case expense

    var id: String { rawValue }
    var title: String { self == .income ? "Fixed Income" : "Fixed Expense" }
}

struct FixedPlanItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: FixedPlanKind
    var title: String
    var amount: Decimal
    var firstCycle: Date
    /// nil means ongoing; a positive value ends after exactly that many cycles.
    var durationCycles: Int?

    func isActive(in cycle: Date, calendar: Calendar = .current) -> Bool {
        let month = BudgetCycle.start(containing: cycle, calendar: calendar)
        let first = BudgetCycle.start(containing: firstCycle, calendar: calendar)
        guard month >= first else { return false }
        guard let durationCycles else { return true }
        guard durationCycles > 0 else { return false }
        let afterFinal = BudgetCycle.shift(first, by: durationCycles, calendar: calendar)
        return month < afterFinal
    }

    func elapsedCycles(through cycle: Date, calendar: Calendar = .current) -> Int {
        let first = BudgetCycle.start(containing: firstCycle, calendar: calendar)
        let current = BudgetCycle.start(containing: cycle, calendar: calendar)
        let components = calendar.dateComponents([.month], from: first, to: current)
        return max(0, (components.month ?? 0) + 1)
    }

    func finalDay(calendar: Calendar = .current) -> Date? {
        guard let durationCycles, durationCycles > 0 else { return nil }
        let nextCycle = BudgetCycle.shift(firstCycle, by: durationCycles, calendar: calendar)
        return calendar.date(byAdding: .day, value: -1, to: nextCycle)
    }
}

struct MonthlyFixedBudget: Codable, Equatable {
    var items: [FixedPlanItem] = []
    var groceryPercent: Int = 45
    var fuelPercent: Int = 25
    var eatOutPercent: Int = 15
    var appliedCycle: Date?

    var otherPercent: Int {
        max(0, 100 - groceryPercent - fuelPercent - eatOutPercent)
    }

    func activeItems(_ kind: FixedPlanKind, in cycle: Date) -> [FixedPlanItem] {
        items.filter { $0.kind == kind && $0.isActive(in: cycle) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func total(_ kind: FixedPlanKind, in cycle: Date) -> Decimal {
        activeItems(kind, in: cycle).reduce(Decimal.zero) { $0 + $1.amount }
    }

    func available(in cycle: Date) -> Decimal {
        total(.income, in: cycle) - total(.expense, in: cycle)
    }

    func allocation(_ percent: Int, in cycle: Date) -> Decimal {
        max(Decimal.zero, available(in: cycle)) * Decimal(percent) / 100
    }

    mutating func setAllocation(grocery: Int, fuel: Int, eatOut: Int, cycle: Date) {
        precondition(grocery >= 0 && fuel >= 0 && eatOut >= 0)
        precondition(grocery + fuel + eatOut <= 100)
        groceryPercent = grocery
        fuelPercent = fuel
        eatOutPercent = eatOut
        appliedCycle = BudgetCycle.start(containing: cycle)
    }
}
