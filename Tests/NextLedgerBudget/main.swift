import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
func check(_ condition: @autoclosure () -> Bool, _ detail: String) {
    guard condition() else { fatalError("Budget regression: \(detail)") }
}

check(BudgetCycle.start(containing: day(2026, 10, 31), calendar: calendar)
    == day(2026, 10, 1), "31st stays in October")
check(BudgetCycle.start(containing: day(2026, 11, 1), calendar: calendar)
    == day(2026, 11, 1), "1st starts a new month")
check(BudgetCycle.interval(start: day(2026, 12, 1), calendar: calendar).end
    == day(2027, 1, 1), "December crosses year")
check(BudgetCycle.interval(start: day(2028, 2, 29), calendar: calendar).end
    == day(2028, 3, 1), "February leap-year interval")
check(BudgetCycle.interval(start: day(2027, 2, 28), calendar: calendar).duration == 28 * 86400,
    "ordinary February closes on the 28th")
check(BudgetCycle.interval(start: day(2026, 11, 30), calendar: calendar).end
    == day(2026, 12, 1), "November closes on the 30th")
check(BudgetCycle.storedStart(day(2026, 10, 26), calendar: calendar) == day(2026, 11, 1),
    "legacy 26 October anchor belongs to November closing month")

let salary = FixedPlanItem(kind: .income, title: "Salary",
    amount: 9000, firstCycle: day(2026, 10, 1), durationCycles: nil)
let short = FixedPlanItem(kind: .expense, title: "Instalment",
    amount: 1200, firstCycle: day(2026, 10, 1), durationCycles: 3)
let rent = FixedPlanItem(kind: .expense, title: "Rent",
    amount: 2500, firstCycle: day(2026, 10, 1), durationCycles: nil)
check(!short.isActive(in: day(2026, 9, 30), calendar: calendar), "not active before start")
check(short.isActive(in: day(2026, 10, 1), calendar: calendar), "active cycle 1")
check(short.isActive(in: day(2026, 12, 1), calendar: calendar), "active cycle 3")
check(!short.isActive(in: day(2027, 1, 1), calendar: calendar), "short term expires")
check(rent.isActive(in: day(2027, 1, 1), calendar: calendar), "ongoing continues")

var plan = MonthlyFixedBudget()
plan.items = [salary, short, rent]
check(plan.available(in: day(2026, 10, 1)) == 5300, "income minus scheduled expenses")
check(plan.available(in: day(2027, 1, 1)) == 6500, "expired expense releases funds")
plan.setAllocation(grocery: 45, fuel: 25, eatOut: 15, cycle: day(2026, 10, 1))
plan.setAllocation(grocery: 50, fuel: 20, eatOut: 10, cycle: day(2026, 11, 1))
check(plan.savedAllocation(in: day(2026, 10, 1))?.groceryPercent == 45,
    "old cycle allocations preserved")
check(plan.savedAllocation(in: day(2026, 11, 1))?.groceryPercent == 50,
    "new cycle allocations saved")
check(plan.otherPercent == 20, "unassigned is residual")
let encoded = try JSONEncoder().encode(plan)
let roundTrip = try JSONDecoder().decode(MonthlyFixedBudget.self, from: encoded)
check(roundTrip == plan, "backup persistence roundtrip")
print("Fixed budget regression checks passed")

// Legacy anchors remain unchanged in backups, with installments interpreted
// in their original closing month.
let legacy = FixedPlanItem(kind: .expense, title: "Legacy installment", amount: 100,
    firstCycle: day(2026, 10, 26), durationCycles: 2)
check(!legacy.isActive(in: day(2026, 10, 31), calendar: calendar), "legacy first closing month is November")
check(legacy.isActive(in: day(2026, 11, 1), calendar: calendar), "legacy first installment preserved")
check(legacy.isActive(in: day(2026, 12, 31), calendar: calendar), "legacy second installment preserved")
check(!legacy.isActive(in: day(2027, 1, 1), calendar: calendar), "legacy installment ends as expected")
check(legacy.finalDay(calendar: calendar) == day(2026, 12, 31), "legacy final month ends on actual last day")
var oldPlan = MonthlyFixedBudget(items: [legacy], cycleAllocations: [
    SavedCycleBudget(cycleStart: day(2026, 10, 26), groceryPercent: 40, fuelPercent: 20, eatOutPercent: 10)
])
check(oldPlan.savedAllocation(in: day(2026, 11, 15))?.groceryPercent == 40, "old allocation maps to closing month")
oldPlan.setAllocation(grocery: 50, fuel: 20, eatOut: 10, cycle: day(2026, 11, 30))
check(oldPlan.cycleAllocations.count == 1, "no duplicate allocation after month transition")
check(oldPlan.savedAllocation(in: day(2026, 11, 1))?.groceryPercent == 50, "updated calendar allocation")
print("Build 113 calendar month and legacy anchor migration passed.")

var customPlan = plan
customPlan.customPeriod = CustomBudgetPeriod(start: day(2026, 11, 26), end: day(2026, 12, 31), calendar: calendar)
let customRange = customPlan.reportInterval(for: day(2027, 1, 15), calendar: calendar)
check(customRange.start == day(2026, 11, 26), "manual start survives beyond selected period")
check(customRange.end == day(2027, 1, 1), "closing date is inclusive")
check(customPlan.reportPlanMonth(for: day(2026, 11, 26), calendar: calendar) == day(2026, 12, 1), "fixed plans use closing month once")
check(CustomBudgetPeriod(start: day(2026, 12, 1), end: day(2026, 11, 30), calendar: calendar) == nil, "reject reversed dates")
let customRestored = try JSONDecoder().decode(MonthlyFixedBudget.self, from: JSONEncoder().encode(customPlan))
check(customRestored == customPlan, "custom date selection survives backup and restore")
check(roundTrip.customPeriod == nil, "old backup defaults to calendar month")
customPlan.customPeriod = nil
check(customPlan.reportInterval(for: day(2027, 1, 15), calendar: calendar).start == day(2027, 1, 1), "return to calendar month")
print("Build 114 custom period persistence and inclusive dates passed.")
