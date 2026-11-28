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
struct LocalFile: Identifiable {
    let url: URL
    var id: URL { url }
}
struct PendingDownload: Identifiable {
    let id: ObjectIdentifier
    var name: String
    var progress: Double
}
final class Browser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    @Published var loginHelp = false
    @Published var externalURL: URL?
    @Published var downloadDiagnostic = "No downloads yet."
    @Published var downloadMessage: String?
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
    let web: WKWebView
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
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: .zero, configuration: config)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.keyboardDismissMode = .interactive
        web.isOpaque = false
        if let data = UserDefaults.standard.data(forKey: "bookmarks"),
           let decoded = try? JSONDecoder().decode([SavedLink].self, from: data) { bookmarks = decoded.filter { chatPage($0.url) } }
        observations = [
            web.observe(\.isLoading, options: [.initial,.new]) { [weak self] w,_ in DispatchQueue.main.async { self?.loading = w.isLoading } },
            web.observe(\.canGoBack, options: [.initial,.new]) { [weak self] w,_ in DispatchQueue.main.async { self?.canBack = w.canGoBack } },
            web.observe(\.canGoForward, options: [.initial,.new]) { [weak self] w,_ in DispatchQueue.main.async { self?.canForward = w.canGoForward } },
            web.observe(\.url, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async {
                self?.current = w.url
                if let url = w.url, chatPage(url), url.path.hasPrefix("/c/") || url.path.hasPrefix("/g/") {
                    UserDefaults.standard.set(url.absoluteString, forKey: "lastChat")
                }
            } },
            web.observe(\.title, options: [.new]) { [weak self] w,_ in DispatchQueue.main.async { self?.pageTitle = w.title ?? "ChatGPT" } }
        ]
        monitor.pathUpdateHandler = { [weak self] path in DispatchQueue.main.async { self?.online = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "nextchat.network"))
        refreshFiles()
        if !(UserDefaults.standard.object(forKey: "preferSystemBrowserV5") as? Bool ?? false) { startEmbeddedIfNeeded() }
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
    func open(_ url: URL) { guard chatPage(url) else { return }; web.load(URLRequest(url: url)) }
    func newChat() { closePopup(); open(homeURL) }
    func restartLogin() {
        closePopup()
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
    func savePage() {
        guard let current, chatPage(current), current.path != "/" else { notice = "Open a conversation before saving it."; return }
        if bookmarks.contains(where: { $0.url == current }) { notice = "Already saved."; return }
        bookmarks.insert(SavedLink(title: pageTitle, url: current), at: 0); persistBookmarks()
    }
    func removeBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; persistBookmarks() }
    private func persistBookmarks() { if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: "bookmarks") } }
    func clearCache(all: Bool) {
        if all { closePopup(); web.stopLoading() }
        let types: Set<String> = all ? WKWebsiteDataStore.allWebsiteDataTypes() : [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        web.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            if all { UserDefaults.standard.removeObject(forKey: "lastChat"); self?.newChat() }
            self?.notice = all ? "Local website data cleared." : "Cache cleared."
        }
    }
    private func external(_ url: URL) {
        guard ["http","https"].contains(url.scheme ?? "") else { return }
        if UserDefaults.standard.string(forKey: "externalLinkMode") == "Safari" { UIApplication.shared.open(url) }
        else { externalURL = url }
    }
    private func beginFile(_ request: URLRequest, in view: WKWebView) {
        downloadDiagnostic = "Starting download in website session."
        view.startDownload(using: request) { [weak self] download in
            guard let self else { return }
            self.downloadViews[ObjectIdentifier(download)] = view
            self.register(download)
        }
    }
    private func isFileView(_ view: WKWebView) -> Bool { fileViews[ObjectIdentifier(view)] != nil }
    private func fileRoute(_ request: URLRequest, from view: WKWebView) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = view.configuration.websiteDataStore
        let child = WKWebView(frame: .zero, configuration: config)
        child.navigationDelegate = self
        fileViews[ObjectIdentifier(child)] = child
        downloadDiagnostic = "Resolving attachment."
        child.load(request)
    }
    private func releaseFileView(_ view: WKWebView) { fileViews.removeValue(forKey: ObjectIdentifier(view)) }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        // Never bridge WKFrameInfo.request on iOS 16.
        let source = webView.url
        let scheme = url.scheme?.lowercased() ?? ""
        let fromChat = official(source)
        let appleSignIn = appleIdentity(url) && (fromChat || appleIdentity(source) || webView === popup)
        let auth = authPage(source) || appleIdentity(source) || identityProvider(url)
        if action.shouldPerformDownload && !auth && (scheme == "https" || (fromChat && ["blob","data"].contains(scheme))) {
            decisionHandler(.download); return
        }
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if isFileView(webView) {
            decisionHandler(scheme == "https" ? .allow : .cancel); return
        }
        if scheme == "sandbox" && fromChat {
            decisionHandler(.cancel)
            downloadDiagnostic = "Unresolved sandbox reference."
            notice = "The website did not resolve this file link. Ask ChatGPT to regenerate the attachment."
            return
        }
        if !auth && fromChat && fileHost(url) {
            decisionHandler(.cancel)
            fileRoute(action.request, from: webView); return
        }
        if !auth && fromChat && fileLink(url) && action.navigationType == .linkActivated {
            decisionHandler(.cancel)
            beginFile(action.request, in: webView); return
        }
        if scheme == "blob" && fromChat && action.navigationType == .linkActivated {
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
        if !auth && fromChat && (action.shouldPerformDownload || url.scheme == "blob" || fileLink(url)) && ["https","blob","data"].contains(url.scheme ?? "") {
            beginFile(action.request, in: webView); return nil
        }
        if !auth && fromChat && fileHost(url) {
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
            downloadDiagnostic = "Unresolved sandbox reference."
            notice = "Ask ChatGPT to regenerate the attachment."
        } else if action.navigationType == .linkActivated || fromChat { external(url) }
        return nil
    }
    func webViewDidClose(_ webView: WKWebView) {
        if webView === popup { closePopup() }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === popup { popupHost = webView.url?.host ?? "Official sign-in" }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if authPage(webView.url), webView.url?.path.lowercased().contains("error") == true {
            loginHelp = true
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { notice = "Web content stopped. Reload to recover your session." }
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
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { downloadViews[ObjectIdentifier(download)] = webView; register(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { downloadViews[ObjectIdentifier(download)] = webView; register(download) }
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
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let id = ObjectIdentifier(download)
        do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch { completionHandler(nil); notice = "Cannot create download folder."; return }
        let sanitized = (suggestedFilename as NSString).lastPathComponent
        let name = sanitized.isEmpty || sanitized == "." || sanitized == ".." ? "Download" : sanitized
        var dest = folder.appendingPathComponent(name)
        if fm.fileExists(atPath: dest.path) || destinations.values.contains(dest) { dest = folder.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + name) }
        destinations[id] = dest
        if let i = active.firstIndex(where: { $0.id == id }) { active[i].name = name }
        completionHandler(dest)
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
struct WebSurface: UIViewRepresentable {
    let browser: Browser
    func makeUIView(context: Context) -> WKWebView { browser.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
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
struct PromptTools: View {
    @StateObject private var dictation = Dictation()
    @AppStorage("favoritePrompts") private var favorites = "Review this code for bugs.\nSummarize the key findings."
    @State private var selectedText = ""
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
    @Environment(\.dismiss) private var dismiss
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
                Section("Saved files") {
                    if browser.files.isEmpty { Text("Downloaded files appear here.").foregroundStyle(.secondary) }
                    ForEach(browser.files) { file in
                        Button { preview = file } label: { Label(file.url.lastPathComponent, systemImage: "doc") }
                            .contextMenu {
                                ShareLink(item: file.url)
                                Button("Rename") { name = file.url.lastPathComponent; editing = file }
                                Button("Delete", role: .destructive) { browser.delete(file) }
                            }
                            .swipeActions { Button("Delete", role: .destructive) { browser.delete(file) } }
                    }
                }
            }.navigationTitle("Downloads").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
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
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("restore") private var restore = true
    @AppStorage("externalLinkMode") private var externalLinkMode = "In-app browser"
    @AppStorage("appLock") private var appLock = false
    @AppStorage("privacy") private var privacy = true
    @AppStorage("lockDelay") private var lockDelay = 0
    @State private var confirm = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Appearance", selection: $appearance) { ForEach(["System","Light","Dark"], id: \.self) { Text($0) } }
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Restore last conversation", isOn: $restore)
                    Picker("Website links", selection: $externalLinkMode) {
                        Text("In-app browser").tag("In-app browser")
                        Text("Safari").tag("Safari")
                    }
                }
                Section("Privacy") {
                    Toggle("App switcher privacy", isOn: $privacy)
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
                Section("Connection") {
                    LabeledContent("Network", value: browser.online ? "Available" : "Offline")
                    Button("Reload ChatGPT") { browser.web.reload(); dismiss() }
                    Button("Restart sign-in") { browser.restartLogin(); dismiss() }
                    Text(browser.diagnostic).font(.caption).textSelection(.enabled)
                    Text(browser.downloadDiagnostic).font(.caption).textSelection(.enabled)
                    ShareLink(item: browser.downloadDiagnostic) { Label("Share download diagnostics", systemImage: "square.and.arrow.up") }
                    ShareLink(item: browser.diagnostic) { Label("Share login diagnostics", systemImage: "square.and.arrow.up") }
                    Button("Open in Safari") { browser.safariLogin() }
                    ShareLink(item: "Next Chat 1.0.0 (7)\niOS \(UIDevice.current.systemVersion)\nNetwork: \(browser.online ? "available" : "offline")\nNo account or session information included.") { Label("Share diagnostics", systemImage: "square.and.arrow.up") }
                }
                Section("About") {
                    LabeledContent("Version", value: "1.0.0 (7)")
                    Text("Unofficial companion. Conversations and authentication are provided by the ChatGPT website. Safari sessions are separate. No additional API subscription is used. Local bookmarks and downloads are stored on this device.")
                    Link("OpenAI privacy policy", destination: URL(string: "https://openai.com/policies/privacy-policy/")!)
                }
            }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear local website data and sign out of this web session?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Clear data", role: .destructive) { browser.clearCache(all: true) }
            }
        }
    }
}
enum Panel: String, Identifiable { case settings, downloads, prompts, bookmarks, browserMode, externalBrowser; var id: String { rawValue } }
struct RootView: View {
    @StateObject private var browser = Browser()
    @AppStorage("appearance") private var appearance = "System"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("privacy") private var privacy = true
    @AppStorage("appLock") private var appLock = false
    @AppStorage("lockDelay") private var lockDelay = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var panel: Panel?
    @State private var externalStart: URL?
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
    private func showBrowser() {
        guard !appLock || !locked else { pendingRoute = "resume"; return }
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
                WebSurface(browser: browser).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !launchBrowserMode {
                VStack(spacing: 0) {
                if browser.loading { ProgressView().progressViewStyle(.linear) }
                Divider()
                HStack(spacing: 18) {
                Button { tap(); browser.web.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!browser.canBack).accessibilityLabel("Back")
                Button { tap(); browser.web.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!browser.canForward).accessibilityLabel("Forward")
                Spacer(minLength: 0)
                Button { tap(); browser.newChat() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New chat")
                Button { tap(); panel = .downloads } label: {
                    Image(systemName: "arrow.down.circle").overlay(alignment: .topTrailing) {
                        if !browser.active.isEmpty { Circle().fill(Color.accentColor).frame(width: 7, height: 7) }
                    }
                }.accessibilityLabel("Downloads")
                Menu {
                    Button { browser.resume() } label: { Label("Resume conversation", systemImage: "clock") }
                    Button { browser.savePage() } label: { Label("Save current page", systemImage: "bookmark") }
                    Button { panel = .bookmarks } label: { Label("Saved conversations", systemImage: "books.vertical") }
                    Button { panel = .prompts } label: { Label("Prompt tools", systemImage: "text.bubble") }
                    Button { browser.web.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Button { browser.restartLogin() } label: { Label("Restart sign-in", systemImage: "person.crop.circle.badge.exclamationmark") }
                    Button { showDirectLoginHelp = true } label: { Label("Direct mode login help", systemImage: "questionmark.circle") }
                    Button { showBrowser() } label: { Label("Browser mode", systemImage: "globe") }
                    Button { launchBrowserMode = true; showBrowser() } label: { Label("Make Browser mode default", systemImage: "globe") }
                    Button { confirmResetLogin = true } label: { Label("Reset embedded sign-in", systemImage: "arrow.counterclockwise") }
                    Button { browser.safari() } label: { Label("Open in Safari", systemImage: "safari") }
                    Button { panel = .settings } label: { Label("Settings", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("More")
                }.font(.system(size: 21, weight: .medium)).padding(.horizontal, 22).frame(height: 46)
                }.fixedSize(horizontal: false, vertical: true).background(.regularMaterial)
            }
        }
        .preferredColorScheme(appearance == "Dark" ? .dark : appearance == "Light" ? .light : nil)
        .sheet(item: $panel) { sheet in
            switch sheet {
            case .settings: SettingsView(browser: browser)
            case .downloads: DownloadsView(browser: browser)
            case .prompts: PromptTools()
            case .browserMode: SafariSurface(start: homeURL).ignoresSafeArea()
            case .externalBrowser:
                if let url = externalStart { SafariSurface(start: url).ignoresSafeArea() }
            case .bookmarks:
                NavigationStack {
                    List {
                        if browser.bookmarks.isEmpty { Text("Save a conversation from the More menu. All account history is in ChatGPT's own sidebar.").foregroundStyle(.secondary) }
                        ForEach(browser.bookmarks.filter { bookmarkSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(bookmarkSearch) }) { item in
                            Button(item.title) { browser.open(item.url); panel = nil }.swipeActions { Button("Remove", role: .destructive) { browser.removeBookmark(item.id) } }
                        }
                    }.searchable(text: $bookmarkSearch).navigationTitle("Saved conversations").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { panel = nil } } }
                }
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
        .onChange(of: appLock) { value in locked = value; if value { panel = nil; didLaunchBrowser = false; unlock() } }
        .onChange(of: launchBrowserMode) { value in if !value { browser.startEmbeddedIfNeeded() } }
        .onChange(of: scenePhase) { phase in
            if phase == .background { if privacy && panel != .browserMode { panel = nil }; inactiveSince = Date(); if appLock && lockDelay == 0 { panel = nil; locked = true; didLaunchBrowser = false } }
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
