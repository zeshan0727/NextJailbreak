import SwiftUI
import WebKit
import Combine

struct SavedBookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    let title: String
    let url: String
}

struct WebDownloadPrompt: Identifiable {
    let id = UUID()
    let request: URLRequest
    let tabID: UUID
    var label: String {
        request.url?.lastPathComponent.isEmpty == false
            ? (request.url?.lastPathComponent ?? "File")
            : (request.url?.host ?? "File")
    }
}

struct WebPopupPrompt: Identifiable {
    let id = UUID()
    let url: URL
    let originatingTabID: UUID
}

@MainActor
final class BrowserPage: Identifiable {
    let id = UUID()
    let webView: WKWebView
    let delegate: NextWebDelegate
    var title = "New Tab"
    var address = "https://www.google.com"
    var isLoading = false
    var canBack = false
    var canForward = false

    init(store: BrowserStore, url: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        // Every tab has its own independent navigation stack. Cookies may be
        // shared in the normal WebKit profile for signed-in websites.
        let view = WKWebView(frame: .zero, configuration: config)
        let handler = NextWebDelegate(store: store)
        webView = view
        delegate = handler
        address = url.absoluteString
        view.navigationDelegate = handler
        view.uiDelegate = handler
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        store.applyFilters(to: view)
        view.load(URLRequest(url: url))
    }
}

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var pages: [BrowserPage] = []
    @Published private(set) var selectedID: UUID?
    @Published var currentAddress = "https://www.google.com"
    @Published var loading = false
    @Published var pendingDownload: WebDownloadPrompt?
    @Published var pendingPopup: WebPopupPrompt?
    @Published var showMessage: String?
    @Published var bookmarks: [SavedBookmark] = []

    let library: MovieLibrary
    let downloads: BrowserDownloadStore
    private let bookmarkKey = "nextcast.bookmarks.1"
    var blockAds = true

    init(library: MovieLibrary, downloads: BrowserDownloadStore) {
        self.library = library
        self.downloads = downloads
        if let data = UserDefaults.standard.data(forKey: bookmarkKey),
           let decoded = try? JSONDecoder().decode([SavedBookmark].self, from: data) {
            bookmarks = decoded
        }
        addTab()
    }

    var active: BrowserPage? {
        pages.first { $0.id == selectedID }
    }
    var activeWebView: WKWebView? { active?.webView }
    var canBack: Bool { active?.canBack ?? false }
    var canForward: Bool { active?.canForward ?? false }

    func addTab(url: URL? = nil) {
        guard pages.count < 16 else {
            showMessage = "Close an existing tab before opening another (16 maximum)."
            return
        }
        let page = BrowserPage(store: self, url: url ?? URL(string: "https://www.google.com")!)
        pages.append(page)
        select(page.id)
    }
    func select(_ id: UUID) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        selectedID = id
        currentAddress = page.webView.url?.absoluteString ?? page.address
        loading = page.webView.isLoading
        objectWillChange.send()
    }
    func close(_ id: UUID) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let page = pages.remove(at: index)
        page.webView.stopLoading()
        if pages.isEmpty {
            addTab()
        } else if selectedID == id {
            select(pages[min(index, pages.count - 1)].id)
        }
    }
    func navigate(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let value: String
        if cleaned.contains("://") {
            value = cleaned
        } else if cleaned.contains(".") && !cleaned.contains(" ") {
            value = "https://" + cleaned
        } else {
            let query = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            value = "https://www.google.com/search?q=" + query
        }
        guard let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            showMessage = "Enter a valid webpage URL or search."
            return
        }
        activeWebView?.load(URLRequest(url: url))
    }
    func refresh(view: WKWebView) {
        guard let page = pages.first(where: { $0.webView === view }) else { return }
        page.title = view.title ?? view.url?.host ?? "Tab"
        page.address = view.url?.absoluteString ?? page.address
        page.canBack = view.canGoBack
        page.canForward = view.canGoForward
        page.isLoading = view.isLoading
        if page.id == selectedID {
            currentAddress = page.address
            loading = view.isLoading
        }
        objectWillChange.send()
    }
    func requestDownload(_ request: URLRequest, view: WKWebView) {
        guard let tab = pages.first(where: { $0.webView === view }), let url = request.url,
              ["http","https","blob"].contains(url.scheme?.lowercased() ?? "") else { return }
        pendingDownload = WebDownloadPrompt(request: request, tabID: tab.id)
    }
    func approveDownload() {
        guard let prompt = pendingDownload,
              let tab = pages.first(where: { $0.id == prompt.tabID }) else {
            pendingDownload = nil
            return
        }
        pendingDownload = nil
        // WebKit's native download API retains the browser session, redirect
        // handling, cookies and response-suggested filename.
        tab.webView.startDownload(using: prompt.request) { [weak self, weak tab] download in
            guard let tab, let self else { return }
            download.delegate = tab.delegate
            self.showMessage = "Download started. Open the Downloads tab to follow progress."
        }
    }
    func offerPopup(_ url: URL, from webView: WKWebView) {
        guard let tab = pages.first(where: { $0.webView === webView }) else { return }
        pendingPopup = WebPopupPrompt(url: url, originatingTabID: tab.id)
    }
    func approvePopup(newTab: Bool) {
        guard let prompt = pendingPopup else { return }
        pendingPopup = nil
        if newTab { addTab(url: prompt.url) }
        else if let tab = pages.first(where: { $0.id == prompt.originatingTabID }) {
            select(tab.id)
            tab.webView.load(URLRequest(url: prompt.url))
        }
    }

    func addBookmark() {
        guard let url = activeWebView?.url?.absoluteString, !url.isEmpty else { return }
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.insert(SavedBookmark(title: activeWebView?.title ?? url, url: url), at: 0)
        saveBookmarks()
    }
    func removeBookmark(_ bookmark: SavedBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }
    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    func applyFilters(to view: WKWebView) {
        guard blockAds else { return }
        let domains = [
            "doubleclick[.]net", "googlesyndication[.]com",
            "adservice[.]google[.]com", "popads[.]net", "popcash[.]net",
            "propellerads[.]com", "exoclick[.]com",
            "adnxs[.]com", "taboola[.]com", "outbrain[.]com"
        ]
        let rules: [[String: Any]] = domains.map {
            ["trigger": ["url-filter": ".*" + $0 + ".*"],
             "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "NextCastBlockedAds-v2", encodedContentRuleList: json
        ) { list, _ in
            DispatchQueue.main.async {
                if let list { view.configuration.userContentController.add(list) }
            }
        }
    }
    func toggleFilter(_ enabled: Bool) {
        blockAds = enabled
        for page in pages {
            page.webView.configuration.userContentController.removeAllContentRuleLists()
            if enabled { applyFilters(to: page.webView) }
            page.webView.reload()
        }
    }
}

