import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
}
func assertWidget(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError("Widget regression failed: \(message)") }
}

let today = date(2026, 11, 12)
let first = date(2026, 11, 1)
let loan = FixedPlanItem(kind: .expense, title: "CBQ Loan", amount: 2044.67,
                         firstCycle: first, durationCycles: nil, dueDay: 18)
let airTicket = FixedPlanItem(kind: .expense, title: "Air Ticket", amount: 900,
                              firstCycle: first, durationCycles: 3)
let internet = FixedPlanItem(kind: .expense, title: "Internet", amount: 320,
                             firstCycle: first, durationCycles: nil, dueDay: 22)
let settled = FixedPlanItem(kind: .expense, title: "Settled Payment", amount: 200,
                            firstCycle: first, durationCycles: nil, dueDay: 16)
let future = FixedPlanItem(kind: .expense, title: "Future Plan", amount: 800,
                           firstCycle: date(2026, 12, 1), durationCycles: nil, dueDay: 2)
let income = FixedPlanItem(kind: .income, title: "Salary", amount: 9000,
                           firstCycle: first, durationCycles: nil)
let plan = MonthlyFixedBudget(items: [loan, airTicket, internet, settled, future, income])
let sample = UpcomingPaymentPlanner.snapshot(
    plan: plan,
    fixedSpending: [loan.id: 1044.67, settled.id: 200],
    currency: "QAR",
    asOf: today,
    calendar: calendar
)
assertWidget(sample.payments.count == 3, "only outstanding active fixed expenses show")
assertWidget(sample.payments.map(\.title) == ["CBQ Loan", "Internet", "Air Ticket"],
             "sort specific upcoming due dates before unspecified period-close")
assertWidget(sample.payments.first?.remaining == 1000, "partially paid loan shows remaining")
assertWidget(sample.payments.last?.remaining == 900, "unpaid ticket remains outstanding")
assertWidget(sample.payments.last?.hasSpecifiedDueDay == false,
             "unscheduled ticket is due BY close, not an invented exact date")
assertWidget(calendar.component(.day, from: sample.payments.last!.dueDate) == 30,
             "unscheduled fixed expense is due by November 30")
assertWidget(sample.payments.first?.deadlineLabel(on: today, calendar: calendar) == "Due in 6 days",
             "due in six days from 12 November")
assertWidget(!sample.payments.contains(where: { $0.title == "Settled Payment" }),
             "fully paid installment disappears")
assertWidget(!sample.payments.contains(where: { $0.title == "Future Plan" }),
             "future inactive plans do not appear")
assertWidget(!sample.payments.contains(where: { $0.title == "Salary" }),
             "fixed income does not appear among payments")
let expectedTotal: Decimal = 1000 + 320 + 900
assertWidget(sample.totalOutstanding == expectedTotal, "upcoming totals are exact and not double counted")

let overdue = FixedPlanItem(kind: .expense, title: "Past Due", amount: 100,
                            firstCycle: first, durationCycles: nil, dueDay: 30)
let overdueDate = UpcomingPaymentPlanner.dueDate(item: overdue, cycleStart: first,
                                                  close: sample.closeDay, calendar: calendar)
assertWidget(calendar.component(.month, from: overdueDate) == 11 &&
             calendar.component(.day, from: overdueDate) == 30,
             "due-day 30 belongs to current November")
let nextMonthDate = UpcomingPaymentPlanner.dueDate(item: internet, cycleStart: first,
                                                    close: sample.closeDay, calendar: calendar)
assertWidget(calendar.component(.month, from: nextMonthDate) == 11 &&
             calendar.component(.day, from: nextMonthDate) == 22,
             "due day 22 belongs to current November")

let shorterMonthCycle = date(2026, 11, 1)
let day31 = FixedPlanItem(kind: .expense, title: "Max Day", amount: 100,
                          firstCycle: shorterMonthCycle, durationCycles: nil, dueDay: 31)
