import SwiftUI
import WebKit
import SafariServices
import Combine
import GoogleCast

private struct NextCastSafariPage: Identifiable {
    let id = UUID()
    let url: URL
}

// An in-app Safari browser uses Apple's supported Safari playback path.
// Its cookies and downloaded media are not accessible to Next Cast.
private struct NextCastSafariPlayer: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let view = SFSafariViewController(url: url)
        view.dismissButtonStyle = .done
        return view
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}


@MainActor
final class NextCastPlaybackLog {
    static let shared = NextCastPlaybackLog()
    private var lines: [String] = []

    func append(_ event: String, _ detail: String = "") {
        // Never deliberately record complete URLs, cookies, or page contents.
        let safe = detail.replacingOccurrences(of: #"https?://\S+"#,
            with: "[url]", options: .regularExpression)
        lines.append("[\(ISO8601DateFormatter().string(from: Date()))] \(event): \(String(safe.prefix(250)))")
        if lines.count > 400 { lines.removeFirst(lines.count - 400) }
    }

    func exportFile() -> URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let legacy = UserDefaults.standard.object(forKey: "nextcast.ios16LegacyWebKit") as? Bool ?? true
        let detailed = UserDefaults.standard.bool(forKey: "nextcast.detailedVideoDiagnostics")
        let header = "Next Cast Playback Diagnostic\nVersion: \(version) build \(build)\niOS: \(UIDevice.current.systemVersion)\nLegacy WebKit: \(legacy)\nDetailed logs: \(detailed)\nBuilt-in ad blocker: configurable (exempts video compatibility sites)\nNo media URLs or cookies intentionally collected.\n---\n"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("NextCast-Playback-\(UUID().uuidString.prefix(8)).txt")
        do {
            try (header + lines.joined(separator: "\n") + "\n")
                .write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch { return nil }
    }
}

private struct NextCastPlaybackShareSheet: UIViewControllerRepresentable {
    let fileURL: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}


struct BrowserStreamCandidate: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let contentType: String
    let referer: String

    var typeSummary: String {
        contentType + " • " + (url.host ?? "remote")
    }
}

private struct BrowserStreamVLCPlayer: View {
    let candidate: BrowserStreamCandidate
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = VLCPlayback()
    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VLCVideoSurface(player: player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .background(.black)
                Text(candidate.title).font(.headline).lineLimit(2)
                Text(candidate.typeSummary).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    Button { player.skip(-10) } label: { Image(systemName: "gobackward.10") }
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                    }
                    Button { player.skip(10) } label: { Image(systemName: "goforward.10") }
                }
                .font(.title2)
                Text("VLC supports additional media formats, but the site must permit direct access to the stream.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .navigationTitle("Try VLC Stream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                player.open(candidate.url)
                player.play()
                NextCastPlaybackLog.shared.append("vlc-web-attempt",
                    "host=\(candidate.url.host ?? "-") format=\(candidate.contentType)")
            }
            .onReceive(refreshTimer) { _ in player.refresh() }
            .onDisappear { player.stop() }
        }
    }
}

private struct BrowserCastPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> GCKUICastButton {
        let button = GCKUICastButton(frame: .init(x: 0, y: 0, width: 42, height: 42))
        button.tintColor = .systemTeal
        return button
    }
    func updateUIView(_ uiView: GCKUICastButton, context: Context) {}
}

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

struct BrowserPlayingMedia: Equatable {
    let url: URL
    let referer: String
    let title: String
    let tabID: UUID

    var isDirectHTTPFile: Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        return ["mp4", "m4v", "mov", "mkv", "webm", "avi"].contains(url.pathExtension.lowercased())
    }
}

