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
check(report.budgetSpent == 3650, "fixed, essentials and automatically categorized Other spending")
check(report.outsideSpent == 0, "unmatched spending automatically uses the Other allocation")
check(report.remaining == 5350, "remaining reflects all categorized spending")
check(abs(report.remainingPercentage - (5350.0 / 9000.0 * 100)) < 0.001,
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
check(reclassified.outsideSpent == 0, "manual Other assignment leaves no outside spending")
check(reclassified.budgetSpent == 3650, "manual assignment moves spend without duplication")
check(reclassified.actualSpent == report.actualSpent, "classification cannot change real expense amount")

plan.spendAssignments[rentTxn] = BudgetSpendAssignment(kind: .fixed, fixedItemID: UUID())
let invalidFixed = BudgetPerformanceEngine.build(plan: plan, cycleStart: cycle,
    expenses: expenses, currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(invalidFixed.outsideSpent == 2500, "invalid fixed plan association is not counted as paid")
check(report.unassignedExpenses.isEmpty, "Other expenses are auto categorized and do not require review")
check(reclassified.unassignedExpenses.isEmpty, "manually classified expense remains outside review")
check(reclassified.assignedExpenses.count == 4, "auto and manually categorized expenses remain available for correction")

plan.spendAssignments[unmatched] = BudgetSpendAssignment(kind: .outside)
let manuallyOutside = BudgetPerformanceEngine.build(plan: plan, cycleStart: cycle,
    expenses: expenses, currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(manuallyOutside.outsideSpent == 2800, "explicit outside classification survives alongside invalid fixed mapping")
plan.spendAssignments[unmatched] = BudgetSpendAssignment(kind: .other)
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

func include(_ expense: Bool, _ transfer: Bool, _ sourceBank: Bool,
             _ sourcePayments: Bool, _ destinationPayments: Bool) -> Bool {
    BudgetPerformanceEngine.includesInSpending(
        isExpense: expense, isTransfer: transfer, sourceIsBank: sourceBank,
        sourceIsPayments: sourcePayments, destinationIsPayments: destinationPayments)
}
check(include(true, false, true, false, false), "ordinary expenses are counted")
check(!include(false, true, true, false, false), "bank-to-bank transfer is not spending")
check(include(false, true, true, false, true), "bank-to-Payments transfer is spending")
check(!include(false, true, false, true, true), "Payments-to-Payments is excluded")
check(!include(false, true, false, false, true), "non-bank source transfer is excluded")
check(!include(false, false, true, false, true), "income does not count as spending")

let noOtherPlan = MonthlyFixedBudget(
    items: [rent, income], groceryPercent: 45, fuelPercent: 25, eatOutPercent: 30)
let noOtherReport = BudgetPerformanceEngine.build(
    plan: noOtherPlan, cycleStart: cycle, expenses: expenses,
    currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(noOtherReport.outsideSpent == 300, "zero Other allocation never invents budget")
check(noOtherReport.unassignedExpenses.count == 1, "unbudgeted expense still requires review")
check(noOtherReport.outsideRecordedCategories.contains {
    $0.name == "Electronics" && $0.spent == 300
}, "outside budget shows original transaction category")

let uber = BudgetSpendRecord(id: UUID(), amount: 120, date: day(2026, 10, 28),
    category: "Taxi", vendor: "Uber", currencyCode: "QAR")
let otherTaxi = BudgetSpendRecord(id: UUID(), amount: 80, date: day(2026, 10, 29),
    category: "taxi", vendor: "Other Cab", currencyCode: "QAR")
let genericTransfer = BudgetSpendRecord(id: UUID(), amount: 400, date: day(2026, 10, 30),
    category: "Transfer", vendor: "Bank → Payments", currencyCode: "QAR",
    fixedMatchHint: "Rent")
let specificTaxiWithHint = BudgetSpendRecord(id: UUID(), amount: 30, date: day(2026, 10, 30),
    category: "Taxi", vendor: "Uber", currencyCode: "QAR", fixedMatchHint: "Rent")
let categoryReport = BudgetPerformanceEngine.build(plan: plan, cycleStart: cycle,
    expenses: [uber, otherTaxi, genericTransfer, specificTaxiWithHint],
    currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(categoryReport.otherRecordedCategories.count == 1,
    "case variants of Taxi are grouped into one original-category subtotal")
check(categoryReport.otherRecordedCategories.first?.spent == 230,
    "Uber taxi and another Taxi payment together consume Other allocation")
check(categoryReport.otherRecordedCategories.first?.transactionCount == 3,
    "grouped Taxi subtotal retains source transaction count")
check(categoryReport.expenses.first(where: { $0.id == uber.id })?.record.category == "Taxi",
    "Uber retains its original Taxi category")
check(categoryReport.expenses.first(where: { $0.id == genericTransfer.id })?.bucket == .fixed(rent.id),
    "generic Payments transfer can match fixed expense by destination hint")
check(categoryReport.expenses.first(where: { $0.id == specificTaxiWithHint.id })?.bucket == .other,
    "meaningful original Taxi category takes priority over destination hint")
check(categoryReport.unassignedExpenses.isEmpty,
    "original-category Other spending is automatically classified, no manual work")
check(categoryReport.budgetSpent == 630, "subtotals and fixed payments counted exactly once")
check(categoryReport.actualSpent == 630, "no duplication from category grouping")
print("Budget Performance Build 104: original category preservation, Uber Taxi, category totals, transfer hints, allocations, FX, JSON and boundaries passed.")
// Build 106: forecast stays separate from actuals and never multiplies already
// paid fixed installments as though they were daily variable spending.
let futureProjection = BudgetPerformanceEngine.projection(
    for: report, asOf: day(2026, 10, 25), calendar: calendar)
check(futureProjection.elapsedDays == 0, "forecast shows zero elapsed days before cycle")
check(futureProjection.forecast == report.totalBudget, "future cycle estimate starts at plan")
let activeProjection = BudgetPerformanceEngine.projection(
    for: report, asOf: day(2026, 11, 1), calendar: calendar)
check(activeProjection.elapsedDays == 7 && activeProjection.totalDays == 31,
      "26 Oct through 1 Nov is seven days in a 31 day salary cycle")
check(activeProjection.isEstimated, "active cycle forecast is explicitly estimated")
check(activeProjection.forecast > report.actualSpent,
      "active forecast covers unpaid fixed bills and ongoing variable pace")
let finalProjection = BudgetPerformanceEngine.projection(
    for: report, asOf: day(2026, 11, 26), calendar: calendar)
check(!finalProjection.isEstimated && finalProjection.forecast == report.actualSpent,
      "completed cycles show recorded actuals instead of invented forecasts")
check(finalProjection.elapsedDays == finalProjection.totalDays,
      "completed cycle progress is full")
print("Budget Performance Build 106: actual, forecast, salary-cycle boundaries and category invariants passed.")

// Build 109: an imported Gadgets expense remains in its recorded category,
// is explicitly Unassigned, and can be reassigned to an installment.
let gadgetID = UUID()
let gadget = spend(gadgetID, 1095, "Gadgets & Accessories", day(2026, 10, 30))
var importedPlan = MonthlyFixedBudget(items: [rent, income])
importedPlan.setAllocation(grocery: 45, fuel: 25, eatOut: 15, cycle: cycle)
importedPlan.spendAssignments[gadgetID] = BudgetSpendAssignment(kind: .unassigned)
let awaitingReview = BudgetPerformanceEngine.build(
    plan: importedPlan, cycleStart: cycle, expenses: [gadget],
    currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(awaitingReview.unassignedExpenses.map(\.id) == [gadgetID],
      "SMS auto-import remains pending even when an Other allocation is available")
check(awaitingReview.outsideSpent == 1095,
      "unassigned spend is visible in totals, not silently counted in a fixed plan")
check(awaitingReview.expenses.first?.record.category == "Gadgets & Accessories",
      "unassigned import preserves original recorded category")
importedPlan.spendAssignments[gadgetID] =
    BudgetSpendAssignment(kind: .fixed, fixedItemID: rent.id)
let installment = BudgetPerformanceEngine.build(
    plan: importedPlan, cycleStart: cycle, expenses: [gadget],
    currencyCode: "QAR", asOf: day(2026, 11, 1), calendar: calendar)
check(installment.unassignedExpenses.isEmpty, "manually mapped gadget installment leaves review")
check(installment.lines.first(where: { $0.title == "Rent" })?.spent == 1095,
      "manual fixed mapping counts paid installment")
check(installment.actualSpent == awaitingReview.actualSpent,
      "budget allocation never duplicates or changes original financial spending")
check(installment.expenses.first?.record.category == "Gadgets & Accessories",
      "mapping a gadget to an installment does not rewrite original category")
let importedJSON = try JSONEncoder().encode(importedPlan)
check(try JSONDecoder().decode(MonthlyFixedBudget.self, from: importedJSON) == importedPlan,
      "manual fixed mapping and imported review state persist through backups")
print("Build 109: imported review, per-transaction fixed installment, original category preservation and backup compatibility passed.")

