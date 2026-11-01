import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}
func check(_ ok: @autoclosure () -> Bool, _ reason: String) {
    if !ok() { fatalError("Budget performance regression failure: \(reason)") }
}

let cycle = day(2026, 10, 26)
let rent = FixedPlanItem(kind: .expense, title: "Rent", amount: 2500,
                         firstCycle: cycle, durationCycles: nil)
let income = FixedPlanItem(kind: .income, title: "Salary", amount: 9000,
                           firstCycle: cycle, durationCycles: nil)
var plan = MonthlyFixedBudget(items: [rent, income])
plan.setAllocation(grocery: 45, fuel: 25, eatOut: 15, cycle: cycle)
let rentTxn = UUID(), groceries = UUID(), fuel = UUID(), unmatched = UUID()
func spend(_ id: UUID, _ amount: Decimal, _ category: String, _ date: Date,
           _ currency: String = "QAR") -> BudgetSpendRecord {
    BudgetSpendRecord(id: id, amount: amount, date: date, category: category,
                      vendor: nil, currencyCode: currency)
}
let expenses: [BudgetSpendRecord] = [
    spend(rentTxn, 2500, "Rent", day(2026, 10, 27)),
    spend(groceries, 700, "Grocery", day(2026, 10, 28)),
    spend(fuel, 150, "Fuel", day(2026, 10, 28)),
    spend(unmatched, 300, "Electronics", day(2026, 10, 29)),
    spend(UUID(), 600, "Rent", day(2026, 10, 25)), // prior cycle
    spend(UUID(), 350, "Grocery", day(2026, 11, 26)), // next cycle
    spend(UUID(), 950, "Grocery", day(2026, 10, 29), "PKR"), // other currency
    spend(UUID(), 400, "Grocery", day(2026, 11, 20)) // future as-of
]
let report = BudgetPerformanceEngine.build(plan: plan, cycleStart: cycle,
    expenses: expenses, currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(report.totalBudget == 9000, "planned fixed plus 100% of remaining income")
check(report.budgetSpent == 3350, "fixed and essentials actual spending")
check(report.outsideSpent == 300, "unmatched expense belongs outside")
check(report.remaining == 5650, "remaining based on actual in-budget spending")
check(abs(report.remainingPercentage - (5650.0 / 9000.0 * 100)) < 0.001,
      "accurate remaining percentage")
check(report.actualSpent == 3650, "total paid including unplanned")
check(report.unconvertedByCurrency["PKR"] == 950, "never guess FX conversion")
check(report.expenses.count == 4, "exclude other cycles, other currencies and future expense")
check(report.usesSavedAllocations, "respect applied cycle percentages")
check(report.lines.first(where: { $0.title == "Rent" })?.spent == 2500,
      "exact matched fixed expense counted as paid")

plan.spendAssignments[unmatched] = BudgetSpendAssignment(kind: .other)
let reclassified = BudgetPerformanceEngine.build(plan: plan, cycleStart: cycle,
    expenses: expenses, currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(reclassified.outsideSpent == 0, "manual assignment removes outside spend")
check(reclassified.budgetSpent == 3650, "manual assignment moves spend without duplication")
check(reclassified.actualSpent == report.actualSpent, "classification cannot change real expense amount")

plan.spendAssignments[rentTxn] = BudgetSpendAssignment(kind: .fixed, fixedItemID: UUID())
let invalidFixed = BudgetPerformanceEngine.build(plan: plan, cycleStart: cycle,
    expenses: expenses, currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(invalidFixed.outsideSpent == 2500, "invalid fixed plan association is not counted as paid")
check(invalidFixed.actualSpent == report.actualSpent, "invalid mapping never discards spend")

let saved = try JSONEncoder().encode(plan)
let restored = try JSONDecoder().decode(MonthlyFixedBudget.self, from: saved)
check(restored == plan, "new assignments round-trip through ledger backup")

var old = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
old.removeValue(forKey: "spendAssignments")
let legacy = try JSONSerialization.data(withJSONObject: old)
let legacyRestored = try JSONDecoder().decode(MonthlyFixedBudget.self, from: legacy)
check(legacyRestored.spendAssignments.isEmpty, "older backup loads with absent mapping key")
check(legacyRestored.items.count == 2, "older budget plans remain intact")

let noPlan = BudgetPerformanceEngine.build(
    plan: MonthlyFixedBudget(), cycleStart: cycle, expenses: expenses,
    currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(noPlan.totalBudget == 0, "empty plan has no invented budget")
check(noPlan.outsideSpent == 3650, "all unplanned expenses shown outside when plan is empty")
check(noPlan.remainingPercentage == 0, "no division by zero")

print("Budget performance: 16 calculation, FX, date-boundary, classification and JSON compatibility checks passed.")
