import SwiftUI
import UniformTypeIdentifiers

struct TabSwitcher: View {
    @ObservedObject var model: BrowserModel
    @State private var privateMode = false
    @State private var draggedID: UUID?
    @Environment(\.dismiss) private var dismiss
    private var visibleTabs: [BrowserTab] { model.tabs.filter { $0.isPrivate == privateMode } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab group", selection: $privateMode) {
                    Text("Tabs").tag(false)
                    Text("Private").tag(true)
                }.pickerStyle(.segmented).padding()
                ScrollView {
                    if visibleTabs.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.on.square").font(.largeTitle)
                            Text(privateMode ? "No private tabs" : "No tabs").font(.headline)
                            Text("Tap + to open a new tab.").foregroundStyle(.secondary)
                        }.padding(50)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 16)], spacing: 16) {
                        ForEach(visibleTabs) { tab in
                            TabCard(tab: tab, selected: model.selectedID == tab.id, choose: { model.select(tab); dismiss() }, close: { model.close(tab) })
                                .onDrag { draggedID = tab.id; return NSItemProvider(object: tab.id.uuidString as NSString) }
                                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                                    guard !providers.isEmpty, let draggedID, visibleTabs.contains(where: { $0.id == draggedID }) else { return false }
                                    model.move(draggedID, to: tab.id)
                                    self.draggedID = nil
                                    return true
                                }
                                .contextMenu {
                                    Button { move(tab, by: -1) } label: { Label("Move Earlier", systemImage: "arrow.left") }
                                    Button { move(tab, by: 1) } label: { Label("Move Later", systemImage: "arrow.right") }
                                    Button(role: .destructive) { model.close(tab) } label: { Label("Close Tab", systemImage: "xmark") }
                                }
                        }
                    }.padding(.horizontal, 16).padding(.bottom, 24)
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Your tabs")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { model.addTab(isPrivate: privateMode); dismiss() } label: { Image(systemName: "plus") }.accessibilityLabel("Add tab")
                }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear { privateMode = model.selectedTab?.isPrivate ?? false }
        }
    }
    private func move(_ tab: BrowserTab, by offset: Int) {
        guard let index = visibleTabs.firstIndex(where: { $0.id == tab.id }), visibleTabs.indices.contains(index + offset) else { return }
        model.move(tab.id, to: visibleTabs[index + offset].id)
    }
}

private struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let choose: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: tab.isPrivate ? "hand.raised.fill" : "globe").font(.caption).foregroundStyle(.secondary)
                Text(tab.title).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").font(.caption.bold()).frame(width: 36, height: 44) }
                    .accessibilityLabel("Close \(tab.title)")
            }.padding(.leading, 12)
            Button(action: choose) {
                ZStack {
                    Color(uiColor: .tertiarySystemBackground)
                    if let image = tab.thumbnail, !tab.isPrivate {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 160, alignment: .top).clipped()
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: tab.isPrivate ? "hand.raised.fill" : "safari").font(.system(size: 40)).foregroundStyle(tab.isPrivate ? .purple : .teal)
                            Text(tab.url?.host ?? "Start Page").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }.padding()
                    }
                }.frame(height: 160).clipped()
            }.buttonStyle(.plain).accessibilityLabel("Open \(tab.title)")
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? Color.teal : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1))
    }
}