struct BrowserWebSurface: UIViewRepresentable {
    let page: BrowserPage
    func makeUIView(context: Context) -> WKWebView { page.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
final class NextWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    weak var store: BrowserStore?
    private var lastRequest: URLRequest?
    init(store: BrowserStore) { self.store = store }

    private func looksLikeDownload(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return VideoFormats.extensions.contains(ext) ||
            ["pdf", "zip", "rar", "7z", "txt", "srt", "vtt", "jpg", "png", "apk", "ipa", "tipa"].contains(ext)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        store?.refresh(view: webView)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        store?.refresh(view: webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        store?.refresh(view: webView)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        store?.refresh(view: webView)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        lastRequest = navigationAction.request
        let download = navigationAction.shouldPerformDownload ||
            (navigationAction.navigationType == .linkActivated && looksLikeDownload(url))
        if download {
            store?.requestDownload(navigationAction.request, view: webView)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            store?.offerPopup(url, from: webView)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        let headers = (response as? HTTPURLResponse)?.allHeaderFields ?? [:]
        let disposition = headers.first(where: {
            String(describing: $0.key).lowercased() == "content-disposition"
        }).map { String(describing: $0.value).lowercased() } ?? ""
        if navigationResponse.isForMainFrame &&
            (!navigationResponse.canShowMIMEType || disposition.contains("attachment")) {
            if let url = response.url {
                var request = lastRequest ?? URLRequest(url: url)
                if request.url != url { request = URLRequest(url: url) }
                store?.requestDownload(request, view: webView)
            }
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if navigationAction.shouldPerformDownload || looksLikeDownload(url) {
                store?.requestDownload(navigationAction.request, view: webView)
            } else {
                store?.offerPopup(url, from: webView)
            }
        }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let store else {
            completionHandler(nil)
            return
        }
        let file = store.downloads.destination(for: suggestedFilename)
        store.downloads.begin(download, filename: suggestedFilename, destination: file)
        completionHandler(file)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let store else { return }
        store.downloads.finished(download, library: store.library)
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        store?.downloads.failed(download, error: error)
    }
}

struct BrowserTab: View {
    @ObservedObject var library: MovieLibrary
    @ObservedObject var downloads: BrowserDownloadStore
    @StateObject private var model: BrowserStore
    @AppStorage("browserBlockAds") private var blockAds = true
    @State private var inputURL = ""
    @State private var showBookmarks = false
    @State private var showTabList = false
    var openDownloads: () -> Void

    init(library: MovieLibrary, downloads: BrowserDownloadStore,
         openDownloads: @escaping () -> Void) {
        self.library = library
        self.downloads = downloads
        self.openDownloads = openDownloads
        _model = StateObject(wrappedValue: BrowserStore(library: library, downloads: downloads))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield").foregroundStyle(.cyan)
                    TextField("Search or URL", text: $inputURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit { model.navigate(inputURL) }
                    Button { model.navigate(inputURL) } label: {
                        Image(systemName: "arrow.right.circle.fill").font(.title3)
                    }
                }
                .padding(11)
                .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12).padding(.vertical, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(model.pages) { page in
                            HStack(spacing: 6) {
                                Button { model.select(page.id) } label: {
                                    Text(page.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .frame(maxWidth: 112, alignment: .leading)
                                }
                                Button { model.close(page.id) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption)
                                }
                                .accessibilityLabel("Close tab")
                            }
                            .padding(.horizontal, 11).padding(.vertical, 10)
                            .foregroundStyle(model.selectedID == page.id ? .white : .primary)
                            .background(model.selectedID == page.id ? Color.cyan.opacity(0.6) :
                                        Color.secondary.opacity(0.11), in: Capsule())
                        }
                        Button { model.addTab() } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                        .accessibilityLabel("New browser tab")
                    }.padding(.horizontal, 10)
                }
                .padding(.bottom, 6)

                if model.loading {
                    ProgressView().progressViewStyle(.linear).tint(.cyan)
                }
                if let page = model.active {
                    BrowserWebSurface(page: page)
                        .id(page.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    Button { model.activeWebView?.goBack() } label: {
                        Image(systemName: "chevron.left")
                    }.disabled(!model.canBack)
                    Spacer()
                    Button { model.activeWebView?.goForward() } label: {
                        Image(systemName: "chevron.right")
                    }.disabled(!model.canForward)
                    Spacer()
                    Button { model.navigate("https://www.google.com") } label: {
                        Image(systemName: "house")
                    }
                    Spacer()
                    Button { model.activeWebView?.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Spacer()
                    Button { model.addBookmark() } label: {
                        Image(systemName: "star")
                    }
                    Spacer()
                    Button { showBookmarks = true } label: {
                        Image(systemName: "book.closed")
                    }
                    Spacer()
                    Button { showTabList = true } label: {
                        Label("\(model.pages.count)", systemImage: "square.on.square")
                    }
                    Spacer()
                    Button { openDownloads() } label: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .font(.system(size: 17, weight: .medium))
                .padding(.horizontal, 15).padding(.vertical, 13)
                .foregroundStyle(.cyan)
            }
            .navigationTitle("Browser")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Block common ads", isOn: $blockAds)
                        Button("New Tab", systemImage: "plus") { model.addTab() }
                        Button("Download current URL", systemImage: "arrow.down") {
                            if let url = model.activeWebView?.url,
                               let view = model.activeWebView {
                                model.requestDownload(URLRequest(url: url), view: view)
                            }
                        }
                        Button("Copy URL", systemImage: "link") {
                            UIPasteboard.general.string = model.currentAddress
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .onAppear {
                model.toggleFilter(blockAds)
                inputURL = model.currentAddress
            }
            .onChange(of: blockAds) { enabled in model.toggleFilter(enabled) }
            .onChange(of: model.currentAddress) { inputURL = $0 }
            .onChange(of: model.selectedID) { _ in inputURL = model.currentAddress }
            .confirmationDialog("Download this file?",
                isPresented: Binding(get: { model.pendingDownload != nil },
                                    set: { if !$0 { model.pendingDownload = nil } }),
                titleVisibility: .visible) {
                Button("Start Download") { model.approveDownload() }
                Button("Cancel", role: .cancel) { model.pendingDownload = nil }
            } message: {
                Text(model.pendingDownload?.label ?? "File")
            }
            .confirmationDialog("Website requested a new window",
                isPresented: Binding(get: { model.pendingPopup != nil },
                                    set: { if !$0 { model.pendingPopup = nil } }),
                titleVisibility: .visible) {
                Button("Open in New Tab") { model.approvePopup(newTab: true) }
                Button("Open in Current Tab") { model.approvePopup(newTab: false) }
                Button("Block", role: .cancel) { model.pendingPopup = nil }
            } message: {
                Text(model.pendingPopup?.url.host ?? "Website")
            }
            .alert("Browser", isPresented: Binding(
                get: { model.showMessage != nil },
                set: { if !$0 { model.showMessage = nil } }
            )) {
                Button("OK") { model.showMessage = nil }
            } message: { Text(model.showMessage ?? "") }
            .sheet(isPresented: $showTabList) {
                NavigationStack {
                    List {
                        ForEach(model.pages) { page in
                            HStack {
                                Button {
                                    model.select(page.id)
                                    showTabList = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(page.title).font(.headline)
                                        Text(page.address).font(.caption)
                                            .lineLimit(1).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button(role: .destructive) { model.close(page.id) } label: {
                                    Image(systemName: "xmark.circle")
                                }
                            }
                        }
                    }
                    .navigationTitle("Browser Tabs")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showTabList = false }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { model.addTab(); showTabList = false } label: {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showBookmarks) {
                NavigationStack {
                    List {
                        if model.bookmarks.isEmpty {
                            Text("No bookmarks. Tap the star in the browser to save a page.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.bookmarks) { bookmark in
                            Button {
                                model.navigate(bookmark.url)
                                showBookmarks = false
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bookmark.title).font(.headline)
                                    Text(bookmark.url).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    model.removeBookmark(bookmark)
                                }
                            }
                        }
                    }
                    .navigationTitle("Bookmarks")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showBookmarks = false }
                        }
                    }
                }
            }
        }
    }
}
