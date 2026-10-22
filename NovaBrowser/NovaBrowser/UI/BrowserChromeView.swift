import SwiftUI

struct BrowserChromeView: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var model: BrowserViewModel
    var showTabs: () -> Void
    var showLibrary: () -> Void
    var showSettings: () -> Void
    var showFind: () -> Void
    var repairChatGPT: () -> Void
    var share: () -> Void
    var zoom: () -> Void

    @State private var addressText = ""
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: tab.isPrivate ? "eye.slash.fill" : "lock.shield")
                    .foregroundStyle(tab.isPrivate ? .purple : .cyan)
                TextField("Search or enter website", text: $addressText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($editing)
                    .onSubmit { model.load(addressText); editing = false }
                if editing {
                    Button {
                        addressText = ""
                    } label: { Image(systemName: "xmark.circle.fill") }
                    Button("Go") { model.load(addressText); editing = false }
                        .fontWeight(.semibold)
                } else {
                    Button { tab.isLoading ? tab.stop() : tab.reload() } label: {
                        Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                    }
                }
            }
            .font(.body)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 0) {
                toolbarButton("chevron.backward", enabled: tab.canGoBack) { tab.goBack() }
                toolbarButton("chevron.forward", enabled: tab.canGoForward) { tab.goForward() }
                toolbarButton("plus", enabled: true) { model.newTab() }
                toolbarButton("square.on.square", enabled: true) { showTabs() }
                Menu {
                    Button(action: { showLibrary() }) { Label("Bookmarks & History", systemImage: "book") }
                    Button(action: { model.bookmarkCurrent() }) { Label("Bookmark This Page", systemImage: "bookmark") }
                    Button(action: { share() }) { Label("Share Page", systemImage: "square.and.arrow.up") }
                    Button(action: { showFind() }) { Label("Find in Page", systemImage: "text.magnifyingglass") }
                    Button(action: { repairChatGPT() }) {
                        Label("Repair ChatGPT Login", systemImage: "wrench.and.screwdriver")
                    }
                    if let url = URL(string: tab.address), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        Link(destination: url) { Label("Open Page in Safari", systemImage: "safari") }
                    }
                    Menu {
                        Button("System WebKit (recommended)") { model.setCurrentSiteUserAgent(.system) }
                        Button("iPhone Safari") { model.setCurrentSiteUserAgent(.iPhoneSafari) }
                        Button("iPad / Desktop Safari") { model.setCurrentSiteUserAgent(.iPadDesktop) }
                        Button("Windows Chrome identity") { model.setCurrentSiteUserAgent(.windowsChrome) }
                        Button("Android Chrome identity") { model.setCurrentSiteUserAgent(.androidChrome) }
                        Button("Firefox Linux identity") { model.setCurrentSiteUserAgent(.linuxFirefox) }
                    } label: { Label("User Agent for This Site", systemImage: "network") }
                    Menu {
                        Button("Mobile Site") { model.setCurrentSiteDesktopMode(false) }
                        Button("Desktop Site") { model.setCurrentSiteDesktopMode(true) }
                    } label: { Label("Site Display Mode", systemImage: "desktopcomputer") }
                    Button(action: { zoom() }) { Label("Text / Page Zoom", systemImage: "textformat.size") }
                    Button(action: { model.newTab(privateMode: true) }) { Label("Private Tab", systemImage: "eye.slash") }
                    Button(action: { showSettings() }) { Label("Settings", systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Browser menu")
            }
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            if tab.isLoading {
                ProgressView(value: tab.progress)
                    .progressViewStyle(.linear)
                    .tint(.cyan)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { addressText = tab.address }
        .onChange(of: tab.address) { newValue in
            if !editing { addressText = newValue }
        }
        .onChange(of: tab.id) { _ in addressText = tab.address }
    }

    private func toolbarButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
    }
}
