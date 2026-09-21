import Foundation
import WebKit

struct BrowserSearchCandidate: Codable, Sendable {
    let href: String
    let title: String
    let context: String
}

@MainActor
enum BrowserSearchBridge {
    static func fetch(url: URL) async -> [BrowserSearchCandidate] {
        let renderer = BrowserSearchRenderer()
        return await renderer.fetch(url: url)
    }
}

@MainActor
private final class BrowserSearchRenderer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[BrowserSearchCandidate], Never>?
    private var timeoutTask: Task<Void, Never>?
    private var completed = false

    func fetch(url: URL) async -> [BrowserSearchCandidate] {
        completed = false

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            config.defaultWebpagePreferences.allowsContentJavaScript = true

            let view = WKWebView(frame: .zero, configuration: config)
            view.navigationDelegate = self
            view.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
            self.webView = view

            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: 18
            )
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
            view.load(request)

            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                self?.finish([])
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView, !self.completed else { return }

            // Brave can populate part of the result DOM shortly after didFinish.
            try? await Task.sleep(nanoseconds: 1_200_000_000)

            let script = """
            (() => {
              const rows = [];
              const anchors = Array.from(document.querySelectorAll('a[href]'));
              for (const a of anchors) {
                const href = (a.href || '').trim();
                if (!href) continue;

                const title = ((a.innerText || a.textContent || '') + '')
                  .replace(/\\s+/g, ' ')
                  .trim();

                let node = a;
                let context = title;
                for (let i = 0; i < 5 && node; i++, node = node.parentElement) {
                  const text = ((node.innerText || node.textContent || '') + '')
                    .replace(/\\s+/g, ' ')
                    .trim();
                  if (text.length > context.length) context = text;
                  if (context.length >= 500) break;
                }

                rows.push({
                  href,
                  title,
                  context: context.slice(0, 1400)
                });
              }
              return JSON.stringify(rows);
            })();
            """

            do {
                let value = try await webView.evaluateJavaScript(script)
                guard let json = value as? String,
                      let data = json.data(using: .utf8) else {
                    self.finish([])
                    return
                }

                let decoded = (try? JSONDecoder().decode([BrowserSearchCandidate].self, from: data)) ?? []
                self.finish(decoded)
            } catch {
                self.finish([])
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish([])
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish([])
    }

    private func finish(_ candidates: [BrowserSearchCandidate]) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil

        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: candidates)
    }
}
