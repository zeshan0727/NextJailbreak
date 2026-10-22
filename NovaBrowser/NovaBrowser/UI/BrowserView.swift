import SwiftUI

private enum BrowserSheet: Identifiable {
    case tabs, settings, share(URL)
    var id: String {
        switch self {
        case .tabs: return "tabs"
        case .settings: return "settings"
        case .share(let url): return "share-\(url.absoluteString)"
        }
    }
}

struct BrowserView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var settings: SettingsStore
    @State private var sheet: BrowserSheet?
    @Environment(\.scenePhase) private var phase
    private var colorScheme: ColorScheme? {
        switch settings.value.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            if let tab = model.selectedTab {
                BrowserWorkspace(model: model, tab: tab, showTabs: {
                    model.webViews.captureThumbnail(for: tab)
                    sheet = .tabs
                }, showSettings: { sheet = .settings }, share: { sheet = .share($0) })
                .id(tab.id)
            }
            if phase != .active && model.selectedTab?.isPrivate == true {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                Label("Private Browsing", systemImage: "hand.raised.fill").font(.title2)
            }
        }
        .tint(Color(red: 0.04, green: 0.64, blue: 0.69))
        .preferredColorScheme(colorScheme)
        .sheet(item: $sheet) { destination in
            switch destination {
            case .tabs: TabSwitcher(model: model)
            case .settings: SettingsView(model: model, settings: settings)
            case .share(let url): ShareSheet(url: url)
            }
        }
        .alert(item: $model.notice) { Alert(title: Text("NovaBrowser"), message: Text($0.message), dismissButton: .default(Text("OK"))) }
    }
}

private struct BrowserWorkspace: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var tab: BrowserTab
    let showTabs: () -> Void
    let showSettings: () -> Void
    let share: (URL) -> Void
    @State private var showFind = false
    @State private var findText = ""
    var body: some View {
        VStack(spacing: 0) {
            AddressBar(model: model, tab: tab, find: { showFind.toggle() }, settings: showSettings)
                .padding(.horizontal, 12).padding(.vertical, 8)
            if tab.isLoading {
                ProgressView(value: tab.progress).progressViewStyle(.linear).accessibilityLabel("Page loading")
            } else { Divider() }
            if showFind { findBar }
            ZStack {
                if tab.url != nil && !tab.needsResume {
                    WebViewContainer(model: model, tab: tab)
                        .id(tab.id)
                } else {
                    StartPage(tab: tab, search: { model.submit($0, in: tab) }, resume: { model.resume(tab) })
                }
                if let error = tab.errorMessage {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 42)).foregroundStyle(.secondary)
                        Text("Couldn’t open this page").font(.title2.bold())
                        Text(error).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Reload") { model.resume(tab) }.buttonStyle(.borderedProminent)
                    }
                    .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            Divider()
            HStack {
                tool("Back", symbol: "chevron.left", disabled: !tab.canGoBack) { model.webViews.existing(for: tab)?.goBack() }
                Spacer(minLength: 0)
                tool("Forward", symbol: "chevron.right", disabled: !tab.canGoForward) { model.webViews.existing(for: tab)?.goForward() }
                Spacer(minLength: 0)
                tool("Share page", symbol: "square.and.arrow.up", disabled: tab.url == nil || tab.isLocalTest) { if let url = tab.url { share(url) } }
                Spacer(minLength: 0)
                tool("New tab", symbol: "plus") { model.addTab(isPrivate: tab.isPrivate) }
                Spacer(minLength: 0)
                Button(action: showTabs) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5).stroke(lineWidth: 1.7).frame(width: 26, height: 25)
                        Text("\(model.tabs.count)").font(.caption.bold()).monospacedDigit()
                    }.frame(minWidth: 44, minHeight: 44)
                }.accessibilityLabel("Tabs, \(model.tabs.count) open").accessibilityIdentifier("tabsButton")
            }
            .padding(.horizontal, 14).padding(.vertical, 4).background(.bar)
        }
    }
    private func tool(_ label: String, symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19, weight: .medium)).frame(minWidth: 44, minHeight: 44) }
            .disabled(disabled).accessibilityLabel(label)
    }
    private var findBar: some View {
        HStack(spacing: 8) {
            TextField("Find on this page", text: $findText)
                .textFieldStyle(.roundedBorder).submitLabel(.search)
                .onSubmit { model.webViews.find(findText, in: tab) }
                .onChange(of: findText) { model.webViews.find($0, in: tab) }
            if tab.foundMatch == false { Text("No match").font(.caption).foregroundStyle(.secondary) }
            Button { model.webViews.find(findText, in: tab, backwards: true) } label: { Image(systemName: "chevron.up").frame(width: 32, height: 44) }.accessibilityLabel("Previous match")
            Button { model.webViews.find(findText, in: tab) } label: { Image(systemName: "chevron.down").frame(width: 32, height: 44) }.accessibilityLabel("Next match")
            Button { showFind = false; findText = "" } label: { Image(systemName: "xmark").frame(width: 32, height: 44) }.accessibilityLabel("Close find")
        }.padding(.horizontal, 12).background(.bar)
    }
}
