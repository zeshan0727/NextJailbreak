import Foundation
import SwiftUI
import WebKit

@MainActor
final class FacebookMarketplaceClient: ObservableObject {
    static let shared = FacebookMarketplaceClient()

    @Published private(set) var isConnected: Bool = UserDefaults.standard.bool(forKey: "tipa.facebook.connected")
    @Published private(set) var lastSearchStatus: String = ""

    private init() {
        Task { await refreshConnection() }
    }

    func refreshConnection() async {
        let cookies = await allCookies()
        let connected = cookies.contains {
            $0.name == "c_user" && $0.domain.lowercased().contains("facebook.com")
        }
        isConnected = connected
        UserDefaults.standard.set(connected, forKey: "tipa.facebook.connected")
    }

    func disconnect() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await allCookies()
        for cookie in cookies where cookie.domain.lowercased().contains("facebook.com") {
            await withCheckedContinuation { continuation in
                store.delete(cookie) {
                    continuation.resume()
                }
            }
        }
        isConnected = false
        UserDefaults.standard.set(false, forKey: "tipa.facebook.connected")
    }

    func search(query: String) async -> [MarketplaceListing] {
        await refreshConnection()
        guard isConnected else {
            lastSearchStatus = "Facebook not connected"
            return []
        }

        let renderer = FacebookMarketplaceRenderer()
        let payload = await renderer.search(query: query)

        if payload.loggedOut {
            isConnected = false
            UserDefaults.standard.set(false, forKey: "tipa.facebook.connected")
            lastSearchStatus = "Facebook session expired"
            return []
        }

        let source = MarketplaceSource.all.first(where: { $0.id == "facebook" })!
        var seen = Set<String>()
        var output: [MarketplaceListing] = []

        for (index, row) in payload.rows.enumerated() {
            guard let itemURL = Self.canonicalItemURL(row.href) else { continue }
            let key = itemURL.absoluteString.lowercased()
            guard seen.insert(key).inserted else { continue }

            let cleanText = Self.clean(row.text)
            guard Self.matches(cleanText, query: query) else { continue }
            guard !Self.accessoryMismatch(cleanText, query: query) else { continue }

            output.append(
                MarketplaceListing(
                    title: Self.title(from: cleanText, query: query),
                    url: itemURL,
                    source: source,
                    priceQAR: Self.price(from: cleanText),
                    snippet: String(cleanText.prefix(420)),
                    order: 10_000 + index
                )
            )

            if output.count >= 30 { break }
        }

        lastSearchStatus = output.isEmpty
            ? "Facebook returned no matching direct posts"
            : "Facebook: \(output.count) direct posts"

        return output
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
    }

    private static func canonicalItemURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw) else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host == "facebook.com" || host.hasSuffix(".facebook.com") else { return nil }

        let path = url.path
        guard let expression = try? NSRegularExpression(
            pattern: #"/marketplace/item/([0-9]+)"#,
            options: [.caseInsensitive]
        ) else { return nil }

        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard
            let match = expression.firstMatch(in: path, range: range),
            match.numberOfRanges > 1,
            let idRange = Range(match.range(at: 1), in: path)
        else { return nil }

        let id = String(path[idRange])
        return URL(string: "https://www.facebook.com/marketplace/item/\(id)/")
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"[\\t ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedTokens(_ value: String) -> [String] {
        value.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func matches(_ text: String, query: String) -> Bool {
        let haystack = normalizedTokens(text)
        let queryTokens = normalizedTokens(query).filter {
            !["find", "show", "me", "cheapest", "cheap", "lowest", "highest", "qatar", "doha"].contains($0)
        }
        guard !queryTokens.isEmpty else { return true }

        let hay = Set(haystack)
        let numeric = queryTokens.filter { Int($0) != nil }
        if numeric.contains(where: { !hay.contains($0) }) { return false }

        let words = queryTokens.filter { Int($0) == nil }
        let hits = words.filter { hay.contains($0) }.count

        if words.count <= 2 { return hits == words.count }
        return hits >= words.count - 1
    }

    private static func accessoryMismatch(_ text: String, query: String) -> Bool {
        let q = query.lowercased()
        let phoneQuery = [
            "iphone", "samsung", "galaxy", "fold", "flip", "pixel", "phone",
            "huawei", "honor", "xiaomi", "oppo", "vivo", "oneplus"
        ].contains(where: { q.contains($0) })

        guard phoneQuery else { return false }

        let accessoryWords = [
            "case", "cover", "protector", "tempered", "charger", "cable",
            "adapter", "screen replacement", "lcd", "spare parts"
        ]

        let userAskedAccessory = accessoryWords.contains(where: { q.contains($0) })
        guard !userAskedAccessory else { return false }

        let t = text.lowercased()
        return accessoryWords.contains(where: { t.contains($0) })
    }

    private static func price(from text: String) -> Int? {
        let patterns = [
            #"(?i)(?:QAR|QR)\s*[:\-]?\s*([0-9][0-9,. ]*)"#,
            #"(?i)([0-9][0-9,. ]*)\s*(?:QAR|QR)"#,
            #"([0-9][0-9,. ]*)\s*(?:ر\.?\s*ق\.?)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard
                let match = regex.firstMatch(in: text, range: range),
                match.numberOfRanges > 1,
                let valueRange = Range(match.range(at: 1), in: text)
            else { continue }

            let digits = text[valueRange].filter(\.isNumber)
            if let value = Int(digits), (20...20_000_000).contains(value) {
                return value
            }
        }
        return nil
    }

    private static func title(from text: String, query: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let queryTokens = normalizedTokens(query)
        let candidates = lines.filter { line in
            let lower = line.lowercased()
            guard line.count >= 3 && line.count <= 180 else { return false }
            guard !lower.contains("marketplace") else { return false }
            guard price(from: line) == nil else { return false }

            let tokens = Set(normalizedTokens(line))
            let hits = queryTokens.filter { tokens.contains($0) }.count
            return queryTokens.count <= 2 ? hits == queryTokens.count : hits >= max(1, queryTokens.count - 1)
        }

        if let candidate = candidates.first {
            return candidate
        }

        if let fallback = lines.first(where: { price(from: $0) == nil && $0.count <= 180 }) {
            return fallback
        }

        return query
    }
}

