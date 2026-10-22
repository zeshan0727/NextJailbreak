import UIKit
import WebKit

@MainActor
final class WebViewStore {
    private weak var owner: BrowserModel?
    private var sessions: [UUID: WebSession] = [:]
    private var privateStore = WKWebsiteDataStore.nonPersistent()
    private let regularPool = WKProcessPool()
    private var privatePool = WKProcessPool()

    init(owner: BrowserModel) { self.owner = owner }

    func webView(for tab: BrowserTab, configuration supplied: WKWebViewConfiguration? = nil) -> WKWebView {
        if let session = sessions[tab.id] { return session.webView }
        let config = supplied ?? WKWebViewConfiguration()
        if supplied == nil {
            config.websiteDataStore = tab.isPrivate ? privateStore : .default()
            config.processPool = tab.isPrivate ? privatePool : regularPool
        }
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.limitsNavigationsToAppBoundDomains = false
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // M1 rejects unprompted windows. M2 adds the full configurable blocker.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        view.scrollView.keyboardDismissMode = .interactive
        // This API does not exist on iOS 16.0–16.3.
        if #available(iOS 16.4, *) { view.isInspectable = true }
        let session = WebSession(webView: view, tab: tab, owner: owner)
        sessions[tab.id] = session
        return view
    }

    func existing(for tab: BrowserTab) -> WKWebView? { sessions[tab.id]?.webView }
    func remove(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.invalidate()
    }
    func resetPrivateStore() {
        privateStore = .nonPersistent()
        privatePool = WKProcessPool()
    }
    func captureThumbnail(for tab: BrowserTab) {
        guard !tab.isPrivate, let webView = existing(for: tab), webView.bounds.width > 0, !tab.needsResume else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 320
        webView.takeSnapshot(with: config) { [weak tab] image, _ in
            DispatchQueue.main.async { tab?.thumbnail = image }
        }
    }
    func find(_ query: String, in tab: BrowserTab, backwards: Bool = false) {
        guard !query.isEmpty, let view = existing(for: tab) else { tab.foundMatch = nil; return }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.wraps = true
        config.caseSensitive = false
        view.find(query, configuration: config) { [weak tab] result in tab?.foundMatch = result.matchFound }
    }
    func zoom(_ amount: Double, in tab: BrowserTab) {
        tab.pageZoom = min(2.5, max(0.5, amount))
        existing(for: tab)?.pageZoom = tab.pageZoom
    }
}

@MainActor
private final class WebSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    private weak var tab: BrowserTab?
    private weak var owner: BrowserModel?
    private var observations: [NSKeyValueObservation] = []
    private let refreshControl = UIRefreshControl()
    private var dialogVisible = false

    init(webView: WKWebView, tab: BrowserTab, owner: BrowserModel?) {
        self.webView = webView
        self.tab = tab
        self.owner = owner
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        observations = [
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in self?.scheduleSync() },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleSync() }
        ]
    }
    func invalidate() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.scrollView.refreshControl = nil
    }
    private func scheduleSync() {
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }
    private func sync() {
        guard let tab else { return }
        tab.progress = webView.estimatedProgress
        tab.isLoading = webView.isLoading
        tab.canGoBack = webView.canGoBack
        tab.canGoForward = webView.canGoForward
        if let title = webView.title, !title.isEmpty { tab.title = title }
        if let url = webView.url { tab.url = url }
        if !webView.isLoading { refreshControl.endRefreshing() }
    }
    @objc private func refresh() { webView.reload() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.errorMessage = nil
        tab?.foundMatch = nil
        sync()
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { sync(); owner?.save() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        sync()
        owner?.save()
        if let tab { owner?.webViews.captureThumbnail(for: tab) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        tab?.isLoading = false
        tab?.errorMessage = "iOS stopped this page to reclaim memory. Tap Reload to reopen it."
    }
    private func show(_ error: Error) {
        refreshControl.endRefreshing()
        guard (error as NSError).code != NSURLErrorCancelled else { sync(); return }
        tab?.isLoading = false
        tab?.errorMessage = error.localizedDescription
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob"].contains(scheme) || (scheme == "file" && tab?.isLocalTest == true) {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
        // Never launch arbitrary installed apps from timers or page load events.
        guard navigationAction.navigationType == .linkActivated, ["tel", "mailto", "itms-apps"].contains(scheme) else { return }
        let alert = UIAlertController(title: "Open another app?", message: url.absoluteString, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in UIApplication.shared.open(url) })
        presenter?.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted,
              let url = navigationAction.request.url, ["http", "https"].contains(url.scheme ?? ""),
              let owner, let tab else { return nil }
        let newTab = owner.addTab(isPrivate: tab.isPrivate)
        newTab.url = url
        // Returning this view lets WebKit maintain the opener and POST request.
        let result = owner.webViews.webView(for: newTab, configuration: configuration)
        owner.save()
        return result
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let tab { owner?.close(tab) }
    }

    private var presenter: UIViewController? {
        var view = webView.window?.rootViewController
        while let next = view?.presentedViewController { view = next }
        return view
    }
    private func showDialog(_ alert: UIAlertController, fallback: () -> Void) {
        guard !dialogVisible, let presenter, !presenter.isBeingDismissed else { fallback(); return }
        dialogVisible = true
        presenter.present(alert, animated: true)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.dialogVisible = false; completionHandler() })
        showDialog(alert, fallback: completionHandler)
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.dialogVisible = false; completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.dialogVisible = false; completionHandler(true) })
        showDialog(alert) { completionHandler(false) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: frame.securityOrigin.host, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in self?.dialogVisible = false; completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self, weak alert] _ in self?.dialogVisible = false; completionHandler(alert?.textFields?.first?.text) })
        showDialog(alert) { completionHandler(nil) }
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // WebKit displays a site-specific permission prompt; iOS also asks for OS permission.
        decisionHandler(.prompt)
    }
}
