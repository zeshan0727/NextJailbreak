import SwiftUI
import WidgetKit

// iOS 16+ read-only widget. No AppIntents, no buttons, no special signing
// requirements for interactive controls. Tapping opens MedTrack.
private enum WidgetConfig {
    static let group = "group.com.nextsolution.medtrack"
    static let link = URL(string: "medtrack://today")
    static let blue = Color(red: 0.18, green: 0.41, blue: 0.96)
}

struct MedTrackEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary
    let synced: Bool
}

struct MedTrackTimeline: TimelineProvider {
    func placeholder(in context: Context) -> MedTrackEntry { fallback() }

    func getSnapshot(in context: Context, completion: @escaping (MedTrackEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MedTrackEntry>) -> Void) {
        let entry = load()
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> MedTrackEntry {
        guard let shared = UserDefaults(suiteName: WidgetConfig.group),
              let data = shared.data(forKey: "widgetSummary"),
              let decoded = try? JSONDecoder().decode(WidgetSummary.self, from: data) else {
            return fallback()
        }
        return MedTrackEntry(date: Date(), summary: decoded.prepared(for: Date()), synced: true)
    }

    private func fallback() -> MedTrackEntry {
        // Sample names only. Never suggest that the user has confirmed a dose.
        let sample = [
            WidgetDose(name: "Panocer", time: "8:00 AM", done: false),
            WidgetDose(name: "Ezechol", time: "8:00 AM", done: false),
            WidgetDose(name: "Aspirin", time: "8:00 AM", done: false),
            WidgetDose(name: "Lipitor", time: "8:00 PM", done: false)
        ]
        return MedTrackEntry(date: Date(),
                             summary: WidgetSummary(completed: 0, total: 4, upcoming: sample),
                             synced: false)
    }
}

struct MedTrackWidgetView: View {
    let entry: MedTrackEntry
    @Environment(\.widgetFamily) private var family

    private var display: [WidgetDose] {
        Array(entry.summary.upcoming.prefix(family == .systemSmall ? 2 : 4))
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 7) {
            HStack(spacing: 5) {
                Image(systemName: "pills.fill").foregroundColor(WidgetConfig.blue)
                Text("MedTrack").font(.system(size: 14, weight: .bold))
                Spacer(minLength: 2)
                if entry.synced && entry.summary.total > 0 {
                    Text("\(entry.summary.completed)/\(entry.summary.total)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .lineLimit(1)

            if display.isEmpty {
                Text("No medicines scheduled")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                Text("Tap to view your medication list")
                    .font(.system(size: 10)).foregroundColor(WidgetConfig.blue)
            } else {
                ForEach(Array(display.enumerated()), id: \.offset) { _, dose in
                    HStack(spacing: 6) {
                        Image(systemName: dose.status == .taken ? "checkmark.circle.fill" :
                                            dose.status == .skipped ? "minus.circle.fill" : "circle")
                            .foregroundColor(dose.status == .taken ? .green :
                                             dose.status == .skipped ? .orange : WidgetConfig.blue)
                            .font(.system(size: 12))
                        Text(dose.name)
                            .font(.system(size: family == .systemSmall ? 11 : 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if family != .systemSmall {
                            Text(dose.actedAt.map { Self.timeFormatter.string(from: $0) } ?? dose.time)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(minHeight: family == .systemSmall ? 22 : 23)
                }
            }

            Spacer(minLength: 0)
            if !entry.synced {
                Text("Open MedTrack to refresh")
                    .font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            } else if family == .systemLarge {
                Text("Tap to record a dose in MedTrack")
                    .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .padding(family == .systemSmall ? 10 : 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                content.containerBackground(Color(uiColor: .secondarySystemGroupedBackground), for: .widget)
            } else {
                content.background(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
        .widgetURL(WidgetConfig.link)
    }
}

@main
struct MedTrackWidget: Widget {
    let kind = "MedTrackWidget" // Keep kind unchanged across upgrades.
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MedTrackTimeline()) { entry in
            MedTrackWidgetView(entry: entry)
        }
        .configurationDisplayName("MedTrack medicines")
        .description("Today's scheduled doses. Tap to open MedTrack.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
