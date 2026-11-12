import SwiftUI
import WidgetKit

private enum WidgetPalette {
    static let blue = Color(red: 0.20, green: 0.26, blue: 0.90)
    static let navy = Color(red: 0.08, green: 0.13, blue: 0.34)
    static let soft = Color(red: 0.94, green: 0.95, blue: 1.00)
    static let green = Color(red: 0.06, green: 0.56, blue: 0.37)
    static let grey = Color(red: 0.48, green: 0.51, blue: 0.60)
}

private struct UpcomingPaymentsEntry: TimelineEntry {
    let date: Date
    let snapshot: UpcomingPaymentsWidgetSnapshot?
}

private struct UpcomingPaymentsProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingPaymentsEntry {
        UpcomingPaymentsEntry(
            date: Date(),
            snapshot: UpcomingPaymentsWidgetSnapshot(
                version: 1, generatedAt: Date(),
                cycleStart: Calendar.current.startOfDay(for: Date()),
                nextCycleStart: Calendar.current.date(byAdding: .day, value: 12, to: Date())!,
                currency: "QAR",
                payments: [
                    UpcomingWidgetPayment(
                        id: UUID(), title: "Fixed payment", remaining: 900,
                        dueDate: Date().addingTimeInterval(86400 * 2),
                        hasSpecifiedDueDay: true
                    )
                ]
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingPaymentsEntry) -> Void) {
        completion(UpcomingPaymentsEntry(
            date: Date(), snapshot: UpcomingPaymentsWidgetStorage.load()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingPaymentsEntry>) -> Void) {
        let now = Date()
        let snapshot = UpcomingPaymentsWidgetStorage.load()
        let entry = UpcomingPaymentsEntry(date: now, snapshot: snapshot)
        // WidgetKit controls the final refresh time. Timelines also reload
        // proactively after an expense or budget update in the main app.
        let nextMidnight = Calendar.current.nextDate(
            after: now, matching: DateComponents(hour: 0, minute: 0, second: 10),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(86400)
        let refresh = min(nextMidnight, now.addingTimeInterval(60 * 30))
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct NextLedgerUpcomingPaymentsView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpcomingPaymentsEntry

    private var snapshot: UpcomingPaymentsWidgetSnapshot? {
        guard let snapshot = entry.snapshot, snapshot.isCurrent(on: entry.date) else { return nil }
        return snapshot
    }

    private var payments: [UpcomingWidgetPayment] { snapshot?.payments ?? [] }
    private var currency: String { snapshot?.currency ?? "QAR" }
    private var closingLabel: String {
        snapshot?.closeDay.formatted(.dateTime.day().month(.abbreviated)) ?? "25th"
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallWidget
            case .systemMedium:
                mediumWidget
            case .systemLarge:
                largeWidget
            default:
                smallWidget
            }
        }
        .widgetURL(URL(string: "dailyledger://budget-upcoming"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next Ledger upcoming fixed payments")
    }

    private var brand: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(WidgetPalette.blue)
            Text("Next Ledger")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetPalette.navy)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var smallWidget: some View {
        ZStack {
            WidgetPalette.soft
            VStack(alignment: .leading, spacing: 7) {
                brand
                Text("Upcoming")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.navy)
                if let payment = payments.first {
                    HStack(spacing: 6) {
                        Image(systemName: symbol(for: payment.title))
                            .foregroundStyle(WidgetPalette.blue)
                            .frame(width: 22)
                        Text(payment.title)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(WidgetPalette.navy)
                    Text(payment.deadlineLabel(on: entry.date))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WidgetPalette.grey)
                        .lineLimit(1)
                    Text(money(payment.remaining))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(WidgetPalette.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Spacer(minLength: 0)
                    Text(payments.count > 1 ? "+\(payments.count - 1) more payments" :
                            "By \(closingLabel)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetPalette.blue)
                        .lineLimit(1)
                } else {
                    emptyState
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var mediumWidget: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                Label("Next Ledger", systemImage: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("Upcoming\nPayments")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text("\(payments.count) to pay")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text("By \(closingLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .frame(width: 128, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(colors: [WidgetPalette.navy, WidgetPalette.blue],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            VStack(alignment: .leading, spacing: 6) {
                if payments.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(payments.prefix(3))) { item in
                        HStack(spacing: 7) {
                            Image(systemName: symbol(for: item.title))
                                .foregroundStyle(WidgetPalette.blue)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.navy)
                                    .lineLimit(1)
                                Text(item.deadlineLabel(on: entry.date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(WidgetPalette.grey)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            Text(money(item.remaining))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(WidgetPalette.green)
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                        }
                        .frame(maxHeight: .infinity)
                        if item.id != payments.prefix(3).last?.id {
                            Rectangle().fill(WidgetPalette.blue.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                    if payments.count > 3 {
                        Text("+\(payments.count - 3) more")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WidgetPalette.blue)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.white)
        }
    }

    private var largeWidget: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Next Ledger", systemImage: "chart.bar.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("Upcoming Before Period Close")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .lineLimit(2)
                HStack {
                    Text("\(payments.count) payment\(payments.count == 1 ? "" : "s") remaining")
                    Spacer()
                    Label("By \(closingLabel)", systemImage: "calendar")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.86))
            }
            .foregroundStyle(.white)
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [WidgetPalette.navy, WidgetPalette.blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 0) {
                if payments.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(payments.prefix(5))) { payment in
                        HStack(spacing: 10) {
                            Image(systemName: symbol(for: payment.title))
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(WidgetPalette.blue)
                                .frame(width: 32, height: 32)
                                .background(WidgetPalette.blue.opacity(0.11), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(payment.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.navy)
                                    .lineLimit(1)
                                Text(payment.deadlineLabel(on: entry.date))
                                    .font(.system(size: 10))
                                    .foregroundStyle(WidgetPalette.grey)
                            }
                            Spacer(minLength: 6)
                            Text(money(payment.remaining))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(WidgetPalette.green)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        if payment.id != payments.prefix(5).last?.id {
                            Rectangle().fill(WidgetPalette.blue.opacity(0.12)).frame(height: 1)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                        Text(payments.count > 5 ? "+\(payments.count - 5) more · " : "")
                        Text("Remaining \(money(snapshot?.totalOutstanding ?? 0))")
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(WidgetPalette.green.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 11))
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.white)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: snapshot == nil ? "arrow.clockwise.icloud" : "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(WidgetPalette.green)
            Text(snapshot == nil ? "Open Next Ledger" : "All caught up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(WidgetPalette.navy)
            Text(snapshot == nil ? "Open Budget to refresh payments" :
                    "No unpaid fixed expenses before \(closingLabel)")
                .font(.system(size: 10))
                .foregroundStyle(WidgetPalette.grey)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func money(_ amount: Decimal) -> String {
        let formatted = amount.formatted(.number.precision(.fractionLength(2)))
        return "\(currency) \(formatted)"
    }

    private func symbol(for name: String) -> String {
        let title = name.lowercased()
        if title.contains("air") || title.contains("ticket") { return "airplane" }
        if title.contains("loan") || title.contains("bank") { return "building.columns.fill" }
        if title.contains("rent") || title.contains("house") { return "house.fill" }
        if title.contains("internet") || title.contains("wifi") { return "wifi" }
        if title.contains("car") || title.contains("auto") { return "car.fill" }
        if title.contains("phone") { return "iphone" }
        return "calendar.badge.clock"
    }
}

@main
struct NextLedgerWidgetCollection: WidgetBundle {
    var body: some Widget {
        UpcomingPaymentsWidget()
    }
}

private struct UpcomingPaymentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: UpcomingPaymentsWidgetStorage.widgetKind,
            provider: UpcomingPaymentsProvider()
        ) { entry in
            NextLedgerUpcomingPaymentsView(entry: entry)
        }
        .configurationDisplayName("Upcoming Fixed Payments")
        .description("Unpaid fixed-budget expenses before the 25th, shown on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
