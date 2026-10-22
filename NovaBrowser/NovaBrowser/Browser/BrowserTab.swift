import Combine
import Foundation
import UIKit
import WebKit

final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    let isPrivate: Bool
    @Published private(set) var title: String = "New Tab"
    @Published private(set) var address: String = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isSuspended = false

    var onVisit: ((String, String, Bool) -> Void)?
    var onPopupWithConfiguration: ((WKWebViewConfiguration, Bool) -> WKWebView?)?
    private let inheritedConfiguration: WKWebViewConfiguration?
    var onChanged: (() -> Void)?
    var onDownload: ((DownloadEntry) -> Void)?
    var onError: ((String) -> Void)?
    var resolveSite: ((String) -> ResolvedSiteSettings)?
    var compatibilityShimsEnabled: (() -> Bool)?
    private var appearance: BrowserAppearance = .system
    private var cachedWebView: WKWebView?
    var webView: WKWebView {
        if let cachedWebView { return cachedWebView }
        let instance = makeWebView()
        cachedWebView = instance
        return instance
    }

    private let downloads = DownloadCoordinator()
    private var observations: [NSKeyValueObservation] = []

    init(id: UUID = UUID(), isPrivate: Bool = false, configuration: WKWebViewConfiguration? = nil) {
        self.id = id
        self.isPrivate = isPrivate
        self.inheritedConfiguration = configuration
        super.init()
        downloads.onSaved = { [weak self] entry in self?.onDownload?(entry) }
        downloads.onFailed = { [weak self] message in self?.onError?(message) }
    }

    private func makeWebView() -> WKWebView {
        LaunchDiagnostics.record("Creating WebKit view")
        // WKUIDelegate requires pop-ups to use exactly its supplied configuration.
        // This preserves window.opener relationships and the parent's web session.
        let configuration = inheritedConfiguration ?? WKWebViewConfiguration()
        if inheritedConfiguration == nil {
            configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        }
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.limitsNavigationsToAppBoundDomains = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if inheritedConfiguration == nil && (compatibilityShimsEnabled?() ?? true) {
            configuration.userContentController.addUserScript(WKUserScript(source: LegacyWebKitPolyfills.source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        let web = WKWebView(frame: .zero, configuration: configuration)
        let targetHost = URL(string: address)?.host ?? ""
        let resolved = resolveSite?(targetHost) ?? SiteSettingsResolver.resolve(host: targetHost, global: GlobalSiteSettings(), sites: [])
        web.customUserAgent = UserAgentIdentity.value(for: resolved.userAgentPreset, desktop: resolved.desktopMode)
        web.configuration.defaultWebpagePreferences.preferredContentMode = resolved.desktopMode ? .desktop : .mobile
        web.configuration.defaultWebpagePreferences.allowsContentJavaScript = resolved.javaScriptEnabled
        web.overrideUserInterfaceStyle = appearance.userInterfaceStyle
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = self
        web.uiDelegate = self
        web.scrollView.alwaysBounceVertical = true
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(reloadFromPull(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh
        if #available(iOS 16.4, *) { web.isInspectable = true }
        observations = [
            web.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                self?.progress = view.estimatedProgress
            },
            web.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                self?.isLoading = view.isLoading
            },
            web.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                self?.canGoBack = view.canGoBack
            },
            web.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                self?.canGoForward = view.canGoForward
            },
            web.observe(\.title, options: [.new]) { [weak self] view, _ in
                self?.title = view.title?.isEmpty == false ? view.title! : "New Tab"
                self?.onChanged?()
            },
            web.observe(\.url, options: [.new]) { [weak self] view, _ in
                self?.address = view.url?.absoluteString ?? ""
                self?.onChanged?()
            }
        ]
        LaunchDiagnostics.record("WebKit view created")
        return web
    }

    func restore(_ url: URL, title restoredTitle: String) {
        address = url.absoluteString
        title = restoredTitle
        isSuspended = true
    }

    func resume() {
        guard isSuspended, let url = URL(string: address) else { return }
        load(url)
    }

    func load(_ url: URL) {
        isSuspended = false
        if url.scheme == "http" || url.scheme == "https" {
            address = url.absoluteString
            applySiteSettings(for: url.host ?? "")
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
        }
    }

    func updateAppearance(_ mode: BrowserAppearance) {
        appearance = mode
        cachedWebView?.overrideUserInterfaceStyle = mode.userInterfaceStyle
    }

    func applySiteSettings(for host: String) {
        let resolved = resolveSite?(host) ?? SiteSettingsResolver.resolve(host: host, global: GlobalSiteSettings(), sites: [])
        if let cachedWebView {
            cachedWebView.customUserAgent = UserAgentIdentity.value(for: resolved.userAgentPreset, desktop: resolved.desktopMode)
            cachedWebView.configuration.defaultWebpagePreferences.allowsContentJavaScript = resolved.javaScriptEnabled
            cachedWebView.configuration.defaultWebpagePreferences.preferredContentMode = resolved.desktopMode ? .desktop : .mobile
        }
    }

    func reloadWithCompatibility() {
        if let host = URL(string: address)?.host {
            applySiteSettings(for: host)
            cachedWebView?.reload()
        }
    }


    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }
    func zoom(_ value: CGFloat) { webView.pageZoom = value }

    @objc private func reloadFromPull(_ sender: UIRefreshControl) { reload() }

    private func finish(_ web: WKWebView) {
        web.scrollView.refreshControl?.endRefreshing()
        let current = web.url?.absoluteString ?? ""
        if !current.isEmpty {
            onVisit?(current, web.title ?? current, isPrivate)
            onChanged?()
        }
    }
}

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        WebDiagnostics.record(host: webView.url?.host ?? "unknown", event: "Navigation started")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        WebDiagnostics.record(host: webView.url?.host ?? "unknown", event: "Document loaded")
        finish(webView)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        WebDiagnostics.record(host: webView.url?.host ?? "unknown", event: "Server redirect")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        WebDiagnostics.record(host: webView.url?.host ?? "unknown", event: "Web content process terminated")
        onError?("The webpage process stopped. Tap Reload to retry. This may be a WebKit memory limit on iOS 16.")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        let e = error as NSError
        WebDiagnostics.record(host: webView.url?.host ?? "unknown", event: "Navigation failure: \(e.domain) code \(e.code)")
        onError?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        webView.scrollView.refreshControl?.endRefreshing()
        let e = error as NSError
        if e.code != NSURLErrorCancelled {
            WebDiagnostics.record(host: webView.url?.host ?? "unknown", event: "Provisional failure: \(e.domain) code \(e.code)")
            onError?(error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        let host = navigationAction.request.url?.host ?? webView.url?.host ?? ""
        let resolved = resolveSite?(host) ?? SiteSettingsResolver.resolve(host: host, global: GlobalSiteSettings(), sites: [])
        preferences.allowsContentJavaScript = resolved.javaScriptEnabled
        preferences.preferredContentMode = resolved.desktopMode ? .desktop : .mobile
        self.webView(webView, decidePolicyFor: navigationAction) { decision in
            decisionHandler(decision, preferences)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let requestURL = navigationAction.request.url
        if let scheme = requestURL?.scheme?.lowercased(), !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            onError?("External link requires another app: \(scheme):")
            decisionHandler(.cancel)
            return
        }
        if let targetHost = requestURL?.host {
            applySiteSettings(for: targetHost)
        }
        if navigationAction.targetFrame == nil {
            let settings = resolveSite?(webView.url?.host ?? "") ?? SiteSettingsResolver.resolve(host: "", global: GlobalSiteSettings(), sites: [])
            let request = PopupRequest(sourceHost: webView.url?.host ?? "", targetURL: requestURL,
                                       isUserInitiated: navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted)
            // A genuinely new WKWebView is supplied by createWebViewWith.
            // Returning .allow here is necessary for OAuth windows that rely on window.opener.
            decisionHandler(PopupPolicy.decide(request, settings: settings) == .allow ? .allow : .cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if !navigationResponse.canShowMIMEType || navigationResponse.response.suggestedFilename.map({ name in
            let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
            return disposition.lowercased().contains("attachment") && !name.isEmpty
        }) == true {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = downloads
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = downloads
    }
}

extension BrowserTab: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let settings = resolveSite?(webView.url?.host ?? "") ?? SiteSettingsResolver.resolve(host: "", global: GlobalSiteSettings(), sites: [])
        let request = PopupRequest(sourceHost: webView.url?.host ?? "", targetURL: navigationAction.request.url,
                                   isUserInitiated: navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted)
        guard PopupPolicy.decide(request, settings: settings) == .allow else { return nil }
        return onPopupWithConfiguration?(configuration, isPrivate)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let controller = BrowserPresentation.topViewController() else { completionHandler(); return }
        let alert = UIAlertController(title: webView.url?.host ?? "Website", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        controller.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let controller = BrowserPresentation.topViewController() else { completionHandler(false); return }
        let alert = UIAlertController(title: webView.url?.host ?? "Website", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        controller.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let controller = BrowserPresentation.topViewController() else { completionHandler(nil); return }
        let alert = UIAlertController(title: webView.url?.host ?? "Website", message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text) })
        controller.present(alert, animated: true)
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
}

enum BrowserPresentation {
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let root = scenes.flatMap({ $0.windows }).first(where: \.isKeyWindow)?.rootViewController else { return nil }
        var controller = root
        while let presented = controller.presentedViewController { controller = presented }
        return controller
    }
}
