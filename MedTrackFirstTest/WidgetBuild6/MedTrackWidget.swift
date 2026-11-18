import WidgetKit
import SwiftUI

struct MedTrackEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary
}

struct MedTrackTimeline: TimelineProvider {
    func placeholder(in context: Context) -> MedTrackEntry { MedTrackEntry(date: Date(), summary: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (MedTrackEntry) -> Void) {
        completion(MedTrackEntry(date: Date(), summary: snapshot()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MedTrackEntry>) -> Void) {
        let entry = MedTrackEntry(date: Date(), summary: snapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
    private func snapshot() -> WidgetSummary {
        guard let data = UserDefaults(suiteName: "group.com.nextsolution.medtrack")?.data(forKey: "widgetSummary"),
              let value = try? JSONDecoder().decode(WidgetSummary.self, from: data) else { return .empty }
        return value
    }
}

struct MedTrackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MedTrackEntry
    private let blue = Color(red: 0.18, green: 0.41, blue: 0.96)

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(Color(uiColor: .secondarySystemGroupedBackground), for: .widget)
        } else {
            content.background(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: "pills.fill").foregroundStyle(blue)
                Text("MedTrack").font(.headline)
                Spacer(minLength: 0)
            }
            Text("\(entry.summary.completed) / \(entry.summary.total) taken")
                .font(.system(.title2, design: .rounded).bold())
            if entry.summary.upcoming.isEmpty {
                Text("Open MedTrack to review your schedule.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.summary.upcoming.prefix(family == .systemSmall ? 1 : (family == .systemMedium ? 2 : 5)), id: \.self) { dose in
                    HStack(spacing: 5) {
                        Image(systemName: dose.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(dose.done ? .green : blue)
                        Text(dose.name).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(dose.time).foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: "medtrack://today"))
    }
}

@main
struct MedTrackWidget: Widget {
    let kind = "MedTrackWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MedTrackTimeline()) { entry in
            MedTrackWidgetView(entry: entry)
        }
        .configurationDisplayName("Medication schedule")
        .description("See upcoming doses and today's completion.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
