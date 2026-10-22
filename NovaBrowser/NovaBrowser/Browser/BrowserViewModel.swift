import Combine
import Foundation
import SwiftUI

final class BrowserViewModel: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var downloads: [DownloadEntry] = []
    @Published private(set) var siteSettings: [SiteSettings] = []
    @Published var errorMessage: String?
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
        tab.onPopup = { [weak self] url, privateTab in self?.newTab(url: url, privateMode: privateTab) }
        tab.onDownload = { [weak self] entry in
            self?.downloads.insert(entry, at: 0)
            self?.persist()
        }
        tab.onError = { [weak self] message in self?.errorMessage = message }
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