private struct FacebookSearchRow: Codable {
    let href: String
    let text: String
}

private struct FacebookSearchPayload {
    let loggedOut: Bool
    let rows: [FacebookSearchRow]
}

@MainActor
private final class FacebookMarketplaceRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<FacebookSearchPayload, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false
    private var query = ""

    func search(query: String) async -> FacebookSearchPayload {
        self.query = query
        completed = false

        var components = URLComponents(string: "https://www.facebook.com/marketplace/search/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "exact", value: "false")
        ]

        guard let url = components.url else {
            return .init(loggedOut: false, rows: [])
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.defaultWebpagePreferences.allowsContentJavaScript = true

            let view = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                configuration: config
            )
            view.navigationDelegate = self
            view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
            webView = view

            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 25
            )
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            view.load(request)

            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 28_000_000_000)
                self?.finish(.init(loggedOut: false, rows: []))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView, !self.completed else { return }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight * 0.45);")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, document.body.scrollHeight * 0.85);")
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            let script = """
            (() => {
              const body = (document.body && document.body.innerText || '').toLowerCase();
              const loggedOut =
                !!document.querySelector('input[name="email"]') ||
                !!document.querySelector('input[name="pass"]') ||
                body.includes('log in to facebook') ||
                body.includes('you must log in');

              const rows = [];
              const anchors = Array.from(document.querySelectorAll('a[href*="/marketplace/item/"]'));

              for (const a of anchors) {
                const href = (a.href || '').trim();
                if (!href) continue;

                let node = a;
                let best = ((a.innerText || a.textContent || '') + '').trim();

                for (let i = 0; i < 8 && node; i++, node = node.parentElement) {
                  const text = ((node.innerText || node.textContent || '') + '')
                    .replace(/[ \t]+/g, ' ')
                    .replace(/\n{3,}/g, '\n\n')
                    .trim();

                  if (text.length >= best.length && text.length <= 1800) {
                    best = text;
                  }

                  if (best.length >= 80) break;
                }

                rows.push({href, text: best.slice(0, 1800)});
              }

              return JSON.stringify({loggedOut, rows});
            })();
            """

            do {
                let value = try await webView.evaluateJavaScript(script)
                guard
                    let json = value as? String,
                    let data = json.data(using: .utf8),
                    let decoded = try? JSONDecoder().decode(FacebookDecodedPayload.self, from: data)
                else {
                    self.finish(.init(loggedOut: false, rows: []))
                    return
                }

                self.finish(.init(loggedOut: decoded.loggedOut, rows: decoded.rows))
            } catch {
                self.finish(.init(loggedOut: false, rows: []))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.init(loggedOut: false, rows: []))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.init(loggedOut: false, rows: []))
    }

    private func finish(_ payload: FacebookSearchPayload) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: payload)
    }
}

private struct FacebookDecodedPayload: Codable {
    let loggedOut: Bool
    let rows: [FacebookSearchRow]
}

struct FacebookLoginSheet: View {
    @ObservedObject var client: FacebookMarketplaceClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FacebookLoginWebView(client: client)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Facebook Marketplace")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            Task {
                                await client.refreshConnection()
                                dismiss()
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        if client.isConnected {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption.bold())
                        }
                    }
                }
        }
    }
}

private struct FacebookLoginWebView: UIViewRepresentable {
    @ObservedObject var client: FacebookMarketplaceClient

    func makeCoordinator() -> Coordinator {
        Coordinator(client: client)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"

        if let url = URL(string: "https://www.facebook.com/marketplace/") {
            view.load(URLRequest(url: url))
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let client: FacebookMarketplaceClient

        init(client: FacebookMarketplaceClient) {
            self.client = client
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                await client.refreshConnection()
            }
        }
    }
}
