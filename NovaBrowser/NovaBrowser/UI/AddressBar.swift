import SwiftUI

struct AddressBar: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    let find: () -> Void
    let settings: () -> Void
    @State private var address = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button { model.home(tab) } label: { Label("Start Page", systemImage: "house") }
                Button(action: find) { Label("Find in Page", systemImage: "doc.text.magnifyingglass") }.disabled(tab.url == nil || tab.needsResume)
                Section("Page Zoom: \(Int(tab.pageZoom * 100))%") {
                    Button { model.webViews.zoom(tab.pageZoom + 0.1, in: tab) } label: { Label("Larger Text", systemImage: "plus.magnifyingglass") }
                    Button { model.webViews.zoom(tab.pageZoom - 0.1, in: tab) } label: { Label("Smaller Text", systemImage: "minus.magnifyingglass") }
                    Button("Reset Zoom") { model.webViews.zoom(1, in: tab) }
                }
                Button(action: settings) { Label("Settings", systemImage: "gearshape") }
            } label: {
                Text("aA").font(.system(size: 17, weight: .medium)).frame(width: 40, height: 44)
            }.accessibilityLabel("Page menu")
            Image(systemName: tab.isPrivate ? "hand.raised.fill" : (tab.url?.scheme == "https" ? "lock.fill" : "globe"))
                .font(.caption).foregroundStyle(tab.isPrivate ? Color.purple : Color.secondary)
                .accessibilityLabel(tab.isPrivate ? "Private tab" : (tab.url?.scheme == "https" ? "HTTPS connection" : "Website address"))
            TextField("Search or enter website", text: $address)
                .font(.body).keyboardType(.webSearch).textContentType(.URL)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.go).focused($focused)
                .accessibilityIdentifier("addressField")
                .onSubmit { focused = false; model.submit(address, in: tab) }
                .onAppear { updateAddress() }
                .onChange(of: tab.url) { _ in if !focused { updateAddress() } }
                .onChange(of: focused) { value in if value { address = tab.isLocalTest ? "" : (tab.url?.absoluteString ?? "") } else { updateAddress() } }
            if focused {
                Button { address = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 40, height: 44) }
                    .accessibilityLabel("Clear address")
            } else {
                Button {
                    if tab.isLoading { model.webViews.existing(for: tab)?.stopLoading() }
                    else if tab.needsResume { model.resume(tab) }
                    else { model.webViews.existing(for: tab)?.reload() }
                } label: { Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise").frame(width: 40, height: 44) }
                    .disabled(tab.url == nil).accessibilityLabel(tab.isLoading ? "Stop loading" : "Reload page")
            }
        }
        .background(tab.isPrivate ? Color.purple.opacity(0.12) : Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(tab.isPrivate ? Color.purple.opacity(0.25) : Color.primary.opacity(0.05), lineWidth: 1))
    }
    private func updateAddress() { address = tab.isLocalTest ? "Local Browser Test" : (tab.url?.absoluteString ?? "") }
}
