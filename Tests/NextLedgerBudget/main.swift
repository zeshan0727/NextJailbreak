import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
func check(_ condition: @autoclosure () -> Bool, _ detail: String) {
    guard condition() else { fatalError("Budget regression: \(detail)") }
}

check(BudgetCycle.start(containing: day(2026, 10, 25), calendar: calendar)
    == day(2026, 9, 26), "25th must belong to prior cycle")
check(BudgetCycle.start(containing: day(2026, 10, 26), calendar: calendar)
    == day(2026, 10, 26), "26th starts a new cycle")
check(BudgetCycle.interval(start: day(2026, 12, 26), calendar: calendar).end
    == day(2027, 1, 26), "December cycle crosses year")
check(BudgetCycle.interval(start: day(2028, 2, 26), calendar: calendar).end
    == day(2028, 3, 26), "February leap-year interval")

let salary = FixedPlanItem(kind: .income, title: "Salary",
    amount: 9000, firstCycle: day(2026, 10, 26), durationCycles: nil)
let short = FixedPlanItem(kind: .expense, title: "Instalment",
    amount: 1200, firstCycle: day(2026, 10, 26), durationCycles: 3)
let rent = FixedPlanItem(kind: .expense, title: "Rent",
    amount: 2500, firstCycle: day(2026, 10, 26), durationCycles: nil)
check(!short.isActive(in: day(2026, 10, 25), calendar: calendar), "not active before start")
check(short.isActive(in: day(2026, 10, 26), calendar: calendar), "active cycle 1")
check(short.isActive(in: day(2026, 12, 26), calendar: calendar), "active cycle 3")
check(!short.isActive(in: day(2027, 1, 26), calendar: calendar), "short term expires")
check(rent.isActive(in: day(2027, 1, 26), calendar: calendar), "ongoing continues")

var plan = MonthlyFixedBudget()
plan.items = [salary, short, rent]
check(plan.available(in: day(2026, 10, 26)) == 5300, "income minus scheduled expenses")
check(plan.available(in: day(2027, 1, 26)) == 6500, "expired expense releases funds")
plan.setAllocation(grocery: 45, fuel: 25, eatOut: 15, cycle: day(2026, 10, 26))
plan.setAllocation(grocery: 50, fuel: 20, eatOut: 10, cycle: day(2026, 11, 26))
check(plan.savedAllocation(in: day(2026, 10, 26))?.groceryPercent == 45,
    "old cycle allocations preserved")
check(plan.savedAllocation(in: day(2026, 11, 26))?.groceryPercent == 50,
    "new cycle allocations saved")
check(plan.otherPercent == 20, "unassigned is residual")
let encoded = try JSONEncoder().encode(plan)
let roundTrip = try JSONDecoder().decode(MonthlyFixedBudget.self, from: encoded)
check(roundTrip == plan, "backup persistence roundtrip")
print("Fixed budget regression checks passed")
