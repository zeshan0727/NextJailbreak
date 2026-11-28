import SwiftUI
import WebKit
import SafariServices
import LocalAuthentication
import Speech
import AVFoundation
import QuickLook
import Network
import UIKit

private let homeURL = URL(string: "https://chatgpt.com/")!
private func official(_ url: URL?) -> Bool {
    guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") || host == "openai.com" || host.hasSuffix(".openai.com")
}
private func fileHost(_ url: URL?) -> Bool {
    guard let url, url.scheme == "https", let h = url.host?.lowercased() else { return false }
    return h == "oaiusercontent.com" || h.hasSuffix(".oaiusercontent.com") || h == "oaistatic.com" || h.hasSuffix(".oaistatic.com")
}
private func fileLink(_ url: URL) -> Bool {
    guard url.scheme == "https" else { return false }
    return ["ipa","tipa","zip","pdf","doc","docx","xls","xlsx","csv","ppt","pptx","txt","json","png","jpg","jpeg","webp","gif","mp4","mov","m4a","mp3","wav","tar","gz","7z","rar","dmg","ics","mobileprovision","deb"].contains(url.pathExtension.lowercased())
}
private func chatPage(_ url: URL?) -> Bool {
    guard let url, url.scheme == "https", url.host?.lowercased() == "chatgpt.com" else { return false }
    return true
}
private let loginURL = URL(string: "https://chatgpt.com/auth/login")!
private func authPage(_ url: URL?) -> Bool {
    guard let url, official(url), let host = url.host?.lowercased() else { return false }
    return host.hasPrefix("auth.") || host.hasPrefix("auth0.") || host.hasPrefix("login.") || url.path.hasPrefix("/auth") || url.path.hasPrefix("/api/auth") || url.path.hasPrefix("/oauth")
}
private func appleIdentity(_ url: URL?) -> Bool {
    guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return ["appleid.apple.com","account.apple.com","idmsa.apple.com"].contains(host)
}
private func identityProvider(_ url: URL) -> Bool {
    guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
    return ["accounts.google.com","appleid.apple.com","account.apple.com","login.microsoftonline.com","login.live.com","account.live.com"].contains(host)
}
private func browserStart(_ url: URL?) -> URL {
    guard let url, chatPage(url), !authPage(url) else { return homeURL }
    var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    parts?.query = nil
    parts?.fragment = nil
    return parts?.url ?? homeURL
}
struct SavedLink: Codable, Identifiable {
    var id = UUID()
    let title: String
    let url: URL
}
struct RecentChat: Codable, Identifiable {
    var id: URL { url }
    let url: URL
    var title: String
    var visited: Date
}
private func conversationURL(_ url: URL?) -> URL? {
    guard let url, chatPage(url), !authPage(url) else { return nil }
    let parts = url.path.split(separator: "/")
    guard let index = parts.firstIndex(of: "c"), index + 1 < parts.count else { return nil }
    guard index == 0 || (index > 0 && parts.first == "g") else { return nil }
    var clean = URLComponents(url: url, resolvingAgainstBaseURL: false)
    clean?.query = nil
    clean?.fragment = nil
    return clean?.url
}
struct LocalFile: Identifiable {
    let url: URL
    var id: URL { url }
    var bytes: Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    var modified: Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    var detail: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
struct PendingDownload: Identifiable {
    let id: ObjectIdentifier
    var name: String
    var progress: Double
}
// A weak bridge for explicit browser-generated file downloads only.
struct AttachmentIssue {
    let filename: String
    let conversation: URL
    let reason: String
}
private final class LocalDownloadBridge: NSObject, WKScriptMessageHandler {
    weak var browser: Browser?
    init(_ browser: Browser) { self.browser = browser }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        browser?.receiveLocalDownload(message)
    }
}
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published var loginHelp = false
    @Published var externalURL: URL?
    @Published var downloadDiagnostic = "No downloads yet."
    @Published var downloadMessage: String?
    @Published var attachmentIssue: AttachmentIssue?
    private var attachmentAttempts: [ObjectIdentifier: UUID] = [:]
    private var attachmentPopupParents: [ObjectIdentifier: WKWebView] = [:]
    private var recentDownloadGestures: [ObjectIdentifier: Date] = [:]
    @Published var diagnostic = "No navigation error recorded."
    @Published var resetInProgress = false
    @Published var popup: WKWebView?
    @Published var popupHost = "auth.openai.com"
    @Published var loading = false
    @Published var canBack = false
    @Published var canForward = false
    @Published var current: URL?
    @Published var pageTitle = "ChatGPT"
    @Published var notice: String?
    @Published var online = true
    @Published var files: [LocalFile] = []
    @Published var active: [PendingDownload] = []
    @Published var bookmarks: [SavedLink] = []
    @Published var recentChats: [RecentChat] = []
    private var recentWork: DispatchWorkItem?
    @Published private(set) var web: WKWebView
    @Published private(set) var liveViews: [WKWebView] = []
    private let liveLimit = 4
    private var requestedURLs: [ObjectIdentifier: URL] = [:]
    private var stoppedViews: Set<ObjectIdentifier> = []
    private var observations: [NSKeyValueObservation] = []
    private var transfers: [ObjectIdentifier: WKDownload] = [:]
    private var destinations: [ObjectIdentifier: URL] = [:]
    private var progressObservers: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var fileViews: [ObjectIdentifier: WKWebView] = [:]
    private var downloadViews: [ObjectIdentifier: WKWebView] = [:]
    private let monitor = NWPathMonitor()
    private let fm = FileManager.default
    private var folder: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
    }
    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        configure(web)
        liveViews = [web]
        if let data = UserDefaults.standard.data(forKey: "bookmarks"),
           let decoded = try? JSONDecoder().decode([SavedLink].self, from: data) { bookmarks = decoded.filter { chatPage($0.url) } }
        if UserDefaults.standard.object(forKey: "recordRecentChats") as? Bool ?? true,
           let data = UserDefaults.standard.data(forKey: "recentChats"),
           let decoded = try? JSONDecoder().decode([RecentChat].self, from: data) {
            recentChats = Array(decoded.filter { conversationURL($0.url) != nil }.prefix(100))
        }
        observeActive()
        monitor.pathUpdateHandler = { [weak self] path in DispatchQueue.main.async { self?.online = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "nextchat.network"))
        refreshFiles()
        if !(UserDefaults.standard.object(forKey: "preferSystemBrowserV5") as? Bool ?? false) { startEmbeddedIfNeeded() }
    }
    private func configure(_ view: WKWebView) {
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.scrollView.keyboardDismissMode = .interactive
        view.isOpaque = false
        let controller = view.configuration.userContentController
        controller.add(LocalDownloadBridge(self), contentWorld: .defaultClient, name: "nextLocalFile")
        controller.addUserScript(WKUserScript(source: Self.localDownloadScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        controller.addUserScript(WKUserScript(source: Self.detachedDownloadScript, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
    }
    // Some web clients generate a download anchor off-DOM and call click().
    // Attach it briefly so the standard DOM download listener can see the event.
    private static let detachedDownloadScript = #"""
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'chatgpt.com') return;
      let lastGesture = 0;
      document.addEventListener('click', e => {
        if (e.isTrusted) lastGesture = Date.now();
      }, true);
      const nativeClick = HTMLAnchorElement.prototype.click;
      HTMLAnchorElement.prototype.click = function() {
        if (!this.isConnected && this.hasAttribute('download') &&
            /^(blob:|data:)/i.test(this.href) &&
            Date.now() - lastGesture < 30000 && document.body) {
          const previousStyle = this.getAttribute('style');
          this.style.display = 'none';
          document.body.appendChild(this);
          try { return nativeClick.apply(this, arguments); }
          finally {
            this.remove();
            if (previousStyle === null) this.removeAttribute('style');
            else this.setAttribute('style', previousStyle);
          }
        }
        return nativeClick.apply(this, arguments);
      };
    })();
    """#
    // Only user-initiated browser-generated download anchors are intercepted.
    // The website's own click handlers retain priority. HTTPS and sandbox references
    // are never fetched by this bridge; the website must resolve them itself.
    private static let localDownloadScript = #"""
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'chatgpt.com') return;
      const limit = 8 * 1024 * 1024;
      let lastGesture = 0;
      // Observe, never cancel or replace the website's sandbox attachment handler.
      document.addEventListener('click', event => {
        if (!event.isTrusted || event.button !== 0) return;
        lastGesture = Date.now();
        const target = event.target instanceof Element ? event.target : event.target?.parentElement;
        const anchor = target?.closest('a[href]');
        const button = target?.closest('button,[role="button"]');
        const href = anchor?.getAttribute('href') || '';
        const sandbox = /^sandbox:\/mnt\/data\//i.test(href);
        const label = button?.getAttribute('aria-label') || button?.getAttribute('title') || '';
        if (!sandbox && !anchor?.hasAttribute('download') && !/download/i.test(label)) return;
        let name = sandbox ? href.split('/').pop() : anchor?.download || 'Attachment';
        try { name = decodeURIComponent(name || 'Attachment'); } catch (_) {}
        window.webkit?.messageHandlers?.nextLocalFile?.postMessage({kind:'sandboxTap', name});
      }, true);
      document.addEventListener('click', async event => {
        if (event.defaultPrevented || event.button !== 0 || (!event.isTrusted && Date.now() - lastGesture >= 30000)) return;
        const anchor = event.target instanceof Element ? event.target.closest('a[download]') : null;
        if (!anchor || anchor.hasAttribute('data-next-native-retry')) return;
        const url = anchor.href;
        if (!/^(blob:|data:)/i.test(url) || !window.webkit?.messageHandlers?.nextLocalFile) return;
        if (url.startsWith('data:') && url.length > limit * 1.5) return;
        const name = anchor.download || 'Download';
        event.preventDefault();
        const retry = () => {
          const link = document.createElement('a');
          link.href = url; link.download = name;
          link.setAttribute('data-next-native-retry', '');
          document.body.appendChild(link); link.click(); link.remove();
        };
        try {
          const response = await fetch(url);
          if (!response.ok) throw new Error('Unavailable local attachment');
          const blob = await response.blob();
          if (blob.size > limit) { retry(); return; }
          const reader = new FileReader();
          reader.onerror = retry;
          reader.onload = () => {
            const value = String(reader.result || '');
            const offset = value.indexOf(',');
            if (offset < 0) { retry(); return; }
            window.webkit.messageHandlers.nextLocalFile.postMessage({name, bytes: value.slice(offset + 1)});
          };
          reader.readAsDataURL(blob);
        } catch (_) { retry(); }
      }, false);
    })();
    """#
    fileprivate func receiveLocalDownload(_ message: WKScriptMessage) {
        guard message.name == "nextLocalFile", message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "chatgpt.com",
              let view = message.webView, liveViews.contains(where: { $0 === view }),
              chatPage(view.url), !authPage(view.url),
              let body = message.body as? [String: Any],
              let name = body["name"] as? String else { return }
        if body["kind"] as? String == "sandboxTap" {
            watchAttachment(name, from: view)
            return
        }
        guard let encoded = body["bytes"] as? String,
              encoded.utf8.count <= 11_184_816,
              let data = Data(base64Encoded: encoded), data.count <= 8 * 1024 * 1024 else { return }
        attachmentStarted(view)
        do {
            let destination = try availableDestination(name)
            try data.write(to: destination, options: .atomic)
            refreshFiles()
            downloadDiagnostic = "Browser-generated attachment saved."
            downloadMessage = "Download saved"
        } catch {
            downloadDiagnostic = "Unable to save browser-generated attachment."
            notice = "Download could not be saved. Check available device storage and retry."
        }
    }
    private func observeActive() {
        observations.removeAll()
        current = web.url
        pageTitle = web.title ?? "ChatGPT"
        loading = web.isLoading
        canBack = web.canGoBack
        canForward = web.canGoForward
        observations = [
            web.observe(\.isLoading, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async { guard let self, self.web === w else { return }; if self.loading != w.isLoading { self.loading = w.isLoading } } },
            web.observe(\.canGoBack, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async { guard let self, self.web === w else { return }; if self.canBack != w.canGoBack { self.canBack = w.canGoBack } } },
            web.observe(\.canGoForward, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async { guard let self, self.web === w else { return }; if self.canForward != w.canGoForward { self.canForward = w.canGoForward } } },
            web.observe(\.url, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async {
                guard let self, self.web === w else { return }
                guard self.current != w.url else { return }
                self.current = w.url
                if let url = conversationURL(w.url) { UserDefaults.standard.set(url.absoluteString, forKey: "lastChat") }
                self.scheduleRecent()
            } },
            web.observe(\.title, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async {
                guard let self, self.web === w else { return }
                let title = w.title ?? "ChatGPT"
                guard self.pageTitle != title else { return }
                self.pageTitle = title
                self.scheduleRecent()
            } }
        ]
        if let url = conversationURL(web.url) { UserDefaults.standard.set(url.absoluteString, forKey: "lastChat") }
        scheduleRecent()
    }
    private func makeLiveView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = web.configuration.websiteDataStore
        config.processPool = web.configuration.processPool
        config.allowsInlineMediaPlayback = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let view = WKWebView(frame: .zero, configuration: config)
        configure(view)
        return view
    }
    func tabTitle(_ view: WKWebView) -> String {
        if let title = view.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title != "ChatGPT" { return title }
        if let url = conversationURL(view.url) ?? conversationURL(requestedURLs[ObjectIdentifier(view)]),
           let recent = recentChats.first(where: { $0.url == url }) { return recent.title }
        return conversationURL(view.url) != nil ? "Conversation" : "New conversation"
    }
    private func tabURL(_ view: WKWebView) -> URL? {
        conversationURL(view.url) ?? (view.isLoading ? conversationURL(requestedURLs[ObjectIdentifier(view)]) : nil)
    }
    @discardableResult func selectTab(_ view: WKWebView) -> Bool {
        guard liveViews.contains(where: { $0 === view }) else { return false }
        guard view !== web else { return true }
        closePopup()
        recentWork?.cancel()
        web.endEditing(true)
        web = view
        observeActive()
        if stoppedViews.remove(ObjectIdentifier(view)) != nil {
            if view.url != nil { view.reload() }
            else { view.load(URLRequest(url: requestedURLs[ObjectIdentifier(view)] ?? homeURL)) }
            notice = "iOS had reclaimed this tab. Reopening it from the website."
        }
        return true
    }
    @discardableResult private func loadInNewTab(_ url: URL) -> Bool {
        if web.url == nil && !web.isLoading && requestedURLs[ObjectIdentifier(web)] == nil {
            requestedURLs[ObjectIdentifier(web)] = url
            web.load(URLRequest(url: url))
            return true
        }
        guard liveViews.count < liveLimit else {
            notice = "Four live conversations are open. Close a tab in Conversations before opening another."
            return false
        }
        let view = makeLiveView()
        liveViews.append(view)
        requestedURLs[ObjectIdentifier(view)] = url
        selectTab(view)
        view.load(URLRequest(url: url))
        return true
    }
    func closeTab(_ view: WKWebView) {
        guard liveViews.count > 1, let i = liveViews.firstIndex(where: { $0 === view }) else { return }
        if view === web { selectTab(liveViews[i == 0 ? 1 : i - 1]) }
        liveViews.removeAll { $0 === view }
        requestedURLs.removeValue(forKey: ObjectIdentifier(view))
        attachmentAttempts.removeValue(forKey: ObjectIdentifier(view))
        recentDownloadGestures.removeValue(forKey: ObjectIdentifier(view))
        stoppedViews.remove(ObjectIdentifier(view))
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }
    private func discardOtherTabs() {
        for view in liveViews.filter({ $0 !== web }) { closeTab(view) }
        requestedURLs.removeAll()
        stoppedViews.removeAll()
    }
    func startEmbeddedIfNeeded() {
        guard web.url == nil, !web.isLoading else { return }
        let restore = UserDefaults.standard.object(forKey: "restore") as? Bool ?? true
        if restore { resume() } else { open(homeURL) }
    }
    func prepareSystemBrowser() {
        closePopup()
        web.stopLoading()
        loginHelp = false
        notice = nil
    }
    deinit { monitor.cancel() }
    @discardableResult func open(_ url: URL) -> Bool {
        guard chatPage(url) else { return false }
        if let target = conversationURL(url) {
            if let existing = liveViews.first(where: { tabURL($0) == target }) { return selectTab(existing) }
            return loadInNewTab(url)
        }
        if web.url == url { return true }
        return loadInNewTab(url)
    }
    func newChat() { closePopup(); loadInNewTab(homeURL) }
    func restartLogin() {
        closePopup()
        discardOtherTabs()
        loginHelp = false
        web.stopLoading()
        web.load(URLRequest(url: homeURL, cachePolicy: .reloadIgnoringLocalCacheData))
    }
    func resetSignIn() {
        guard !resetInProgress else { return }
        closePopup()
        web.stopLoading()
        loginHelp = false
        resetInProgress = true
        let store = web.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resetInProgress = false
                self.restartLogin()
            }
        }
    }
    func closePopup() {
        popup?.stopLoading()
        popup?.navigationDelegate = nil
        popup?.uiDelegate = nil
        popup = nil
        popupHost = "auth.openai.com"
    }
    func resume() {
        if let raw = UserDefaults.standard.string(forKey: "lastChat"), let url = URL(string: raw), chatPage(url) { open(url) }
        else { newChat() }
    }
    func safari() { UIApplication.shared.open(browserStart(current)) }
    func safariLogin() { closePopup(); loginHelp = false; UIApplication.shared.open(homeURL) }
    private func scheduleRecent() {
        recentWork?.cancel()
        guard UserDefaults.standard.object(forKey: "recordRecentChats") as? Bool ?? true,
              let url = conversationURL(web.url) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, conversationURL(self.web.url) == url,
                  UserDefaults.standard.object(forKey: "recordRecentChats") as? Bool ?? true else { return }
            let title = self.web.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let previous = self.recentChats.first { $0.url == url }
            let label = title.isEmpty || title == "ChatGPT" ? (previous?.title ?? "Conversation") : title
            self.recentChats.removeAll { $0.url == url }
            self.recentChats.insert(RecentChat(url: url, title: label, visited: Date()), at: 0)
            self.recentChats = Array(self.recentChats.prefix(100))
            self.persistRecents()
        }
        recentWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
    private func persistRecents() {
        if let data = try? JSONEncoder().encode(recentChats) { UserDefaults.standard.set(data, forKey: "recentChats") }
    }
    func clearRecents() {
        recentWork?.cancel()
        recentChats = []
        UserDefaults.standard.removeObject(forKey: "recentChats")
    }
    func removeRecent(_ url: URL) {
        recentChats.removeAll { $0.url == url }; persistRecents()
    }
    func pin(_ url: URL, title: String) {
        guard let safe = conversationURL(url), !bookmarks.contains(where: { conversationURL($0.url) == safe }) else { return }
        bookmarks.insert(SavedLink(title: title, url: safe), at: 0); persistBookmarks()
    }
    func renamePin(_ id: UUID, title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let old = bookmarks[i]
        bookmarks[i] = SavedLink(id: old.id, title: clean, url: old.url)
        persistBookmarks()
    }
    func savePage() {
        guard let current = conversationURL(web.url) else { notice = "Open a conversation before saving it."; return }
        if bookmarks.contains(where: { conversationURL($0.url) == current }) { notice = "Already pinned."; return }
        pin(current, title: pageTitle == "ChatGPT" ? "Conversation" : pageTitle)
    }
    func removeBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; persistBookmarks() }
    private func persistBookmarks() { if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: "bookmarks") } }
    func clearCache(all: Bool) {
        if all { closePopup(); discardOtherTabs(); web.stopLoading() }
        let types: Set<String> = all ? WKWebsiteDataStore.allWebsiteDataTypes() : [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        web.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            if all { UserDefaults.standard.removeObject(forKey: "lastChat"); self?.clearRecents(); self?.restartLogin() }
            self?.notice = all ? "Local website data cleared." : "Cache cleared."
        }
    }
    private func external(_ url: URL) {
        guard ["http","https"].contains(url.scheme ?? "") else { return }
        if UserDefaults.standard.string(forKey: "externalLinkMode") == "Safari" { UIApplication.shared.open(url) }
        else { externalURL = url }
    }
    private func watchAttachment(_ name: String, from view: WKWebView) {
        guard view === web else { return }
        let key = ObjectIdentifier(view)
        recentDownloadGestures[key] = Date()
        let attempt = UUID()
        let conversation = browserStart(view.url)
        let safeName = String(name.prefix(180))
        attachmentAttempts[key] = attempt
        attachmentIssue = nil
        downloadDiagnostic = "Waiting for ChatGPT to resolve attachment."
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak view] in
            guard let self, let view, self.attachmentAttempts[key] == attempt else { return }
            self.attachmentAttempts.removeValue(forKey: key)
            guard view === self.web, browserStart(view.url) == conversation else { return }
            self.downloadDiagnostic = "Attachment tap observed; no native download started within 15 seconds."
            self.attachmentIssue = AttachmentIssue(filename: safeName, conversation: conversation,
                reason: "ChatGPT has not started a download yet. The attachment may still be resolving or may be unavailable.")
        }
    }
    private func attachmentStarted(_ view: WKWebView) {
        let source = attachmentPopupParents[ObjectIdentifier(view)] ?? view
        if attachmentAttempts.removeValue(forKey: ObjectIdentifier(source)) != nil, source === web {
            attachmentIssue = nil
        }
    }
    private func unresolvedAttachment(_ url: URL, from view: WKWebView) {
        attachmentStarted(view)
        downloadDiagnostic = "Website returned an unresolved sandbox file reference."
        guard view === web || view === popup else { return }
        attachmentIssue = AttachmentIssue(filename: String(url.lastPathComponent.prefix(180)),
            conversation: browserStart(web.url),
            reason: "ChatGPT supplied an internal sandbox reference instead of a downloadable attachment. Next Chat cannot access the remote sandbox directly.")
    }
    func openAttachmentInSafari() {
        guard let issue = attachmentIssue else { return }
        attachmentIssue = nil
        UIApplication.shared.open(issue.conversation)
    }
    func copyAttachmentRequest() {
        guard let issue = attachmentIssue else { return }
        UIPasteboard.general.string = "Please regenerate \(issue.filename.isEmpty ? "the attachment" : issue.filename) as a downloadable file in this conversation. Verify that the file exists before sharing the download link."
        attachmentIssue = nil
    }
    private func beginFile(_ request: URLRequest, in view: WKWebView) {
        attachmentStarted(view)
        downloadDiagnostic = "Starting download in website session."
        view.startDownload(using: request) { [weak self] download in
            guard let self else { return }
            self.downloadViews[ObjectIdentifier(download)] = view
            self.register(download)
        }
    }
    private func isFileView(_ view: WKWebView) -> Bool { fileViews[ObjectIdentifier(view)] != nil }
    private func fileRoute(_ request: URLRequest, from view: WKWebView) {
        attachmentStarted(view)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = view.configuration.websiteDataStore
        config.processPool = view.configuration.processPool
        let child = WKWebView(frame: .zero, configuration: config)
        child.navigationDelegate = self
        fileViews[ObjectIdentifier(child)] = child
        downloadDiagnostic = "Resolving attachment."
        child.load(request)
    }
    private func releaseFileView(_ view: WKWebView) {
        let key = ObjectIdentifier(view)
        fileViews.removeValue(forKey: key)
        attachmentPopupParents.removeValue(forKey: key)
    }
    private func recentAttachmentGesture(_ view: WKWebView) -> Bool {
        guard let date = recentDownloadGestures[ObjectIdentifier(view)] else { return false }
        return Date().timeIntervalSince(date) < 30
    }
    private func attachmentPopup(_ config: WKWebViewConfiguration, parent: WKWebView) -> WKWebView {
        let child = WKWebView(frame: .zero, configuration: config)
        child.navigationDelegate = self
        child.uiDelegate = self
        let key = ObjectIdentifier(child)
        fileViews[key] = child
        attachmentPopupParents[key] = parent
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self, weak child] in
            guard let self, let child, self.isFileView(child),
                  !self.downloadViews.values.contains(where: { $0 === child }) else { return }
            child.stopLoading()
            self.releaseFileView(child)
        }
        return child
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Never bridge WKFrameInfo.request on iOS 16.
        let source = webView.url
        let scheme = url.scheme?.lowercased() ?? ""
        let fromChat = official(source)
        let appleSignIn = appleIdentity(url) && (fromChat || appleIdentity(source) || webView === popup)
        let auth = authPage(source) || appleIdentity(source) || identityProvider(url)
        if action.shouldPerformDownload && !auth && (scheme == "https" || (fromChat && ["blob","data"].contains(scheme))) {
            attachmentStarted(webView)
            decisionHandler(.download); return
        }
        if action.targetFrame?.isMainFrame == false {
            // A user-selected attachment can be delivered via an iframe.
            // Leave all unrelated embedded content alone.
            if !auth && fromChat && attachmentAttempts[ObjectIdentifier(webView)] != nil &&
                ((fileHost(url) && fileLink(url)) || (scheme == "blob" && action.navigationType == .linkActivated)) {
                attachmentStarted(webView)
                decisionHandler(.download); return
            }
            decisionHandler(.allow); return
        }
        if isFileView(webView) {
            if let parent = attachmentPopupParents[ObjectIdentifier(webView)] {
                if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
                if scheme == "blob" || scheme == "data" {
                    attachmentStarted(parent); decisionHandler(.download); return
                }
                if scheme == "sandbox" {
                    decisionHandler(.cancel)
                    unresolvedAttachment(url, from: parent)
                    releaseFileView(webView)
                    return
                }
                // Permit only official HTTPS attachment destinations in a hidden popup.
                if scheme == "https", (fileHost(url) || (official(url) && !authPage(url))) {
                    decisionHandler(.allow); return
                }
                decisionHandler(.cancel)
                releaseFileView(webView)
                return
            }
            decisionHandler(scheme == "https" ? .allow : .cancel); return
        }
        if scheme == "sandbox" && fromChat {
            decisionHandler(.cancel)
            unresolvedAttachment(url, from: webView)
            return
        }
        if !auth && fromChat && fileHost(url) {
            decisionHandler(.cancel)
            fileRoute(action.request, from: webView); return
        }
        if !auth && fromChat && fileLink(url) &&
            (action.navigationType == .linkActivated || action.targetFrame == nil || official(url)) {
            decisionHandler(.cancel)
            fileRoute(action.request, from: webView); return
        }
        if !auth && fromChat && scheme == "blob" {
            decisionHandler(.download); return
        }
        if !auth && fromChat && scheme == "data" && action.navigationType == .linkActivated {
            decisionHandler(.download); return
        }
        if official(url) || appleSignIn || url.absoluteString == "about:blank" || (scheme == "blob" && fromChat) {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if auth {
            DispatchQueue.main.async { [weak self] in
                self?.diagnostic = "Authentication navigation requires a browser. Destination host: \(url.host ?? "unknown")."
                self?.loginHelp = true
            }
        } else if action.navigationType == .linkActivated || (fromChat && action.targetFrame == nil) {
            external(url)
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = response.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let attachment = disposition.contains("attachment") || disposition.contains("filename=") || disposition.contains("filename*=")
        let route = isFileView(webView)
        let mime = response.response.mimeType?.lowercased() ?? ""
        if attachmentPopupParents[ObjectIdentifier(webView)] != nil,
           response.response.url?.absoluteString == "about:blank" {
            decisionHandler(.allow); return
        }
        if route && (!(200...299).contains(http?.statusCode ?? 200) || (!attachment && mime == "text/html")) {
            decisionHandler(.cancel)
            releaseFileView(webView)
            downloadDiagnostic = "Attachment unavailable: HTTP \(http?.statusCode ?? 0), \(mime)."
            notice = "The server did not return a downloadable file. Try regenerating it."
            return
        }
        decisionHandler(route || !response.canShowMIMEType || attachment ? .download : .allow)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard action.targetFrame == nil, let url = action.request.url else { return nil }
        let source = webView.url
        let fromChat = official(source)
        let appleSignIn = appleIdentity(url) && (fromChat || appleIdentity(source))
        let auth = authPage(source) || appleIdentity(source) || identityProvider(url)
        if !auth && fromChat && recentAttachmentGesture(webView) && url.absoluteString == "about:blank" {
            return attachmentPopup(configuration, parent: webView)
        }
        // The asynchronous popup preference is enabled for attachment flows;
        // block unsolicited scripted popups, but retain normal links and authentication.
        if !auth && !appleSignIn && action.navigationType != .linkActivated &&
            !recentAttachmentGesture(webView) && !action.shouldPerformDownload &&
            !fileHost(url) && !fileLink(url) && url.scheme != "blob" {
            return nil
        }
        if !auth && fromChat && (action.shouldPerformDownload || url.scheme == "blob") && ["https","blob","data"].contains(url.scheme ?? "") {
            beginFile(action.request, in: webView); return nil
        }
        if !auth && fromChat && (fileHost(url) || fileLink(url)) {
            fileRoute(action.request, from: webView); return nil
        }
        if !appleSignIn && (identityProvider(url) || (!official(url) && url.absoluteString != "about:blank" && authPage(source))) {
            DispatchQueue.main.async { [weak self] in self?.loginHelp = true }
            return nil
        }
        if official(url) || appleSignIn || url.absoluteString == "about:blank" {
            guard popup == nil else { return nil }
            let child = WKWebView(frame: .zero, configuration: configuration)
            child.navigationDelegate = self
            child.uiDelegate = self
            child.scrollView.keyboardDismissMode = .interactive
            popupHost = url.host ?? "Official sign-in"
            popup = child
            return child
        }
        if url.scheme == "sandbox" && fromChat {
            unresolvedAttachment(url, from: webView)
        } else if action.navigationType == .linkActivated || fromChat { external(url) }
        return nil
    }
    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { closePopup() }
        else if isFileView(webView), !downloadViews.values.contains(where: { $0 === webView }) { releaseFileView(webView) }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === popup { popupHost = webView.url?.host ?? "Official sign-in" }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === web && authPage(webView.url) { discardOtherTabs() }
        if (webView === web || webView === popup), authPage(webView.url), webView.url?.path.lowercased().contains("error") == true {
            loginHelp = true
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if liveViews.contains(where: { $0 === webView }) && webView !== web {
            stoppedViews.insert(ObjectIdentifier(webView))
        } else if webView === web || webView === popup {
            notice = "Web content stopped. Reload to recover your session."
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { report(error, view: webView, stage: "provisional") }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error, view: webView, stage: "committed") }
    private func report(_ error: Error, view: WKWebView, stage: String) {
        let e = error as NSError
        if isFileView(view) {
            if (e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled) || ((e.domain == WKError.errorDomain || e.domain == "WebKitErrorDomain") && e.code == 102) { return }
            releaseFileView(view)
            downloadDiagnostic = "Attachment failed: \(e.domain) \(e.code)."
            notice = "Download failed. Tap the original attachment to retry."
            return
        }
        if view !== web && view !== popup { return }
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        // A delegate policy cancellation (e.g. Google OAuth handoff) is not a network failure.
        if (e.domain == WKError.errorDomain || e.domain == "WebKitErrorDomain") && e.code == 102 { return }
        let failed = e.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        let host = (failed ?? view.url)?.host ?? "unknown"
        diagnostic = "Navigation \(stage) • \(e.domain) code \(e.code) • host \(host)"
        if authPage(view.url) || authPage(failed) || appleIdentity(view.url) || appleIdentity(failed) || (failed.map { identityProvider($0) } ?? false) || view === popup {
            loginHelp = true
        } else {
            notice = "Unable to load page. \(diagnostic). Use Reload or Browser mode."
        }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { attachmentStarted(webView); downloadViews[ObjectIdentifier(download)] = webView; register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { attachmentStarted(webView); downloadViews[ObjectIdentifier(download)] = webView; register(download) }
    private func register(_ download: WKDownload) {
        let id = ObjectIdentifier(download)
        guard transfers[id] == nil else { return }
        transfers[id] = download; download.delegate = self
        downloadDiagnostic = "Download accepted by WebKit."
        active.append(PendingDownload(id: id, name: "Preparing download", progress: 0))
        progressObservers[id] = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p,_ in
            DispatchQueue.main.async {
                guard let self, let index = self.active.firstIndex(where: { $0.id == id }) else { return }
                self.active[index].progress = p.fractionCompleted
            }
        }
    }
    private func availableDestination(_ suggestedFilename: String) throws -> URL {
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let sanitized = (suggestedFilename as NSString).lastPathComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .components(separatedBy: .controlCharacters).joined()
        let safe = String(sanitized.prefix(180))
        let name = safe.isEmpty || safe == "." || safe == ".." ? "Download" : safe
        var dest = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) || destinations.values.contains(dest) {
            dest = folder.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + name)
        }
        return dest
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let id = ObjectIdentifier(download)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            downloadDiagnostic = "Attachment server returned HTTP \(http.statusCode)."
            completionHandler(nil)
            return
        }
        if response.mimeType?.lowercased() == "text/html",
           let url = response.url, fileLink(url),
           !["html","htm"].contains((suggestedFilename as NSString).pathExtension.lowercased()) {
            downloadDiagnostic = "The attachment link returned a web page instead of a file."
            completionHandler(nil)
            return
        }
        do {
            let dest = try availableDestination(suggestedFilename)
            destinations[id] = dest
            if let i = active.firstIndex(where: { $0.id == id }) { active[i].name = dest.lastPathComponent }
            completionHandler(dest)
        } catch {
            completionHandler(nil)
            notice = "Cannot create download destination."
        }
    }
    func downloadDidFinish(_ download: WKDownload) { finish(download, failed: false) }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let e = error as NSError
        downloadDiagnostic = "Download error: \(e.domain) \(e.code)."
        finish(download, failed: true)
    }
    private func finish(_ download: WKDownload, failed: Bool) {
        let id = ObjectIdentifier(download)
        if failed, let url = destinations[id] { try? fm.removeItem(at: url) }
        active.removeAll { $0.id == id }; transfers[id] = nil; destinations[id] = nil; progressObservers[id] = nil
        if let view = downloadViews.removeValue(forKey: id) { releaseFileView(view) }
        refreshFiles()
        if failed { notice = "Download failed. Reopen the original link to retry. \(downloadDiagnostic)" }
        else { downloadDiagnostic = "Download saved."; downloadMessage = "Download saved" }
    }
    func cancel(_ id: ObjectIdentifier) {
        guard let download = transfers[id] else { return }
        download.cancel { [weak self] _ in DispatchQueue.main.async { self?.finish(download, failed: true); self?.notice = "Download cancelled." } }
    }
    func refreshFiles() {
        let partials = Set(destinations.values)
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey,.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        files = urls.filter { !partials.contains($0) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.map { LocalFile(url: $0) }
    }
    func delete(_ file: LocalFile) { do { try fm.removeItem(at: file.url); refreshFiles() } catch { notice = "Unable to delete file." } }
    func rename(_ file: LocalFile, _ name: String) {
        let safe = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty, safe != ".", safe != "..", (safe as NSString).lastPathComponent == safe else { notice = "Invalid filename."; return }
        do { try fm.moveItem(at: file.url, to: folder.appendingPathComponent(safe)); refreshFiles() } catch { notice = "Unable to rename file." }
    }
}
// Keep live pages attached, but resize only the visible page during keyboard transitions.
final class LiveChatContainer: UIView {
    private weak var visiblePage: WKWebView?
    private var attachedPages: [ObjectIdentifier] = []
    func reconcile(_ pages: [WKWebView], active: WKWebView) {
        let identities = pages.map { ObjectIdentifier($0) }
        // SwiftUI can issue many updates during keyboard animation; do not revisit inactive views.
        guard attachedPages != identities || visiblePage !== active || active.superview !== self || active.isHidden else { return }
        attachedPages = identities
        let keep = Set(identities)
        for child in subviews where !keep.contains(ObjectIdentifier(child)) { child.removeFromSuperview() }
        for page in pages where page.superview !== self {
            page.autoresizingMask = []
            page.frame = bounds
            page.isHidden = page !== active
            page.accessibilityElementsHidden = page !== active
            addSubview(page)
        }
        guard visiblePage !== active || active.isHidden else { return }
        // No separate visibility animation when restoring an existing conversation.
        UIView.performWithoutAnimation {
            for page in pages {
                let hidden = page !== active
                if page.isHidden != hidden { page.isHidden = hidden }
                if page.accessibilityElementsHidden != hidden { page.accessibilityElementsHidden = hidden }
            }
            if active.frame != bounds { active.frame = bounds }
            if subviews.last !== active { bringSubviewToFront(active) }
            visiblePage = active
        }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Inactive tabs keep their previous viewport and live document state.
        if let page = visiblePage, page.frame != bounds { page.frame = bounds }
    }
}
struct WebSurface: UIViewRepresentable {
    let browser: Browser
    let onLeftEdge: () -> Void
    let onRightEdge: () -> Void
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onLeftEdge: () -> Void
        var onRightEdge: () -> Void
        var edges: [UIScreenEdgePanGestureRecognizer] = []
        init(_ parent: WebSurface) {
            onLeftEdge = parent.onLeftEdge
            onRightEdge = parent.onRightEdge
        }
        @objc func edgeMoved(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            let delta = gesture.translation(in: view)
            guard abs(delta.x) > 36, abs(delta.x) > abs(delta.y) else { return }
            if gesture.edges == .left && delta.x > 0 { onLeftEdge() }
            if gesture.edges == .right && delta.x < 0 { onRightEdge() }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scroll = otherGestureRecognizer.view as? UIScrollView else { return false }
            return otherGestureRecognizer === scroll.panGestureRecognizer
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> LiveChatContainer {
        let view = LiveChatContainer(frame: .zero)
        view.clipsToBounds = true
        view.reconcile(browser.liveViews, active: browser.web)
        for edge in [UIRectEdge.left, UIRectEdge.right] {
            let gesture = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.edgeMoved(_:)))
            gesture.edges = edge
            gesture.delegate = context.coordinator
            gesture.cancelsTouchesInView = false
            view.addGestureRecognizer(gesture)
            context.coordinator.edges.append(gesture)
        }
        return view
    }
    func updateUIView(_ uiView: LiveChatContainer, context: Context) {
        uiView.reconcile(browser.liveViews, active: browser.web)
        context.coordinator.onLeftEdge = onLeftEdge
        context.coordinator.onRightEdge = onRightEdge
    }
    static func dismantleUIView(_ uiView: LiveChatContainer, coordinator: Coordinator) {
        for gesture in coordinator.edges { uiView.removeGestureRecognizer(gesture) }
        coordinator.edges.removeAll()
    }
}
struct PopupSurface: UIViewRepresentable {
    let web: WKWebView
    func makeUIView(context: Context) -> WKWebView { web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
struct SafariSurface: UIViewControllerRepresentable {
    let start: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: start)
        controller.dismissButtonStyle = .done
        controller.preferredControlTintColor = .systemBlue
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
struct Preview: UIViewControllerRepresentable {
    let url: URL
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let c = QLPreviewController(); c.dataSource = context.coordinator; return c }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
}
final class Dictation: ObservableObject {
    @Published var text = ""
    @Published var recording = false
    @Published var error: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapped = false
    func start() {
        guard !recording else { return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else { self.error = "Speech permission unavailable."; return }
                AVAudioSession.sharedInstance().requestRecordPermission { allowed in
                    DispatchQueue.main.async { if allowed { self.begin() } else { self.error = "Microphone permission unavailable." } }
                }
            }
        }
    }
    private func begin() {
        guard !recording, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { error = "Dictation unavailable."; return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { error = "No microphone input."; stop(); return }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer,_ in req.append(buffer) }
            tapped = true
            engine.prepare(); try engine.start(); recording = true
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in DispatchQueue.main.async {
                if let result { self?.text = result.bestTranscription.formattedString }
                if error != nil || result?.isFinal == true { self?.stop() }
            } }
        } catch { self.error = "Could not start dictation."; stop() }
    }
    func stop() {
        engine.stop()
        if tapped { engine.inputNode.removeTap(onBus: 0); tapped = false }
        request?.endAudio(); task?.cancel(); request = nil; task = nil; recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
struct ConversationHub: View {
    @ObservedObject var browser: Browser
    var onClose: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    @AppStorage("recordRecentChats") private var recordRecentChats = true
    @State private var search = ""
    @State private var editing: SavedLink?
    @State private var titleDraft = ""
    @State private var confirmClear = false
    @State private var closingTab: WKWebView?
    @Environment(\.dismiss) private var dismiss
    private func matches(_ title: String) -> Bool { search.isEmpty || title.localizedCaseInsensitiveContains(search) }
    private func close() { if let onClose { onClose() } else { dismiss() } }
    private func open(_ url: URL) { if browser.open(url) { close() } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { browser.newChat(); close() } label: { Label("New conversation", systemImage: "square.and.pencil") }
                    Button { browser.savePage() } label: { Label("Pin current conversation", systemImage: "pin") }
                }
                Section {
                    ForEach(browser.liveViews, id: \.self) { view in
                        HStack {
                            Button {
                                browser.selectTab(view); close()
                            } label: {
                                Label(browser.tabTitle(view), systemImage: view === browser.web ? "checkmark.circle.fill" : "rectangle.on.rectangle")
                                    .font(.subheadline.weight(view === browser.web ? .semibold : .regular))
                                    .foregroundStyle(view === browser.web ? Color.accentColor : Color.primary)
                                    .lineLimit(2)
                            }.buttonStyle(.borderless)
                            Spacer()
                            if browser.liveViews.count > 1 {
                                Button { closingTab = view } label: { Image(systemName: "xmark.circle").foregroundStyle(.secondary) }
                                    .buttonStyle(.borderless).accessibilityLabel("Close tab")
                            }
                        }
                    }
                } header: {
                    Text("Live tabs · \(browser.liveViews.count)/4")
                } footer: {
                    Text("Open tabs stay in memory. Closing a tab may discard an unsent draft. iOS can reclaim web content under memory pressure.")
                }
                Section("Pinned") {
                    if browser.bookmarks.filter({ matches($0.title) }).isEmpty {
                        Text("Pin important conversations for quick access.").foregroundStyle(.secondary)
                    }
                    ForEach(browser.bookmarks.filter { matches($0.title) }) { item in
                        Button { open(item.url) } label: { Label(item.title, systemImage: "pin.fill") }
                            .contextMenu {
                                Button("Rename") { titleDraft = item.title; editing = item }
                                ShareLink(item: item.url)
                                Button("Unpin", role: .destructive) { browser.removeBookmark(item.id) }
                            }
                            .swipeActions { Button("Unpin", role: .destructive) { browser.removeBookmark(item.id) } }
                    }
                }
                Section("Recently opened on this device") {
                    if !recordRecentChats { Text("Local history is disabled in Settings.").foregroundStyle(.secondary) }
                    else if browser.recentChats.filter({ matches($0.title) }).isEmpty { Text("Open conversations to build this list.").foregroundStyle(.secondary) }
                    ForEach(browser.recentChats.filter { matches($0.title) }) { item in
                        Button { open(item.url) } label: {
                            HStack {
                                Image(systemName: "clock").foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).lineLimit(2)
                                    Text(item.visited, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions(edge: .leading) { Button { browser.pin(item.url, title: item.title) } label: { Label("Pin", systemImage: "pin") }.tint(.blue) }
                        .swipeActions { Button("Remove", role: .destructive) { browser.removeRecent(item.url) } }
                        .contextMenu {
                            Button("Pin") { browser.pin(item.url, title: item.title) }
                            Button("Remove from recents", role: .destructive) { browser.removeRecent(item.url) }
                        }
                    }
                }
                if let onSettings {
                    Section { Button(action: onSettings) { Label("Settings", systemImage: "gearshape") } }
                }
                Section {
                    Button("Clear local recents", role: .destructive) { confirmClear = true }.disabled(browser.recentChats.isEmpty)
                } footer: { Text("Only titles and links opened in Next Chat are stored locally. Your full account history remains in the ChatGPT sidebar. Removing a local shortcut does not delete a conversation.") }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search conversations")
            .navigationTitle("Conversations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary) }.accessibilityLabel("Close conversations") } }
            .alert("Rename pinned conversation", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("Title", text: $titleDraft)
                Button("Save") { if let item = editing { browser.renamePin(item.id, title: titleDraft) }; editing = nil }
                Button("Cancel", role: .cancel) { editing = nil }
            }
            .confirmationDialog("Close this live tab?", isPresented: Binding(get: { closingTab != nil }, set: { if !$0 { closingTab = nil } }), titleVisibility: .visible) {
                Button("Close tab", role: .destructive) { if let view = closingTab { browser.closeTab(view) }; closingTab = nil }
                Button("Cancel", role: .cancel) { closingTab = nil }
            } message: { Text("This does not delete the account conversation, but may discard an unsent draft.") }
            .confirmationDialog("Clear local recent conversations?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear recents", role: .destructive) { browser.clearRecents() }
            }
        }
    }
}
struct PromptTools: View {
    @StateObject private var dictation = Dictation()
    @AppStorage("favoritePrompts") private var favorites = "Review this code for bugs.\nSummarize the key findings."
    @State private var selectedText = ""
    @State private var promptSearch = ""
    @State private var category = "All"
    private let templates: [(category: String, title: String, prompt: String)] = [
        ("Development", "Debug a crash", "Analyze this crash log. Identify the likely root cause, affected code, minimal correction and device test plan. Distinguish evidence from assumptions."),
        ("Development", "Review a patch", "Review the changes for regressions, security issues, compatibility, and edge cases. Prioritize actionable fixes and tests."),
        ("Accounting", "Reconcile balances", "Reconcile these balances by account and period. Show matching entries, differences, likely causes and supporting evidence. Do not invent amounts."),
        ("Accounting", "Financial review", "Review these financial statements. Summarize material variances, classification issues and questions for management. Separate observations from conclusions."),
        ("Writing", "Professional email", "Draft a clear, concise professional email based on the details below. Preserve the facts and requested action."),
        ("Research", "Compare options", "Compare the options using current evidence, costs, advantages, limitations and risks. State assumptions and cite sources where available."),
        ("Research", "Summarize evidence", "Summarize the supplied material, identify key findings and unresolved questions, and distinguish facts from interpretation.")
    ]
    @State private var speaking = false
    @State private var speaker = AVSpeechSynthesizer()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Draft or dictate") {
                    TextEditor(text: $dictation.text).frame(minHeight: 120)
                    Button { dictation.recording ? dictation.stop() : dictation.start() } label: {
                        Label(dictation.recording ? "Stop dictation" : "Start dictation", systemImage: dictation.recording ? "stop.circle" : "mic")
                    }
                    if let error = dictation.error { Text(error).foregroundStyle(.secondary) }
                    Button("Copy draft to paste in ChatGPT") { dictation.stop(); UIPasteboard.general.string = dictation.text; dismiss() }.disabled(dictation.text.isEmpty)
                }
                Section("Prompt library") {
                    Picker("Category", selection: $category) {
                        ForEach(["All","Development","Accounting","Writing","Research"], id: \.self) { Text($0) }
                    }
                    TextField("Search templates", text: $promptSearch)
                    ForEach(templates.filter { (category == "All" || $0.category == category) && (promptSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(promptSearch) || $0.prompt.localizedCaseInsensitiveContains(promptSearch)) }, id: \.title) { template in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(template.title).font(.headline)
                            Text(template.prompt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            HStack {
                                Button("Edit draft") { dictation.text = template.prompt }.buttonStyle(.borderless)
                                Spacer()
                                Button("Copy & return") { dictation.stop(); UIPasteboard.general.string = template.prompt; dismiss() }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
                Section("Favorite prompts · one per line") {
                    TextEditor(text: $favorites).frame(minHeight: 100)
                    ForEach(Array(favorites.split(separator: "\n").enumerated()), id: \.offset) { _, value in
                        Button(String(value)) { dictation.text = String(value) }
                    }
                }
                Section("Read text aloud") {
                    TextEditor(text: $selectedText).frame(minHeight: 90)
                    Button("Speak") { speaker.stopSpeaking(at: .immediate); speaker.speak(AVSpeechUtterance(string: selectedText)) }.disabled(selectedText.isEmpty)
                    Button("Stop") { speaker.stopSpeaking(at: .immediate) }
                }
            }.navigationTitle("Prompt tools").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.onDisappear { dictation.stop(); speaker.stopSpeaking(at: .immediate) }
    }
}
struct DownloadsView: View {
    @ObservedObject var browser: Browser
    @State private var preview: LocalFile?
    @State private var editing: LocalFile?
    @State private var name = ""
    @State private var search = ""
    @State private var sort = "Newest"
    @Environment(\.dismiss) private var dismiss
    private var visibleFiles: [LocalFile] {
        let filtered = browser.files.filter { search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search) }
        switch sort {
        case "Name": return filtered.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        case "Size": return filtered.sorted { $0.bytes > $1.bytes }
        default: return filtered.sorted { $0.modified > $1.modified }
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if !browser.active.isEmpty {
                    Section("In progress") {
                        ForEach(browser.active) { item in
                            VStack(alignment: .leading) {
                                HStack { Text(item.name); Spacer(); Button("Cancel") { browser.cancel(item.id) }.buttonStyle(.borderless) }
                                ProgressView(value: item.progress)
                            }
                        }
                    }
                }
                Section {
                    HStack {
                        Text("\(browser.files.count) files").font(.subheadline)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: browser.files.reduce(Int64(0)) { $0 + $1.bytes }, countStyle: .file)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker("Sort by", selection: $sort) {
                        ForEach(["Newest","Name","Size"], id: \.self) { Text($0) }
                    }
                }
                Section("Saved files") {
                    if visibleFiles.isEmpty { Text(search.isEmpty ? "Downloaded files appear here." : "No matching files.").foregroundStyle(.secondary) }
                    ForEach(visibleFiles) { file in
                        Button { preview = file } label: {
                            HStack {
                                Image(systemName: "doc").font(.title3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.url.lastPathComponent).lineLimit(2)
                                    Text(file.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                            .contextMenu {
                                ShareLink(item: file.url)
                                Button("Rename") { name = file.url.lastPathComponent; editing = file }
                                Button("Delete", role: .destructive) { browser.delete(file) }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { browser.delete(file) } }
                    }
                }
            }.searchable(text: $search, prompt: "Search files").navigationTitle("Downloads").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $preview) { file in
                NavigationStack { Preview(url: file.url).toolbar { ToolbarItem(placement: .primaryAction) { ShareLink(item: file.url) } } }
            }
            .alert("Rename file", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                TextField("Filename", text: $name)
                Button("Save") { if let file = editing { browser.rename(file, name) }; editing = nil }
                Button("Cancel", role: .cancel) { editing = nil }
            }
        }.onAppear { browser.refreshFiles() }
    }
}
struct SettingsView: View {
    @ObservedObject var browser: Browser
    @AppStorage("haptics") private var haptics = true
    @AppStorage("preferSystemBrowserV5") private var launchBrowserMode = false
    @AppStorage("restore") private var restore = true
    @AppStorage("externalLinkMode") private var externalLinkMode = "In-app browser"
    @AppStorage("leftEdgeAction") private var leftEdgeAction = "Conversations"
    @AppStorage("recordRecentChats") private var recordRecentChats = true
    @AppStorage("appLock") private var appLock = false
    @AppStorage("privacy") private var privacy = true
    @AppStorage("lockDelay") private var lockDelay = 0
    @State private var confirm = false
    @Environment(\.dismiss) private var dismiss
    private func destination<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        Form { content() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
    private func tile(_ title: String, _ detail: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint).frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 26, weight: .semibold))
                            .frame(width: 60, height: 60)
                            .foregroundStyle(.white).background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next Chat").font(.title2.bold())
                            Text("Your conversations, elevated.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                }
                Section("Personalize") {
                    NavigationLink {
                        destination("Appearance") {
                            Section {
                                LabeledContent("Theme", value: "System")
                                Text("Next Chat automatically follows iOS light and dark appearance. Change it in iOS Settings → Display & Brightness. ChatGPT's website has its own appearance preference.").foregroundStyle(.secondary)
                            }
                        }
                    } label: { tile("Appearance", "Automatic light and dark", "circle.lefthalf.filled", .indigo) }
                    NavigationLink {
                        destination("Controls") {
                Section("Preferences") {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Restore last conversation", isOn: $restore)
                    Picker("Left edge swipe", selection: $leftEdgeAction) {
                        Text("Open conversations").tag("Conversations")
                        Text("Disabled").tag("Disabled")
                    }
                    Text("Swipe inward from the right edge or tap the bottom-right handle to show native controls.").font(.caption).foregroundStyle(.secondary)
                    Picker("Website links", selection: $externalLinkMode) {
                        Text("In-app browser").tag("In-app browser")
                        Text("Safari").tag("Safari")
                    }
                }

                        }
                    } label: { tile("Controls & gestures", "Navigation, haptics and links", "hand.tap", .blue) }
                }
                Section("App") {
                    NavigationLink {
                        destination("Privacy") {
                Section("Privacy") {
                    Toggle("App switcher privacy", isOn: $privacy)
                    Toggle("Record local recent conversations", isOn: $recordRecentChats)
                        .onChange(of: recordRecentChats) { if !$0 { browser.clearRecents() } }
                    Text("Stores only conversation titles and links on this device. Disabling clears this local list, not your account history.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Device authentication", isOn: Binding(get: { appLock }, set: { value in
                        let context = LAContext()
                        var error: NSError?
                        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { browser.notice = "Device authentication not available."; return }
                        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Change Next Chat privacy settings") { ok,_ in DispatchQueue.main.async { if ok { appLock = value } } }
                    }))
                    Picker("Lock after", selection: $lockDelay) { Text("Immediately").tag(0); Text("1 minute").tag(60); Text("5 minutes").tag(300) }.disabled(!appLock)
                    Button("Clear cache") { browser.clearCache(all: false) }
                    Button("Clear website data", role: .destructive) { confirm = true }
                }

                        }
                        .confirmationDialog("Clear local website data and sign out of this web session?", isPresented: $confirm, titleVisibility: .visible) {
                            Button("Clear data", role: .destructive) { browser.clearCache(all: true) }
                        }
                    } label: { tile("Privacy & security", "App lock, local history and storage", "lock.shield", .green) }
                    NavigationLink {
                        destination("Connection") {
                Section("Connection") {
                    LabeledContent("Network", value: browser.online ? "Available" : "Offline")
                    Picker("Chat mode", selection: $launchBrowserMode) {
                        Text("Direct").tag(false)
                        Text("Browser").tag(true)
                    }
                    Text("Direct mode uses your existing embedded website session. Browser mode is an optional fallback with a separate session. Changing mode does not clear sign-in data.").font(.caption).foregroundStyle(.secondary)
                    Button("Reload ChatGPT") { browser.web.reload(); dismiss() }
                    Button("Restart sign-in") { browser.restartLogin(); dismiss() }
                    Text(browser.diagnostic).font(.caption).textSelection(.enabled)
                    Text(browser.downloadDiagnostic).font(.caption).textSelection(.enabled)
                    ShareLink(item: browser.downloadDiagnostic) { Label("Share download diagnostics", systemImage: "square.and.arrow.up") }
                    ShareLink(item: browser.diagnostic) { Label("Share login diagnostics", systemImage: "square.and.arrow.up") }
                    Button("Open in Safari") { browser.safariLogin() }
                    ShareLink(item: "Next Chat 1.0.0 (16)\niOS \(UIDevice.current.systemVersion)\nNetwork: \(browser.online ? "available" : "offline")\nNo account or session information included.") { Label("Share diagnostics", systemImage: "square.and.arrow.up") }
                }

                        }
                    } label: { tile("Connection & diagnostics", "Network, sign-in and downloads", "network", .orange) }
                    NavigationLink {
                        destination("About") {
                Section("About") {
                    LabeledContent("Version", value: "1.0.0 (16)")
                    Text("Unofficial companion. Conversations and authentication are provided by the ChatGPT website. Safari sessions are separate. No additional API subscription is used. Local bookmarks and downloads are stored on this device.")
                    Link("OpenAI privacy policy", destination: URL(string: "https://openai.com/policies/privacy-policy/")!)
                }

                        }
                    } label: { tile("About Next Chat", "Version and policies", "info.circle", .secondary) }
                }
            }.listStyle(.insetGrouped)
            .navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
enum Panel: String, Identifiable { case settings, downloads, prompts, bookmarks, browserMode, externalBrowser; var id: String { rawValue } }
struct RootView: View {
    @StateObject private var browser = Browser()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("haptics") private var haptics = true
    @AppStorage("privacy") private var privacy = true
    @AppStorage("appLock") private var appLock = false
    @AppStorage("lockDelay") private var lockDelay = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: Panel?
    @State private var externalStart: URL?
    @State private var controlsExpanded = false
    @State private var sidebarOpen = false
    @AppStorage("leftEdgeAction") private var leftEdgeAction = "Conversations"
    @State private var locked = true
    @State private var authenticating = false
    @State private var inactiveSince: Date?
    @State private var bookmarkSearch = ""
    @State private var pendingRoute: String?
    @AppStorage("preferSystemBrowserV5") private var launchBrowserMode = false
    @State private var confirmResetLogin = false
    @State private var showDirectLoginHelp = false
    @State private var didLaunchBrowser = false
    private func tap() { if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() } }
    private func setControls(_ expanded: Bool) {
        guard !launchBrowserMode, browser.popup == nil, !appLock || !locked else { return }
        if controlsExpanded != expanded {
            tap()
            controlsExpanded = expanded
        }
    }
    private func leftEdge() {
        guard !launchBrowserMode, browser.popup == nil, panel == nil, !appLock || !locked else { return }
        if leftEdgeAction == "Conversations" { showConversations() }
    }
    private func showConversations() {
        guard !appLock || !locked, browser.popup == nil else { return }
        if launchBrowserMode { panel = .bookmarks; return }
        tap()
        browser.web.endEditing(true)
        controlsExpanded = false
        sidebarOpen = true
    }
    private func showBrowser() {
        guard !appLock || !locked else { pendingRoute = "resume"; return }
        sidebarOpen = false
        browser.prepareSystemBrowser()
        didLaunchBrowser = true
        panel = .browserMode
    }
    private func startPreferredMode() {
        guard !appLock || !locked else { return }
        if launchBrowserMode {
            if !didLaunchBrowser && panel == nil { showBrowser() }
        } else {
            browser.startEmbeddedIfNeeded()
        }
    }
    private func unlock() {
        guard appLock, !authenticating else { return }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { browser.notice = "Device authentication unavailable."; return }
        authenticating = true
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Next Chat") { ok,_ in
            DispatchQueue.main.async { authenticating = false; if ok { locked = false; if let route = pendingRoute { pendingRoute = nil; handle(route) } else { startPreferredMode() } } }
        }
    }
    private func handle(_ route: String) {
        guard !appLock || !locked else { pendingRoute = route; return }
        switch route {
        case "new": if launchBrowserMode { showBrowser() } else { browser.newChat() }
        case "resume": if launchBrowserMode { showBrowser() } else { browser.resume() }
        case "downloads": didLaunchBrowser = true; panel = .downloads
        case "prompts": didLaunchBrowser = true; panel = .prompts
        default: break
        }
    }
    private var collapsedControls: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button { setControls(true) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    if !browser.active.isEmpty { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                }
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Next Chat controls")
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.width < -20 && abs(value.translation.width) > abs(value.translation.height) { setControls(true) }
            })
        }.padding(.horizontal, 12)
    }
    private var expandedControls: some View {
        HStack(spacing: 3) {
            Button { showConversations() } label: {
                Image(systemName: "books.vertical").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Conversations")
            Button { tap(); controlsExpanded = false; panel = .prompts } label: {
                Image(systemName: "text.bubble").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Prompt studio")
            Button { tap(); controlsExpanded = false; browser.newChat() } label: {
                Image(systemName: "square.and.pencil").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("New chat")
            Button { tap(); controlsExpanded = false; panel = .downloads } label: {
                Image(systemName: "arrow.down.circle").overlay(alignment: .topTrailing) {
                    if !browser.active.isEmpty { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                }.frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Downloads")
                Menu {
                    Button { browser.resume() } label: { Label("Resume conversation", systemImage: "clock") }
                    Button { browser.savePage() } label: { Label("Save current page", systemImage: "bookmark") }
                    Button { showConversations() } label: { Label("Saved conversations", systemImage: "books.vertical") }
                    Button { panel = .prompts } label: { Label("Prompt tools", systemImage: "text.bubble") }
                    Button { browser.web.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Button { browser.safari() } label: { Label("Open in Safari", systemImage: "safari") }
                    Button { panel = .settings } label: { Label("Settings", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("More")

            Button { setControls(false) } label: {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }.accessibilityLabel("Hide Next Chat controls")
        }
        .font(.system(size: 20, weight: .medium))
        .padding(.horizontal, 7)
        .frame(height: 46)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay { Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5) }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
            if value.translation.width > 36 && abs(value.translation.width) > abs(value.translation.height) { setControls(false) }
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            if !browser.online { Text("Offline · reconnect to continue").font(.caption).frame(maxWidth: .infinity).padding(6).background(.orange.opacity(0.15)) }
            if launchBrowserMode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 30, weight: .semibold))
                            Text("Next Chat").font(.largeTitle.bold())
                            Spacer()
                            Button { panel = .settings } label: { Image(systemName: "gearshape").font(.title2) }.accessibilityLabel("Settings")
                        }
                        Text("Your ChatGPT account").font(.title2.bold())
                        Text("Open your existing conversations, projects and subscription in the secure system browser.").foregroundStyle(.secondary)
                        Button { tap(); showBrowser() } label: {
                            Label("Open ChatGPT", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity).padding(.vertical, 10)
                        }.buttonStyle(.borderedProminent)
                        Button { panel = .downloads } label: { Label("Native downloads", systemImage: "arrow.down.circle") }
                        Button { panel = .prompts } label: { Label("Prompt tools", systemImage: "text.bubble") }
                        Button { launchBrowserMode = false; browser.startEmbeddedIfNeeded() } label: { Label("Switch to direct mode", systemImage: "rectangle.on.rectangle") }
                        Text("Direct mode uses a separate session. Google sign-in is supported in Browser mode, not direct mode. Browser downloads and history are managed by the browser and website.").font(.footnote).foregroundStyle(.secondary)
                    }.padding(24).frame(maxWidth: 600)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let popup = browser.popup {
                HStack {
                    Image(systemName: "lock.shield")
                    Text(browser.popupHost).font(.caption)
                    Spacer()
                    Button("Close") { browser.closePopup() }
                }.padding(12)
                PopupSurface(web: popup).id(ObjectIdentifier(popup)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WebSurface(browser: browser, onLeftEdge: { leftEdge() }, onRightEdge: { setControls(true) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityHidden(sidebarOpen)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !launchBrowserMode && browser.popup == nil {
                ZStack(alignment: .top) {
                    // Keep keyboard layout independent of page loading state.
                    Group {
                        if controlsExpanded {
                            expandedControls.transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            collapsedControls.transition(.opacity)
                        }
                    }
                    if browser.loading {
                        ProgressView().progressViewStyle(.linear)
                            .frame(height: 2)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Loading")
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: controlsExpanded ? 50 : 26, alignment: .center)
                .background(Color(uiColor: .systemBackground))
                .clipped()
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.20), value: controlsExpanded)
            }
        }
        .overlay(alignment: .leading) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    if sidebarOpen {
                        Color.black.opacity(0.28).ignoresSafeArea()
                            .onTapGesture { sidebarOpen = false }
                            .accessibilityLabel("Close conversations")
                            .transition(.opacity)
                        ConversationHub(browser: browser, onClose: { sidebarOpen = false }, onSettings: { sidebarOpen = false; panel = .settings })
                            .frame(width: min(360, max(220, proxy.size.width - 32)))
                            .frame(maxHeight: .infinity)
                            .background(Color(uiColor: .systemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .padding(.vertical, 4)
                            .shadow(color: .black.opacity(0.12), radius: 10, x: 3, y: 0)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                            .accessibilityAddTraits(.isModal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: sidebarOpen)
            }.allowsHitTesting(sidebarOpen)
        }
        .preferredColorScheme(nil)
        .sheet(item: $panel) { sheet in
            switch sheet {
            case .settings: SettingsView(browser: browser)
            case .downloads: DownloadsView(browser: browser)
            case .prompts: PromptTools()
            case .browserMode: SafariSurface(start: homeURL).ignoresSafeArea()
            case .externalBrowser:
                if let url = externalStart { SafariSurface(start: url).ignoresSafeArea() }
            case .bookmarks: ConversationHub(browser: browser)
            }
        }
        .onChange(of: browser.externalURL) { url in
            guard let url else { return }
            if !appLock || !locked { externalStart = url; panel = .externalBrowser }
            browser.externalURL = nil
        }
        .overlay(alignment: .top) {
            if let message = browser.downloadMessage {
                Button { browser.downloadMessage = nil; panel = .downloads } label: {
                    Label(message + " · Open", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold)).padding(10)
                        .background(.regularMaterial, in: Capsule())
                }.padding(.top, 8)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if browser.downloadMessage == message { browser.downloadMessage = nil }
                    }
                }
            }
        }
        .overlay {
            if (privacy && scenePhase != .active) || (appLock && locked) {
                ZStack {
                    Color(uiColor: .systemBackground).ignoresSafeArea()
                    VStack(spacing: 18) {
                        Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 44))
                        Text("Next Chat").font(.largeTitle.bold())
                        if appLock && locked { Button("Unlock", action: unlock).buttonStyle(.borderedProminent) }
                    }
                }.accessibilityAddTraits(.isModal)
            }
        }
        .confirmationDialog("Complete sign-in in one browser", isPresented: $browser.loginHelp, titleVisibility: .visible) {
            Button("Restart sign-in in Next Chat") { browser.restartLogin() }
            Button("Browser mode (separate session)") { showBrowser() }
            Button("Direct mode login help") { showDirectLoginHelp = true }
            Button("Reset embedded sign-in") { confirmResetLogin = true }
            Button("Always start in browser mode") { launchBrowserMode = true; showBrowser() }
            Button("Open ChatGPT in Safari") { browser.safariLogin() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Google requires a supported system browser. Direct mode can use your existing OpenAI password if enabled, or an account's supported sign-in method. Safari sessions remain separate.\n\n\(browser.diagnostic)")
        }
        .alert("Next Chat", isPresented: Binding(get: { browser.notice != nil && (!appLock || !locked) }, set: { if !$0 { browser.notice = nil } })) { Button("OK", role: .cancel) { browser.notice = nil } } message: { Text(browser.notice ?? "") }
        .alert("Attachment not ready", isPresented: Binding(get: { browser.attachmentIssue != nil && (!appLock || !locked) }, set: { if !$0 { browser.attachmentIssue = nil } })) {
            Button("Open conversation in Safari") { browser.openAttachmentInSafari() }
            Button("Copy regeneration request") { browser.copyAttachmentRequest() }
            Button("Close", role: .cancel) { browser.attachmentIssue = nil }
        } message: {
            Text([browser.attachmentIssue?.filename, browser.attachmentIssue?.reason, "Safari may require its own sign-in."].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n"))
        }
        .alert("Direct mode sign-in", isPresented: $showDirectLoginHelp) {
            Button("Try direct sign-in") { launchBrowserMode = false; browser.restartLogin() }
            Button("Open account in Browser mode") { showBrowser() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use your existing ChatGPT account email and password if available. For accounts originally using Google or Apple, check Settings → Security and login → Password → Add in your signed-in ChatGPT account. Do not create a new account. If using Apple, select your original Apple account. Google sign-in is not supported in embedded WebKit.")
        }
        .confirmationDialog("Reset Next Chat website data?", isPresented: $confirmResetLogin, titleVisibility: .visible) {
            Button("Reset embedded sign-in", role: .destructive) { browser.resetSignIn() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears this app's local website cookies and cache only. Your account conversations, downloads and Safari session are not deleted.")
        }
        .onAppear {
            if !appLock { locked = false }
            if !appLock { startPreferredMode() }
        }
        .onChange(of: appLock) { value in locked = value; if value { sidebarOpen = false; panel = nil; didLaunchBrowser = false; unlock() } }
        .onChange(of: launchBrowserMode) { value in sidebarOpen = false; controlsExpanded = false; if !value { browser.startEmbeddedIfNeeded() } }
        .onChange(of: panel) { value in if value != nil { sidebarOpen = false; controlsExpanded = false } }
        .onChange(of: browser.popupHost) { _ in if browser.popup != nil { sidebarOpen = false } }
        .onChange(of: scenePhase) { phase in
            if phase == .background { sidebarOpen = false; if privacy && panel != .browserMode { panel = nil }; inactiveSince = Date(); if appLock && lockDelay == 0 { panel = nil; locked = true; didLaunchBrowser = false } }
            if phase == .active, let date = inactiveSince {
                inactiveSince = nil
                if appLock && Date().timeIntervalSince(date) >= Double(lockDelay) { panel = nil; locked = true; didLaunchBrowser = false }
            }
        }
        .onOpenURL { url in if url.scheme == "nextchat" { handle(url.host ?? "") } }
        .onReceive(NotificationCenter.default.publisher(for: .nextChatShortcut)) { note in if let route = note.object as? String { handle(route) } }
    }
}
extension Notification.Name { static let nextChatShortcut = Notification.Name("NextChatShortcut") }
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(type: "new", localizedTitle: "New chat", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "square.and.pencil")),
            UIApplicationShortcutItem(type: "resume", localizedTitle: "Resume chat", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "clock")),
            UIApplicationShortcutItem(type: "downloads", localizedTitle: "Downloads", localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "arrow.down.circle"))
        ]
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShortcutSceneDelegate.self
        return config
    }
}
final class ShortcutSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        NotificationCenter.default.post(name: .nextChatShortcut, object: shortcutItem.type); completionHandler(true)
    }
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NotificationCenter.default.post(name: .nextChatShortcut, object: item.type) } }
    }
}
@main struct NextChatApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { WindowGroup { RootView() } }
}
