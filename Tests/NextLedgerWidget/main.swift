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
let first = date(2026, 10, 26)
let loan = FixedPlanItem(kind: .expense, title: "CBQ Loan", amount: 2044.67,
                         firstCycle: first, durationCycles: nil, dueDay: 18)
let airTicket = FixedPlanItem(kind: .expense, title: "Air Ticket", amount: 900,
                              firstCycle: first, durationCycles: 3)
let internet = FixedPlanItem(kind: .expense, title: "Internet", amount: 320,
                             firstCycle: first, durationCycles: nil, dueDay: 22)
let settled = FixedPlanItem(kind: .expense, title: "Settled Payment", amount: 200,
                            firstCycle: first, durationCycles: nil, dueDay: 16)
let future = FixedPlanItem(kind: .expense, title: "Future Plan", amount: 800,
                           firstCycle: date(2026, 11, 26), durationCycles: nil, dueDay: 2)
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
assertWidget(calendar.component(.day, from: sample.payments.last!.dueDate) == 25,
             "unscheduled fixed expense is due by the 25th")
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
assertWidget(calendar.component(.month, from: overdueDate) == 10 &&
             calendar.component(.day, from: overdueDate) == 30,
             "due-day 30 belongs to starting October")
let nextMonthDate = UpcomingPaymentPlanner.dueDate(item: internet, cycleStart: first,
                                                    close: sample.closeDay, calendar: calendar)
assertWidget(calendar.component(.month, from: nextMonthDate) == 11 &&
             calendar.component(.day, from: nextMonthDate) == 22,
             "due day 22 belongs to following November")

let shorterMonthCycle = date(2026, 11, 26)
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
assertWidget(sample.isCurrent(on: today), "this salary cycle is current")
assertWidget(!sample.isCurrent(on: date(2026, 11, 26)), "stale widget refreshes after period close")

print("Build 110 widget tests passed: 3 sizes' payload, actual paid/unpaid, optional due day, 26–25 cycle, shorter months, iCloud legacy decoding.")
