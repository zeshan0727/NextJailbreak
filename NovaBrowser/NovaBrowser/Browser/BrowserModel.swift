import SwiftUI
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published var notice: Notice?
    let settings = SettingsStore()
    private let sessions = SessionStore()
    lazy var webViews = WebViewStore(owner: self)
    struct Notice: Identifiable { let id = UUID(); let message: String }
    var selectedTab: BrowserTab? { tabs.first { $0.id == selectedID } }

    init() {
        if settings.value.restoreSession {
            do {
                if let saved = try sessions.load() {
                    tabs = saved.tabs.map { BrowserTab(id: $0.id, title: $0.title, url: $0.url, needsResume: $0.url != nil) }
                    selectedID = saved.selectedID
                }
            } catch {
                notice = Notice(message: "The saved session could not be restored. A new tab has been opened. \(error.localizedDescription)")
            }
        }
        if tabs.isEmpty { _ = addTab() }
    }

    @discardableResult
    func addTab(isPrivate: Bool = false, request: URLRequest? = nil, configuration: WKWebViewConfiguration? = nil) -> BrowserTab {
        let tab = BrowserTab(isPrivate: isPrivate)
        tabs.append(tab)
        selectedID = tab.id
        if let request { navigate(request, in: tab, configuration: configuration) }
        save()
        return tab
    }

    func select(_ tab: BrowserTab) {
        if let current = selectedTab { webViews.captureThumbnail(for: current) }
        selectedID = tab.id
        save()
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        webViews.remove(tab.id)
        tabs.remove(at: index)
        if tabs.isEmpty { _ = addTab() }
        else if selectedID == tab.id { selectedID = tabs[min(index, tabs.count - 1)].id }
        if !tabs.contains(where: \.isPrivate) { webViews.resetPrivateStore() }
        save()
    }

    func move(_ id: UUID, to destination: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }), let to = tabs.firstIndex(where: { $0.id == destination }), from != to else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        save()
    }

    func submit(_ input: String, in tab: BrowserTab) {
        do { navigate(URLRequest(url: try URLResolver.resolve(input, engine: settings.value.searchEngine, httpsFirst: settings.value.httpsFirst)), in: tab) }
        catch { notice = Notice(message: error.localizedDescription) }
    }

    func navigate(_ request: URLRequest, in tab: BrowserTab, configuration: WKWebViewConfiguration? = nil) {
        guard let url = request.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
        tab.errorMessage = nil
        tab.needsResume = false
        tab.isLocalTest = false
        tab.url = url
        webViews.webView(for: tab, configuration: configuration).load(request)
        save()
    }

    func resume(_ tab: BrowserTab) {
        guard let url = tab.url else { return }
        navigate(URLRequest(url: url), in: tab)
    }

    func home(_ tab: BrowserTab) {
        webViews.remove(tab.id)
        tab.url = nil
        tab.title = "New Tab"
        tab.needsResume = false
        tab.isLocalTest = false
        tab.errorMessage = nil
        tab.thumbnail = nil
        tab.canGoBack = false
        tab.canGoForward = false
        tab.isLoading = false
        save()
    }

    func openLocalTest() {
        guard let url = Bundle.main.url(forResource: "test-browser", withExtension: "html") else { return }
        let tab = addTab()
        tab.isLocalTest = true
        tab.url = url
        webViews.webView(for: tab).loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func save() {
        do {
            if settings.value.restoreSession { try sessions.save(tabs: tabs.map(\.record), selectedID: selectedID) }
            else { try sessions.clear() }
        } catch { notice = Notice(message: "Your session could not be saved. \(error.localizedDescription)") }
    }

    func clearWebsiteData() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        for tab in tabs where !tab.isPrivate { home(tab) }
    }
}