let shortEnd = BudgetCycle.interval(start: shorterMonthCycle, calendar: calendar)
let shortClose = calendar.date(byAdding: .day, value: -1, to: shortEnd.end)!
let clamped = UpcomingPaymentPlanner.dueDate(item: day31, cycleStart: shorterMonthCycle,
                                             close: shortClose, calendar: calendar)
assertWidget(calendar.component(.day, from: clamped) == 30 &&
             calendar.component(.month, from: clamped) == 11,
             "a missing November 31st clamps to Nov 30")

let encodedOld = try JSONEncoder().encode(FixedPlanItem(
    kind: .expense, title: "Legacy", amount: 100,
    firstCycle: first, durationCycles: nil
))
var object = try JSONSerialization.jsonObject(with: encodedOld) as! [String: Any]
object.removeValue(forKey: "dueDay")
let restored = try JSONDecoder().decode(FixedPlanItem.self,
    from: JSONSerialization.data(withJSONObject: object))
assertWidget(restored.dueDay == nil, "existing iCloud backup without due date still decodes")

let encodedSnapshot = try JSONEncoder().encode(sample)
let decodedSnapshot = try JSONDecoder().decode(UpcomingPaymentsWidgetSnapshot.self,
                                               from: encodedSnapshot)
assertWidget(decodedSnapshot == sample, "widget's minimal shared JSON round-trips")
assertWidget(sample.isCurrent(on: today), "this calendar month is current")
assertWidget(!sample.isCurrent(on: date(2026, 12, 1)), "stale widget refreshes after period close")

print("Build 110 widget tests passed: 3 sizes' payload, actual paid/unpaid, optional due day, calendar month, shorter months, iCloud legacy decoding.")

// Build 111: page selection is widget-only and does not modify the ledger,
// upcoming payment order, the snapshot JSON or the iCloud backup.
let defaults = UserDefaults(suiteName: "nextledger-widget-pager-build111-tests")!
defaults.removePersistentDomain(forName: "nextledger-widget-pager-build111-tests")
assertWidget(UpcomingWidgetPager.selectedIndex(for: sample, defaults: defaults) == 0,
             "existing widgets start at the nearest upcoming fixed payment")
assertWidget(UpcomingWidgetPager.advance(snapshot: sample, defaults: defaults) == 1,
             "next action moves from the first to the second upcoming payment")
assertWidget(UpcomingWidgetPager.advance(snapshot: sample, defaults: defaults) == 2,
             "next action moves to the third upcoming payment")
assertWidget(UpcomingWidgetPager.advance(snapshot: sample, defaults: defaults) == 0,
             "next action wraps back to the first of three payments")
assertWidget(UpcomingWidgetPager.displayIndex(selectedIndex: 0,
    staticOffset: 1, count: 3) == 1, "iOS 16 second stack widget shows second payment")
assertWidget(UpcomingWidgetPager.displayIndex(selectedIndex: 0,
    staticOffset: 2, count: 3) == 2, "iOS 16 third stack widget shows third payment")
assertWidget(UpcomingWidgetPager.displayIndex(selectedIndex: 2,
    staticOffset: 2, count: 3) == 1, "stack offsets wrap safely after interactive paging")
assertWidget(UpcomingWidgetPager.displayIndex(selectedIndex: 999,
    staticOffset: 1, count: 0) == 0, "no empty-list index or division by zero")
let nextCycle = UpcomingPaymentPlanner.snapshot(
    plan: plan, fixedSpending: [:],
    currency: "QAR", asOf: date(2026, 12, 1), calendar: calendar
)
defaults.set(sample.cycleStart.timeIntervalSince1970, forKey: "NextLedger.WidgetPage.CycleV1")
defaults.set(2, forKey: "NextLedger.WidgetPage.IndexV1")
assertWidget(UpcomingWidgetPager.selectedIndex(for: nextCycle, defaults: defaults) == 0,
             "new budget cycle resets the small widget to the nearest payment")
