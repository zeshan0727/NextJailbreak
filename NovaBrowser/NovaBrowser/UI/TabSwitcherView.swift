import SwiftUI

struct TabSwitcherView: View {
    @ObservedObject var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reordering = false
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            Group {
                if reordering {
                    List {
                        ForEach(model.tabs) { tab in
                            HStack {
                                Image(systemName: tab.isPrivate ? "eye.slash" : "globe")
                                Text(tab.title).lineLimit(1)
                            }
                        }
                        .onMove(perform: model.moveTabs)
                    }
                    .environment(\.editMode, .constant(.active))
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(model.tabs) { tab in
                                Button {
                                    model.select(tab.id)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: tab.isPrivate ? "eye.slash" : "globe")
                                            Text(tab.title).font(.headline).lineLimit(1)
                                            Spacer(minLength: 0)
                                            Button { model.close(tab.id) } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                            .buttonStyle(.borderless)
                                            .accessibilityLabel("Close \(tab.title)")
                                        }
                                        Spacer()
                                        Text(tab.address.isEmpty ? "New Tab" : tab.address)
                                            .font(.caption).lineLimit(2).foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .frame(height: 155)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(tab.id == model.selectedTabID ? Color.cyan.opacity(0.14) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).stroke(tab.id == model.selectedTabID ? Color.cyan : .clear))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Tabs (\(model.tabs.count))")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(reordering ? "Done" : "Reorder") { reordering.toggle() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { model.newTab(privateMode: true); dismiss() } label: { Image(systemName: "eye.slash") }
                    Button { model.newTab(); dismiss() } label: { Image(systemName: "plus") }
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
