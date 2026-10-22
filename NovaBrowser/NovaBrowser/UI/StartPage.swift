import SwiftUI

struct StartPage: View {
    @ObservedObject var tab: BrowserTab
    let search: (String) -> Void
    let resume: () -> Void
    private let destinations = [("Apple", "apple.com", "apple.logo"), ("Wikipedia", "wikipedia.org", "book.closed"), ("GitHub", "github.com", "chevron.left.forwardslash.chevron.right"), ("DuckDuckGo", "duckduckgo.com", "magnifyingglass")]

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 16) {
                        Image(systemName: tab.isPrivate ? "hand.raised.fill" : "safari.fill")
                            .font(.system(size: 45, weight: .light))
                            .foregroundStyle(LinearGradient(colors: tab.isPrivate ? [.purple, .indigo] : [.cyan, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NOVA").font(.system(.caption, design: .rounded, weight: .bold)).tracking(4).foregroundStyle(.secondary)
                            Text(tab.isPrivate ? "Browse privately." : "A wider web.")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        }
                    }.padding(.top, 30)

                    Text(tab.isPrivate ? "Private tabs use temporary website storage and are never saved to your session. Your network provider and websites can still see your traffic." : "Search from the address bar, or choose a destination below.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                    if tab.needsResume, let url = tab.url {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Ready when you are", systemImage: "clock.arrow.circlepath").font(.headline)
                            Text(tab.title).font(.title3.bold()).lineLimit(2)
                            Text(url.host ?? url.absoluteString).font(.subheadline).foregroundStyle(.secondary)
                            Button("Resume Tab", action: resume).buttonStyle(.borderedProminent)
                            Text("Restored tabs wait for your tap before connecting.").font(.caption).foregroundStyle(.secondary)
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        Text("START EXPLORING").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                            ForEach(destinations, id: \.0) { item in
                                Button { search(item.1) } label: {
                                    VStack(alignment: .leading, spacing: 24) {
                                        Image(systemName: item.2).font(.title2).frame(height: 28)
                                        HStack { Text(item.0).font(.subheadline.bold()); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }
                                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    HStack(spacing: 7) {
                        Circle().fill(.teal).frame(width: 6, height: 6)
                        Text("No connections until you open a website.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24).frame(maxWidth: 700)
                .frame(minHeight: geometry.size.height, alignment: .top)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