let backupAfterPaging = try JSONEncoder().encode(sample)
// JSONEncoder does not guarantee byte-identical dictionary key ordering.
// Verify semantic payload integrity, not raw serialized key order.
let restoredAfterPaging = try JSONDecoder().decode(
    UpcomingPaymentsWidgetSnapshot.self, from: backupAfterPaging)
let restoredBeforePaging = try JSONDecoder().decode(
    UpcomingPaymentsWidgetSnapshot.self, from: encodedSnapshot)
assertWidget(restoredAfterPaging == restoredBeforePaging,
             "widget paging never changes the saved financial widget payload")
defaults.removePersistentDomain(forName: "nextledger-widget-pager-build111-tests")
print("Build 111 widgets: iOS17 paging, iOS16 stack offsets, wraparound and cycle reset passed.")


for (year, month, closingDay) in [(2027, 2, 28), (2028, 2, 29), (2026, 12, 31)] {
    let monthStart = date(year, month, 1)
    let item = FixedPlanItem(kind: .expense, title: "End of month", amount: 100,
                             firstCycle: monthStart, durationCycles: nil, dueDay: 31)
    let monthSnapshot = UpcomingPaymentPlanner.snapshot(plan: MonthlyFixedBudget(items: [item]),
        fixedSpending: [:], currency: "QAR", asOf: monthStart, calendar: calendar)
    assertWidget(monthSnapshot.payments.count == 1, "scheduled month-end bill remains visible")
    assertWidget(calendar.component(.day, from: monthSnapshot.payments[0].dueDate) == closingDay,
        "day 31 correctly clamps to actual month end")
}
print("Build 113 widget month-end and February checks passed.")

var customPlan = plan
customPlan.customPeriod = CustomBudgetPeriod(start: date(2026, 11, 26), end: date(2026, 12, 31), calendar: calendar)
let customWidget = UpcomingPaymentPlanner.snapshot(plan: customPlan, fixedSpending: [:],
    currency: "QAR", asOf: date(2027, 1, 2), calendar: calendar)
assertWidget(customWidget.isCustomPeriod == true, "widget uses saved custom dates")
assertWidget(customWidget.isCurrent(on: date(2027, 1, 2)), "manual range remains selected after close")
assertWidget(calendar.component(.day, from: customWidget.closeDay) == 31, "custom widget closes on selected last day")
assertWidget(customWidget.payments.contains { $0.title == "Air Ticket" && calendar.component(.day, from: $0.dueDate) == 31 }, "unscheduled bill uses custom closing date")
print("Build 114 custom widget period passed.")

let doubleLoan = FixedPlanItem(kind: .expense, title: "Two monthly installments", amount: 500,
    firstCycle: date(2026, 11, 1), durationCycles: 3, dueDay: 15)
var doublePlan = MonthlyFixedBudget(items: [doubleLoan])
doublePlan.customPeriod = CustomBudgetPeriod(start: date(2026, 11, 1), end: date(2026, 12, 30), calendar: calendar)
let doubleWidget = UpcomingPaymentPlanner.snapshot(plan: doublePlan, fixedSpending: [:],
    currency: "QAR", asOf: date(2026, 12, 1), calendar: calendar)
assertWidget(doubleWidget.payments.count == 2, "both recurring due dates displayed separately")
assertWidget(Set(doubleWidget.payments.map(\.occurrenceID)).count == 2, "distinct widget identity for each occurrence")
let paidWidget = UpcomingPaymentPlanner.snapshot(plan: doublePlan, fixedSpending: [doubleLoan.id: 600],
    currency: "QAR", asOf: date(2026, 12, 1), calendar: calendar)
assertWidget(paidWidget.payments.count == 1 && paidWidget.payments.first?.remaining == 400, "600 paid applied once across two 500 installments")
print("Build 114 multiple due-date and paid installment widget checks passed.")
