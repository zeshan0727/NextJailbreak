import SwiftUI
import WidgetKit
struct ShortcutEntry: TimelineEntry { let date: Date }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ShortcutEntry { ShortcutEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (ShortcutEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortcutEntry>) -> Void) { completion(Timeline(entries: [placeholder(in: context)], policy: .never)) }
}
struct ShortcutWidgetView: View {
    let entry: ShortcutEntry
    @Environment(\.widgetFamily) var family
    func link(_ title: String, _ symbol: String, _ route: String) -> some View {
        Link(destination: URL(string: "nextchat://\(route)")!) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color.primary.opacity(0.08)).cornerRadius(10)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next Chat", systemImage: "bubble.left.and.bubble.right.fill").font(.headline)
            Spacer(minLength: 0)
            if family == .systemSmall {
                Image(systemName: "square.and.pencil").font(.system(size: 30))
                Text("New chat").font(.subheadline)
            } else {
                link("New chat", "square.and.pencil", "new")
                link("Resume chat", "clock", "resume")
                if family == .systemLarge {
                    link("Downloads", "arrow.down.circle", "downloads")
                    link("Prompt tools", "text.bubble", "prompts")
                }
            }
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "nextchat://new")!)
    }
}
@main struct NextChatWidgets: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextChatShortcuts", provider: Provider()) { ShortcutWidgetView(entry: $0) }
            .configurationDisplayName("Next Chat")
            .description("Open a conversation or your native tools without exposing chat content.")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}
