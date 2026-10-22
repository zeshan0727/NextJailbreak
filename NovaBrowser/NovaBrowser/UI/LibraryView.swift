import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var category = 0

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Library", selection: $category) {
                    Text("Bookmarks").tag(0)
                    Text("History").tag(1)
                    Text("Downloads").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                List {
                    switch category {
                    case 0:
                        ForEach(model.bookmarks) { item in
                            itemButton(item.title, secondary: item.address) { open(item.address) }
                                .swipeActions { Button("Remove", role: .destructive) { model.removeBookmark(item.id) } }
                        }
                    case 1:
                        ForEach(model.history) { item in
                            itemButton(item.title, secondary: item.address) { open(item.address) }
                        }
                    default:
                        ForEach(model.downloads) { item in
                            ShareLink(item: URL(fileURLWithPath: item.savedPath)) {
                                Label(item.filename, systemImage: "arrow.down.doc")
                            }
                        }
                    }
                }
                .overlay {
                    if category == 0 && model.bookmarks.isEmpty { Text("No Bookmarks").foregroundStyle(.secondary) }
                    else if category == 1 && model.history.isEmpty { Text("No History").foregroundStyle(.secondary) }
                    else if category == 2 && model.downloads.isEmpty { Text("No Downloads").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if category == 1 { Button("Clear") { model.clearHistory() } }
                }
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func itemButton(_ title: String, secondary: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading) {
                Text(title).foregroundStyle(.primary).lineLimit(1)
                Text(secondary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func open(_ address: String) {
        model.load(address)
        dismiss()
    }
}
