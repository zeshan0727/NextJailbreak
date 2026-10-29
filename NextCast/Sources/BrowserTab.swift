import SwiftUI
import WebKit
import Combine

struct SavedBookmark: Codable, Identifiable, Equatable {
    var id = UUID()
    let title: String
    let url: String
}

@MainActor
final class BrowserStore: ObservableObject {
    @Published var currentAddress = "https://www.google.com"
    @Published var title = "Browser"
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var loading = false
    @Published var pendingPopupURL: URL?
    @Published var bookmarks: [SavedBookmark] = []
    weak var webView: WKWebView?
    private let bookmarkKey = "nextcast.bookmarks.1"

    init() {
        if let data = UserDefaults.standard.data(forKey: bookmarkKey),
           let restored = try? JSONDecoder().decode([SavedBookmark].self, from: data) {
            bookmarks = restored
        }
    }
    func navigate(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let candidate: String
        if cleaned.contains("://") { candidate = cleaned }
        else if cleaned.contains(".") && !cleaned.contains(" ") { candidate = "https://" + cleaned }
        else {
            let query = cleaned.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            candidate = "https://www.google.com/search?q=" + query
        }
        guard let url = URL(string: candidate),
              ["https","http"].contains(url.scheme?.lowercased() ?? "") else { return }
        webView?.load(URLRequest(url: url))
    }
    func home() { navigate("https://www.google.com") }
    func update(_ view: WKWebView) {
        currentAddress = view.url?.absoluteString ?? currentAddress
        title = view.title ?? "Browser"
        canGoBack = view.canGoBack
        canGoForward = view.canGoForward
        loading = view.isLoading
    }
    func addBookmark() {
        guard let url = webView?.url?.absoluteString, !url.isEmpty else { return }
        guard !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.insert(SavedBookmark(title: webView?.title ?? url, url: url), at: 0)
        save()
    }
    func removeBookmark(_ bookmark: SavedBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }
    func approvePopup() {
        if let url = pendingPopupURL { webView?.load(URLRequest(url: url)) }
        pendingPopupURL = nil
    }
    private func save() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }
}

struct NextWebView: UIViewRepresentable {
    @ObservedObject var model: BrowserStore
    let blockAds: Bool
    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        model.webView = view
        if blockAds { installContentFilter(on: view) }
        view.load(URLRequest(url: URL(string: model.currentAddress)!))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        if model.webView !== uiView { model.webView = uiView }
    }

    private func installContentFilter(on view: WKWebView) {
        // Best-effort blocking of known advertising and popunder networks.
        // No third-party proxy, subscription or remote filtering service.
        let domains = [
            "doubleclick[.]net", "googlesyndication[.]com", "adservice[.]google[.]com",
            "popads[.]net", "popcash[.]net", "propellerads[.]com",
            "exoclick[.]com", "adnxs[.]com", "taboola[.]com",
            "outbrain[.]com", "adsrvr[.]org", "scorecardresearch[.]com"
        ]
        let rules: [[String: Any]] = domains.map { domain in
            ["trigger": ["url-filter": ".*" + domain + ".*"],
             "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let rulesJSON = String(data: data, encoding: .utf8) else { return }
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "NextCastAds-v1", encodedContentRuleList: rulesJSON
        ) { ruleList, _ in
            DispatchQueue.main.async {
                if let ruleList { view.configuration.userContentController.add(ruleList) }
            }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: BrowserStore
        init(model: BrowserStore) { self.model = model }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.update(webView)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.update(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            model.update(webView)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.update(webView)
        }
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Every target=_blank request is blocked pending user consent.
            if navigationAction.targetFrame == nil {
                model.pendingPopupURL = navigationAction.request.url
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                model.pendingPopupURL = navigationAction.request.url
            }
            return nil
        }
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            // Prevent blocking arbitrary JavaScript dialogs; script alerts are not opened.
            completionHandler()
        }
    }
}

struct BrowserTab: View {
    @StateObject private var model = BrowserStore()
    @AppStorage("browserBlockAds") private var blockAds = true
    @State private var inputURL = ""
    @State private var showBookmarks = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.cyan)
                    TextField("Search or enter URL", text: $inputURL)
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
                .padding(.horizontal, 12).padding(.top, 8)

                if model.loading {
                    ProgressView().progressViewStyle(.linear).tint(.cyan)
                }
                NextWebView(model: model, blockAds: blockAds)
                    .id(blockAds)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                HStack {
                    Button { model.webView?.goBack() } label: {
                        Image(systemName: "chevron.left")
                    }.disabled(!model.canGoBack)
                    Spacer()
                    Button { model.webView?.goForward() } label: {
                        Image(systemName: "chevron.right")
                    }.disabled(!model.canGoForward)
                    Spacer()
                    Button { model.home() } label: { Image(systemName: "house") }
                    Spacer()
                    Button { model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    Spacer()
                    Button { model.addBookmark() } label: { Image(systemName: "star") }
                    Spacer()
                    Button { showBookmarks = true } label: { Image(systemName: "book.closed") }
                    Spacer()
                    ShareLink(item: model.currentAddress) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .font(.system(size: 18, weight: .medium))
                .padding(.horizontal, 22).padding(.vertical, 14)
                .foregroundStyle(.cyan)
            }
            .navigationTitle("Browser")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Block common ads", isOn: $blockAds)
                        Button("Copy page URL", systemImage: "link") {
                            UIPasteboard.general.string = model.currentAddress
                        }
                        Button("Save bookmark", systemImage: "star") { model.addBookmark() }
                    } label: {
                        Image(systemName: "shield.lefthalf.filled")
                    }
                }
            }
            .onReceive(model.$currentAddress) { address in inputURL = address }
            .sheet(isPresented: $showBookmarks) {
                NavigationStack {
                    List {
                        if model.bookmarks.isEmpty {
                            ContentUnavailableView("No bookmarks", systemImage: "book",
                                description: Text("Tap the star while browsing to save a page."))
                        }
                        ForEach(model.bookmarks) { mark in
                            Button {
                                model.navigate(mark.url)
                                showBookmarks = false
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(mark.title).font(.headline).foregroundStyle(.primary)
                                    Text(mark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.removeBookmark(mark) }
                            }
                        }
                    }
                    .navigationTitle("Bookmarks")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Done") { showBookmarks = false } }
                    }
                }
            }
            .confirmationDialog(
                "Allow this site to open a new window?",
                isPresented: Binding(get: { model.pendingPopupURL != nil },
                                     set: { if !$0 { model.pendingPopupURL = nil } }),
                titleVisibility: .visible
            ) {
                Button("Allow and open") { model.approvePopup() }
                Button("Block pop-up", role: .cancel) { model.pendingPopupURL = nil }
            } message: {
                Text(model.pendingPopupURL?.host ?? "This website")
            }
        }
    }
}