@MainActor
final class BrowserPage: Identifiable {
    // Runs inside video-provider iframes too; never reads cookies or page contents.
    private static let mediaObserverScript = #"""
    (function () {
      if (window.__nextCastVideoObserverInstalled) return;
      window.__nextCastVideoObserverInstalled = true;
      function publish(event) {
        var video = event.target;
        if (!video || video.tagName !== 'VIDEO') return;
        var address = video.currentSrc || video.src || '';
        if (!address) return;
        try {
          window.webkit.messageHandlers.nextcastMedia.postMessage({
            event: event.type,
            url: address,
            referer: window.location.href,
            title: document.title || 'Video'
          });
        } catch (_) {}
      }
      ['playing', 'loadedmetadata', 'pause', 'ended', 'emptied']
        .forEach(function (name) { document.addEventListener(name, publish, true); });
    })();
    """#

    private static let diagnosticScript = #"""
    (function () {
      if (window.__nextCastProbeInstalled) return;
      window.__nextCastProbeInstalled = true;
      function report(kind, info) {
        try {
          window.webkit.messageHandlers.nextcastDiagnostic.postMessage({
            kind: kind, info: String(info || '').slice(0, 180),
            frame: location.hostname || '(none)'
          });
        } catch (_) {}
      }
      report('frame-ready', document.readyState);
      window.addEventListener('error', function (event) {
        report('js-error', event.message || 'resource-error');
      }, true);
      window.addEventListener('unhandledrejection', function (event) {
        report('promise-rejection', String(event.reason || 'unknown'));
      });
      ['play', 'playing', 'waiting', 'stalled', 'error'].forEach(function (name) {
        document.addEventListener(name, function (event) {
          if (event.target && event.target.tagName === 'VIDEO') {
            var v = event.target;
            report('video-' + name, 'ready=' + v.readyState +
                   ',network=' + v.networkState +
                   ',code=' + (v.error ? v.error.code : 0));
          }
        }, true);
      });
      document.addEventListener('click', function (event) {
        var el = event.target;
        if (el && el.closest && el.closest('button,[role=button],video')) {
          report('player-click', el.tagName || 'element');
        }
      }, true);
    })();
    """#
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
        // The browser restores controlled ad filters. Playback domains can
        // opt out; intrusive popup windows are blocked separately.
        config.userContentController.removeAllContentRuleLists()
        // iOS 16 defaults to the 1.4.0-era minimal WKWebView media setup.
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.allowsInlineMediaPlayback = true
        let legacyOption = UserDefaults.standard.object(forKey: "nextcast.ios16LegacyWebKit") as? Bool ?? true
        let legacy = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 16 && legacyOption
        let detailed = UserDefaults.standard.bool(forKey: "nextcast.detailedVideoDiagnostics")
        let handler = NextWebDelegate(store: store)
        if !legacy {
            config.allowsPictureInPictureMediaPlayback = true
            config.allowsAirPlayForMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        if !legacy || detailed {
            config.userContentController.add(handler, name: "nextcastMedia")
            config.userContentController.addUserScript(
                WKUserScript(source: Self.mediaObserverScript,
                             injectionTime: .atDocumentStart, forMainFrameOnly: false)
            )
        }
        if detailed {
            config.userContentController.add(handler, name: "nextcastDiagnostic")
            config.userContentController.addUserScript(
                WKUserScript(source: Self.diagnosticScript,
                             injectionTime: .atDocumentStart, forMainFrameOnly: false)
            )
        }
        let view = WKWebView(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) { view.isInspectable = true }
        NextCastPlaybackLog.shared.append("browser-init",
             "ios=\(UIDevice.current.systemVersion) legacy=\(legacy) detailed=\(detailed) filters=none")
        webView = view
        delegate = handler
        address = url.absoluteString
        view.navigationDelegate = handler
        view.uiDelegate = handler
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        store.configureBlocking(for: view, initialURL: url)
        view.load(URLRequest(url: url))
    }

    // WebKit MUST receive a view built with its supplied configuration for
    // target=_blank / window.open players. It performs the navigation itself.
    init(store: BrowserStore, popupConfiguration: WKWebViewConfiguration, url: URL?) {
        popupConfiguration.userContentController.removeAllContentRuleLists()
        let view = WKWebView(frame: .zero, configuration: popupConfiguration)
        let handler = NextWebDelegate(store: store)
        webView = view
        delegate = handler
        address = url?.absoluteString ?? "about:blank"
        view.navigationDelegate = handler
        view.uiDelegate = handler
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .automatic
        if let url { store.configureBlocking(for: view, initialURL: url) }
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
    @Published var lastBrowserError: String?
    @Published var playingMedia: BrowserPlayingMedia?
    @Published private(set) var blockedPopupCount = 0
    @Published var bookmarks: [SavedBookmark] = []

    let library: MovieLibrary
    let downloads: BrowserDownloadStore
    private let bookmarkKey = "nextcast.bookmarks.1"
    private var filterGeneration = 0
    var blockAds: Bool { UserDefaults.standard.object(forKey: "browserBlockAds") as? Bool ?? true }
    var blockPopups: Bool { UserDefaults.standard.object(forKey: "nextcast.blockPopups") as? Bool ?? true }
    private let streamingAllowlist = ["play4u.org", "www.play4u.org"]

    private func isVideoCompatibilitySite(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return streamingAllowlist.contains(host)
    }

    func popupBlocked(_ url: URL?) {
        blockedPopupCount += 1
        NextCastPlaybackLog.shared.append("popup-blocked", "host=\(url?.host ?? "-")")
    }

    func configureBlocking(for view: WKWebView, initialURL: URL? = nil) {
        guard blockAds else { return }
        // Only block requests to known advertising domains. Do not block
        // generic media, playlists, image servers, or all third-party scripts.
        let domains = [
            "doubleclick[.]net", "googlesyndication[.]com",
            "adservice[.]google[.]com", "popads[.]net", "popcash[.]net",
            "propellerads[.]com", "exoclick[.]com",
            "adnxs[.]com", "taboola[.]com", "outbrain[.]com"
        ]
        let rules: [[String: Any]] = domains.map {
            ["trigger": [
                "url-filter": ".*" + $0 + ".*",
                "resource-type": ["script", "image", "popup", "ping"],
                // Player sites may use third-party bootstrap scripts.
                "unless-top-url": [".*://([a-z0-9.-]*[.])?play4u[.]org(/.*)?"]
              ],
             "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else { return }
        let generation = filterGeneration
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "NextCastSmartAdBlock-v156", encodedContentRuleList: json
        ) { [weak self, weak view] list, error in
            DispatchQueue.main.async {
                guard let self, let view, let list,
                      self.blockAds, generation == self.filterGeneration else { return }
                // The user may have navigated to a playback compatibility site
                // while the rule list was compiling; WebKit's unless-top-url
                // additionally exempts that site's resources at evaluation.
                view.configuration.userContentController.removeAllContentRuleLists()
                view.configuration.userContentController.add(list)
                NextCastPlaybackLog.shared.append("ad-filter-installed",
                    "site=\(view.url?.host ?? initialURL?.host ?? "-")")
                if view.url != nil { view.reload() }
            }
        }
    }

    func updateProtection() {
        filterGeneration += 1
        blockedPopupCount = 0
        for page in pages {
            page.webView.configuration.userContentController.removeAllContentRuleLists()
            if blockAds { configureBlocking(for: page.webView) }
            else { page.webView.reload() }
        }
    }

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
    var activePlayingMedia: BrowserPlayingMedia? {
        guard let media = playingMedia, media.tabID == selectedID else { return nil }
        return media
    }
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
        if playingMedia?.tabID == id { playingMedia = nil }
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
    func recordNavigationError(_ error: Error, view: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        lastBrowserError = "Web view failed: \(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        NextCastPlaybackLog.shared.append("navigation-failure",
            "domain=\(nsError.domain) code=\(nsError.code)")
        refresh(view: view)
    }


    func reopenActiveWithBrowserMode() {
        guard let id = selectedID,
              let index = pages.firstIndex(where: { $0.id == id }) else { return }
        let oldPage = pages[index]
        let url = oldPage.webView.url ?? URL(string: oldPage.address) ?? URL(string: "https://www.google.com")!
        oldPage.webView.stopLoading()
        let newPage = BrowserPage(store: self, url: url)
        pages[index] = newPage
        if playingMedia?.tabID == id { playingMedia = nil }
        select(newPage.id)
        NextCastPlaybackLog.shared.append("browser-mode-recreated", "host=\(url.host ?? "-")")
    }

    func capturePlaybackSnapshot(completion: @escaping () -> Void) {
        guard let webView = activeWebView else {
            NextCastPlaybackLog.shared.append("snapshot-error", "no active webview")
            completion()
            return
        }
        NextCastPlaybackLog.shared.append("snapshot-start",
            "host=\(webView.url?.host ?? "-") loading=\(webView.isLoading) progress=\(webView.estimatedProgress)")
        let script = #"""
        (function () {
          var videos = document.querySelectorAll('video');
          var v = videos.length ? videos[0] : null;
          var test = document.createElement('video');
          return JSON.stringify({
            documentState: document.readyState,
            videos: videos.length,
            iframes: document.querySelectorAll('iframe').length,
            mediaSource: typeof window.MediaSource,
            managedMediaSource: typeof window.ManagedMediaSource,
            nativeHLS: test.canPlayType('application/vnd.apple.mpegurl'),
            mp4H264: test.canPlayType('video/mp4; codecs="avc1.42E01E"'),
            videoPaused: v ? v.paused : null,
            videoReady: v ? v.readyState : null,
            videoNetwork: v ? v.networkState : null,
            videoError: v && v.error ? v.error.code : 0,
            videoSrcType: v && v.currentSrc ?
              (v.currentSrc.indexOf('blob:') === 0 ? 'blob' :
              v.currentSrc.indexOf('http') === 0 ? 'http' : 'other') : 'none'
          });
        })();
        """#
        webView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async {
                if let error {
                    let ns = error as NSError
                    NextCastPlaybackLog.shared.append("snapshot-js-error",
                        "domain=\(ns.domain) code=\(ns.code)")
                } else {
                    NextCastPlaybackLog.shared.append("snapshot-result",
                        String(describing: result ?? "nil"))
                }
                completion()
            }
        }
    }

    func receiveDiagnostic(_ message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any] else { return }
        let kind = String((payload["kind"] as? String ?? "event").prefix(50))
        let frame = String((payload["frame"] as? String ?? "").prefix(80))
        var info = (payload["info"] as? String ?? "")
        info = info.replacingOccurrences(of: #"https?://\S+"#,
                                         with: "[url]", options: .regularExpression)
        NextCastPlaybackLog.shared.append("frame-\(kind)", "origin=\(frame) \(String(info.prefix(140)))")
    }

    func browserDiagnosis() {
        let detected = activePlayingMedia == nil ? "no HTML5 video detected" : "HTML5 video detected"
        let issue = lastBrowserError ?? "no top-level navigation failure reported"
        showMessage = "Ad filtering: \(blockAds ? "on" : "off"). Pop-up blocking: \(blockPopups ? "on" : "off"), blocked \(blockedPopupCount). Player: \(detected). Browser: \(issue)."
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
        guard let url = prompt.request.url else { return }
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            // Browser clicks often require website cookies and a Referer header.
            // Copy the relevant cookies into an OS-managed background session
            // instead of letting WebKit's foreground-only WKDownload own the file.
            tab.webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                Task { @MainActor in
                    guard let self else { return }
                    var request = prompt.request
                    let host = url.host?.lowercased() ?? ""
                    let permitted = cookies.filter { cookie in
                        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        return host == domain || host.hasSuffix("." + domain)
                    }
                    if !permitted.isEmpty {
                        let fields = HTTPCookie.requestHeaderFields(with: permitted)
                        if let cookieValue = fields["Cookie"] {
                            request.setValue(cookieValue, forHTTPHeaderField: "Cookie")
                        }
                    }
                    if request.value(forHTTPHeaderField: "Referer") == nil,
                       let referer = tab.webView.url?.absoluteString {
                        request.setValue(referer, forHTTPHeaderField: "Referer")
                    }
                    TransferStore.shared.start(request, origin: "Browser")
                    self.showMessage = "Download queued in background manager."
                }
            }
        } else {
            // blob: URLs and in-page generated files cannot be downloaded by
            // the operating-system background HTTP session; try WebKit itself.
            tab.webView.startDownload(using: prompt.request) { [weak self, weak tab] download in
                guard let tab, let self else { return }
                download.delegate = tab.delegate
                self.showMessage = "Website-native download started."
            }
        }
    }
    func openPlayerWindow(configuration: WKWebViewConfiguration,
                          action: WKNavigationAction) -> WKWebView? {
        if blockPopups {
            popupBlocked(action.request.url)
            return nil
        }
        guard pages.count < 16 else {
            showMessage = "Video site opened too many windows (16 tabs maximum)."
            return nil
        }
        if let url = action.request.url {
            guard ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") else {
                return nil
            }
        }
        let page = BrowserPage(store: self, popupConfiguration: configuration,
                               url: action.request.url)
        pages.append(page)
        select(page.id)
        return page.webView
    }

    func receiveVideoMessage(_ message: WKScriptMessage) {
        guard let view = message.webView,
              let page = pages.first(where: { $0.webView === view }),
              let payload = message.body as? [String: Any],
              let raw = payload["url"] as? String,
              let url = URL(string: raw) else { return }
        let event = payload["event"] as? String ?? ""
        if event == "ended" || event == "emptied" {
            if playingMedia?.tabID == page.id && playingMedia?.url == url {
                playingMedia = nil
            }
            return
        }
        guard event == "playing" || event == "loadedmetadata",
              ["http", "https", "blob"].contains(url.scheme?.lowercased() ?? "") else { return }
        playingMedia = BrowserPlayingMedia(
            url: url,
            referer: payload["referer"] as? String ?? "",
            title: payload["title"] as? String ?? "Video",
            tabID: page.id
        )
    }


    /// Captures HTML5 video addresses on demand. Works even if video.error
    /// is already set because iOS 16 WebKit cannot decode the stream.
    func resolveActiveVideo(_ completion: @escaping (BrowserStreamCandidate?) -> Void) {
        guard let webView = activeWebView else {
            showMessage = "Open a webpage containing an HTML5 video first."
            completion(nil)
            return
        }
        let script = #"""
        (function () {
          var videos = Array.from(document.querySelectorAll('video'));
          var video = videos.find(function(v) {
            return !!(v.currentSrc || v.src || v.querySelector('source[src]'));
          }) || videos[0];
          if (!video) return null;
          var firstSource = video.querySelector('source[src]');
          var raw = video.currentSrc || video.src ||
                    (firstSource ? firstSource.src : '') || '';
          if (!raw) return null;
          return {
            url: String(raw),
            type: String(video.getAttribute('type') ||
                         (firstSource ? firstSource.getAttribute('type') : '') || ''),
            title: String(document.title || 'Web Video'),
            referer: String(location.href),
            errorCode: video.error ? video.error.code : 0
          };
        })();
        """#
        webView.evaluateJavaScript(script) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { completion(nil); return }
                guard error == nil, let dict = result as? [String: Any],
                      let raw = dict["url"] as? String,
                      let url = URL(string: raw),
                      ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                    NextCastPlaybackLog.shared.append("video-resolve-failed",
                        "html5_video_url_absent_or_non_http")
                    self.showMessage = "No direct HTTP video stream was found in the current page. This button cannot cast blob, protected, or hidden player sources."
                    completion(nil)
                    return
                }
                let rawMIME = (dict["type"] as? String ?? "")
                    .components(separatedBy: ";").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased() ?? ""
                let ext = url.pathExtension.lowercased()
                let type: String
                switch ext {
                case "m3u8": type = "application/x-mpegurl"
                case "mpd": type = "application/dash+xml"
                case "mp4", "m4v": type = "video/mp4"
                case "webm": type = "video/webm"
                case "ts", "m2ts": type = "video/mp2t"
                case "mov": type = "video/quicktime"
                default:
                    type = rawMIME.isEmpty ? "video/mp4" : rawMIME
                    if rawMIME.isEmpty {
                        NextCastPlaybackLog.shared.append("stream-type-guess",
                            "host=\(url.host ?? "-") assumed=video/mp4")
                    }
                }
                let candidate = BrowserStreamCandidate(
                    url: url,
                    title: (dict["title"] as? String ?? "Web Video"),
                    contentType: type,
                    referer: (dict["referer"] as? String ?? "")
                )
                let code = dict["errorCode"] as? Int ?? 0
                NextCastPlaybackLog.shared.append("video-resolved",
                    "host=\(url.host ?? "-") mime=\(type) mediaError=\(code)")
                completion(candidate)
            }
        }
    }

    func downloadPlayingVideo() {
        guard let media = activePlayingMedia,
              let page = pages.first(where: { $0.id == media.tabID }) else {
            showMessage = "Start playing a video to detect its media address."
            return
        }
        guard media.isDirectHTTPFile else {
            showMessage = "This player uses a stream or protected media address, not a direct downloadable video file. Use the site's own offline option if offered."
            return
        }
        var request = URLRequest(url: media.url)
        if let refererURL = URL(string: media.referer),
           ["http", "https"].contains(refererURL.scheme?.lowercased() ?? "") {
            request.setValue(refererURL.absoluteString, forHTTPHeaderField: "Referer")
        }
        requestDownload(request, view: page.webView)
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

    func reloadUnblockedPage() {
        // Useful if a player needs an entirely unfiltered reload for this tab.
        guard let page = active else { return }
        page.webView.configuration.userContentController.removeAllContentRuleLists()
        lastBrowserError = nil
        page.webView.reload()
    }

}

struct BrowserWebSurface: UIViewRepresentable {
    let page: BrowserPage
    func makeUIView(context: Context) -> WKWebView { page.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
final class NextWebDelegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    weak var store: BrowserStore?
    private var lastRequest: URLRequest?
    init(store: BrowserStore) { self.store = store }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "nextcastMedia" {
            store?.receiveVideoMessage(message)
        } else if message.name == "nextcastDiagnostic" {
            store?.receiveDiagnostic(message)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        NextCastPlaybackLog.shared.append("navigation-start",
            "host=\(webView.url?.host ?? "-")")
        store?.refresh(view: webView)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NextCastPlaybackLog.shared.append("navigation-finish",
            "host=\(webView.url?.host ?? "-")")
        store?.refresh(view: webView)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NextCastPlaybackLog.shared.append("webkit-process-terminated",
            "host=\(webView.url?.host ?? "-")")
        store?.lastBrowserError = "WebKit content process terminated"
        store?.refresh(view: webView)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        store?.recordNavigationError(error, view: webView)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        store?.recordNavigationError(error, view: webView)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        lastRequest = navigationAction.request
        if navigationAction.navigationType == .linkActivated ||
           navigationAction.targetFrame == nil {
            NextCastPlaybackLog.shared.append("navigation-click",
                "host=\(url.host ?? "-") popup=\(navigationAction.targetFrame == nil)")
        }
        // A click on MP4/video is playback unless the website explicitly
        // requests a download (HTML download attribute / WebKit policy).
        if navigationAction.shouldPerformDownload {
            store?.requestDownload(navigationAction.request, view: webView)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            // Allow WebKit's UI delegate to create a real target window.
            decisionHandler(.allow)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        if navigationResponse.isForMainFrame, let http = response as? HTTPURLResponse {
            NextCastPlaybackLog.shared.append("navigation-http",
                "host=\(response.url?.host ?? "-") status=\(http.statusCode) mime=\(response.mimeType ?? "-")")
        }
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
        if navigationAction.shouldPerformDownload {
            store?.requestDownload(navigationAction.request, view: webView)
            return nil
        }
        NextCastPlaybackLog.shared.append("popup-request",
            "host=\(navigationAction.request.url?.host ?? "-")")
        return store?.openPlayerWindow(configuration: configuration, action: navigationAction)
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let store,
              let page = store.pages.first(where: { $0.webView === webView }) else { return }
        store.close(page.id)
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
    @ObservedObject var cast: CastController
    @StateObject private var model: BrowserStore
    @State private var safariPage: NextCastSafariPage?
    @State private var vlcCandidate: BrowserStreamCandidate?
    @AppStorage("nextcast.ios16LegacyWebKit") private var legacyWebKit = true
    @AppStorage("nextcast.detailedVideoDiagnostics") private var detailedVideoLogs = false
    @State private var shareLogFile: URL?
    @State private var showLogShare = false
    @State private var inputURL = ""
    @State private var showBookmarks = false
    @State private var showTabList = false
    var openDownloads: () -> Void

    init(library: MovieLibrary, downloads: BrowserDownloadStore,
         cast: CastController, openDownloads: @escaping () -> Void) {
        self.library = library
        self.downloads = downloads
        self.cast = cast
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
                        .overlay(alignment: .topTrailing) {
                            if let media = model.activePlayingMedia {
                                Button {
                                    model.downloadPlayingVideo()
                                } label: {
                                    Label(media.isDirectHTTPFile ? "Save Video" : "Stream Info",
                                          systemImage: media.isDirectHTTPFile ? "arrow.down.to.line" : "info.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(.regularMaterial, in: Capsule())
                                }
                                .foregroundStyle(.cyan)
                                .padding(12)
                                .accessibilityLabel(media.isDirectHTTPFile ?
                                                    "Save playing video" : "Video stream information")
                            }
                        }
                }

                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 16 && legacyWebKit {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield")
                        Text("iOS 16 Legacy WebKit active")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 4)
                }
                // Always-visible playback actions, even before media detection.
                HStack(spacing: 12) {
                    Button { model.reloadUnblockedPage() } label: {
                        Label("Reload Player", systemImage: "arrow.clockwise.circle")
                    }
                    Spacer(minLength: 4)
                    Button {
                        if let url = model.activeWebView?.url,
                           ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                            safariPage = NextCastSafariPage(url: url)
                        } else {
                            model.showMessage = "Open a website first."
                        }
                    } label: {
                        Label("Safari Player", systemImage: "play.rectangle")
                    }
                    Spacer(minLength: 4)
                    Button { model.downloadPlayingVideo() } label: {
                        Label("Save Video", systemImage: "arrow.down.to.line")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.secondary.opacity(0.07))


                // Remote casting works independently of the phone's WebKit
                // decoder. The receiver itself must support the stream.
                HStack(spacing: 10) {
                    BrowserCastPicker()
                        .frame(width: 42, height: 42)
                        .accessibilityLabel("Select Google Cast TV")
                    Button {
                        if !cast.isConnected {
                            model.showMessage = "First tap the Cast icon to connect your Chromecast or Google Cast TV."
                        } else {
                            model.resolveActiveVideo { candidate in
                                guard let candidate else { return }
                                cast.loadWebStream(candidate.url,
                                    contentType: candidate.contentType,
                                    title: candidate.title)
                            }
                        }
                    } label: {
                        Label("Cast Video", systemImage: "tv.and.hifispeaker.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    Button {
                        model.resolveActiveVideo { candidate in
                            guard let candidate else { return }
                            vlcCandidate = candidate
                        }
                    } label: {
                        Label("Try VLC", systemImage: "play.tv")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)

                if cast.isConnected || cast.nowCastingWebTitle != nil {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(cast.nowCastingWebTitle ?? cast.pendingWebTitle ?? cast.tvName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(cast.castStatus)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 3)
                        if cast.nowCastingWebTitle != nil {
                            Button { cast.togglePlay() } label: {
                                Image(systemName: cast.isPlaying ? "pause.fill" : "play.fill")
                            }
                            Button { cast.stopRemotePlayback() } label: {
                                Image(systemName: "stop.fill")
                            }
                        }
                    }
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 6)
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
            .navigationTitle("Browser · v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reload Unblocked Player", systemImage: "play.rectangle") {
                            model.reloadUnblockedPage()
                        }
                        Button("Save Playing Video", systemImage: "arrow.down.to.line") {
                            model.downloadPlayingVideo()
                        }
                        Button("Cast Current Video to TV", systemImage: "tv") {
                            if !cast.isConnected {
                                model.showMessage = "Tap the TV Cast icon below the video to select a receiver first."
                            } else {
                                model.resolveActiveVideo { candidate in
                                    guard let candidate else { return }
                                    cast.loadWebStream(candidate.url,
                                        contentType: candidate.contentType,
                                        title: candidate.title)
                                }
                            }
                        }
                        Button("Try Video in VLC", systemImage: "play.tv") {
                            model.resolveActiveVideo { candidate in
                                guard let candidate else { return }
                                vlcCandidate = candidate
                            }
                        }
                        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 16 {
                            Toggle("iOS 16 Legacy WebKit (recommended)", isOn: $legacyWebKit)
                        }
                        Toggle("Detailed Player Logging", isOn: $detailedVideoLogs)
                        Button("Export Playback Log", systemImage: "square.and.arrow.up") {
                            model.capturePlaybackSnapshot {
                                shareLogFile = NextCastPlaybackLog.shared.exportFile()
                                if shareLogFile != nil {
                                    showLogShare = true
                                } else {
                                    model.showMessage = "Unable to create playback log."
                                }
                            }
                        }
                        Button("Playback Diagnostics", systemImage: "stethoscope") {
                            model.browserDiagnosis()
                        }
                        Button("Open in Safari Player", systemImage: "safari") {
                            if let url = model.activeWebView?.url,
                               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                                safariPage = NextCastSafariPage(url: url)
                            }
                        }
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
                inputURL = model.currentAddress
            }
            .onChange(of: model.currentAddress) { inputURL = $0 }
            .onChange(of: model.selectedID) { _ in inputURL = model.currentAddress }
            .onChange(of: legacyWebKit) { _ in model.reopenActiveWithBrowserMode() }
            .onChange(of: detailedVideoLogs) { _ in model.reopenActiveWithBrowserMode() }
            .sheet(isPresented: $showLogShare) {
                if let file = shareLogFile { NextCastPlaybackShareSheet(fileURL: file) }
            }
            .sheet(item: $safariPage) { page in
                NextCastSafariPlayer(url: page.url)
                    .ignoresSafeArea()
            }
            .sheet(item: $vlcCandidate) { candidate in
                BrowserStreamVLCPlayer(candidate: candidate)
            }
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
