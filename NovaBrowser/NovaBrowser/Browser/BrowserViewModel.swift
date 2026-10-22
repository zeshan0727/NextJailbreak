import Combine
import Foundation
import SwiftUI
import WebKit

final class BrowserViewModel: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var downloads: [DownloadEntry] = []
    @Published private(set) var siteSettings: [SiteSettings] = []
    @Published var errorMessage: String?
    @Published var compatibilityReport: String = "Use Run Compatibility Check while a website is open."
    let settings = BrowserSettings()

    var activeTab: BrowserTab? { tabs.first { $0.id == selectedTabID } }

    init() {
        LaunchDiagnostics.record("Browser model initialization started")
        let saved = BrowserStore.load()
        bookmarks = saved.bookmarks
        history = saved.history
        downloads = saved.downloads
        siteSettings = saved.siteSettings
        for item in saved.tabs {
            let tab = configure(BrowserTab(id: item.id))
            tabs.append(tab)
            if let url = URL(string: item.address), url.scheme == "https" || url.scheme == "http" { tab.restore(url, title: item.title) }
        }
        selectedTabID = tabs.contains { $0.id == saved.currentID } ? saved.currentID : tabs.first?.id
        if tabs.isEmpty { newTab() }
        LaunchDiagnostics.record("Browser model initialized")
    }

    private func configure(_ tab: BrowserTab) -> BrowserTab {
        tab.onVisit = { [weak self] url, title, privateTab in
            guard let self, !privateTab else { return }
            if self.history.first?.address != url {
                self.history.insert(HistoryEntry(title: title, address: url), at: 0)
                if self.history.count > 1000 { self.history.removeLast() }
            }
            self.persist()
        }
        tab.onChanged = { [weak self] in self?.persist() }
        tab.onPopupWithConfiguration = { [weak self] configuration, privateTab in
            self?.newPopupTab(configuration: configuration, privateMode: privateTab)
        }
        tab.onDownload = { [weak self] entry in
            self?.downloads.insert(entry, at: 0)
            self?.persist()
        }
        tab.onError = { [weak self] message in self?.errorMessage = message }
        tab.compatibilityShimsEnabled = { [weak self] in self?.settings.legacyPolyfillsEnabled ?? true }
        tab.updateAppearance(settings.appearance)
        tab.resolveSite = { [weak self] host in
            guard let self else { return SiteSettingsResolver.resolve(host: host, global: GlobalSiteSettings(), sites: []) }
            return SiteSettingsResolver.resolve(host: host, global: self.settings.globalSiteSettings, sites: self.siteSettings)
        }
        return tab
    }

    @discardableResult
    func newTab(url: URL? = nil, privateMode: Bool = false) -> BrowserTab {
        let tab = configure(BrowserTab(isPrivate: privateMode))
        tabs.append(tab)
        selectedTabID = tab.id
        if let url { tab.load(url) }
        persist()
        return tab
    }

    private func newPopupTab(configuration: WKWebViewConfiguration, privateMode: Bool) -> WKWebView {
        let tab = configure(BrowserTab(isPrivate: privateMode, configuration: configuration))
        tabs.append(tab)
        selectedTabID = tab.id
        persist()
        return tab.webView
    }

    func close(_ id: UUID) {
        let index = tabs.firstIndex { $0.id == id }
        tabs.removeAll { $0.id == id }
        if tabs.isEmpty { newTab() }
        else if selectedTabID == id { selectedTabID = tabs[min(index ?? 0, tabs.count - 1)].id }
        persist()
    }

    func moveTabs(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    func select(_ id: UUID) { selectedTabID = id; persist() }

    func load(_ input: String) {
        guard let url = NavigationRouter.resolve(input, searchEngine: settings.searchEngine) else { return }
        activeTab?.load(url)
    }

    func bookmarkCurrent() {
        guard let tab = activeTab, !tab.address.isEmpty, !tab.isPrivate else { return }
        if !bookmarks.contains(where: { $0.address == tab.address }) {
            bookmarks.insert(Bookmark(title: tab.title, address: tab.address), at: 0)
            persist()
        }
    }

    func removeBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; persist() }
    func clearHistory() { history.removeAll(); persist() }

    func applyAppearance(_ appearance: BrowserAppearance) {
        tabs.forEach { $0.updateAppearance(appearance) }
    }

    func reloadTabsForCompatibility() {
        tabs.forEach { $0.reloadWithCompatibility() }
    }

    func setCurrentSiteDesktopMode(_ enabled: Bool) {
        guard let tab = activeTab, let host = URL(string: tab.address)?.host else { return }
        var value = siteSettings.first(where: { $0.id == host.lowercased() }) ?? SiteSettings(host: host)
        value.desktopMode = enabled
        siteSettings.removeAll { $0.id == value.id }
        siteSettings.append(value)
        tab.reloadWithCompatibility()
        persist()
    }

    func setCurrentSiteUserAgent(_ preset: UserAgentPreset) {
        guard let tab = activeTab, let host = URL(string: tab.address)?.host else { return }
        var value = siteSettings.first(where: { $0.id == host.lowercased() }) ?? SiteSettings(host: host)
        value.userAgentPreset = preset
        siteSettings.removeAll { $0.id == value.id }
        siteSettings.append(value)
        tab.reloadWithCompatibility()
        persist()
    }

    /// User-directed repair for the ChatGPT authentication domain family.
    /// It removes only the matching site's stored data and explicitly resets its overrides.
    func repairChatGPTSession() {
        settings.legacyPolyfillsEnabled = false
        for host in ["chatgpt.com", "www.chatgpt.com", "auth.openai.com", "chat.openai.com"] {
            siteSettings.removeAll { $0.host.lowercased() == host }
            siteSettings.append(SiteSettings(host: host, userAgentPreset: .system,
                                              desktopMode: false, javaScriptEnabled: true, popupMode: .allow))
        }
        persist()
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let domains = ["chatgpt.com", "openai.com"]
        dataStore.fetchDataRecords(ofTypes: types) { [weak self] records in
            let matching = records.filter { record in
                domains.contains { domain in
                    record.displayName.lowercased() == domain ||
                    record.displayName.lowercased().hasSuffix("." + domain)
                }
            }
            dataStore.removeData(ofTypes: types, for: matching) {
                DispatchQueue.main.async {
                    WebDiagnostics.record(host: "chatgpt.com", event: "User initiated website data reset")
                    self?.activeTab?.load(URL(string: "https://chatgpt.com/")!)
                }
            }
        }
    }

    func runCompatibilityCheck() {
        guard let tab = activeTab, !tab.address.isEmpty else {
            compatibilityReport = "Open a website first, then run this check."
            return
        }
        let script = """
        (function() {
          return {
            host: location.hostname,
            readyState: document.readyState,
            cookiesEnabled: String(navigator.cookieEnabled),
            webkit: String(typeof window.webkit !== "undefined"),
            fetch: typeof window.fetch,
            websocket: typeof window.WebSocket,
            serviceWorker: String("serviceWorker" in navigator),
            structuredClone: typeof window.structuredClone,
            withResolvers: typeof Promise.withResolvers
          };
        })();
        """
        tab.webView.evaluateJavaScript(script) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error {
                    self?.compatibilityReport = "JavaScript check failed: " + error.localizedDescription
                    WebDiagnostics.record(host: URL(string: tab.address)?.host ?? "unknown", event: "Compatibility check failed")
                } else if let values = result as? [String: String] {
                    let output = values.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: "\n")
                    self?.compatibilityReport = output
                    WebDiagnostics.record(host: values["host"] ?? "unknown", event: "Compatibility check completed: readyState=\(values["readyState"] ?? "-")")
                } else {
                    self?.compatibilityReport = "No structured JavaScript results returned."
                }
            }
        }
    }

    func persist() {
        let snapshot = BrowserSnapshot(
            tabs: tabs.filter { !$0.isPrivate && !$0.address.isEmpty }.map {
                SavedTab(id: $0.id, address: $0.address, title: $0.title)
            },
            currentID: activeTab?.isPrivate == false ? selectedTabID : nil,
            bookmarks: bookmarks, history: history, downloads: downloads, siteSettings: siteSettings
        )
        BrowserStore.save(snapshot)
    }
}
