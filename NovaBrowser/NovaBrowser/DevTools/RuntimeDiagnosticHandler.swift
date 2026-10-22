import Foundation
import WebKit

/// WKWebView retains script-message handlers, so the bridge weakly references
/// the owning tab to avoid a WKWebView -> handler -> tab -> WKWebView cycle.
final class RuntimeDiagnosticHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?

    init(tab: BrowserTab) {
        self.tab = tab
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard tab != nil, let payload = message.body as? [String: String] else { return }
        let allowedKinds = Set(["script-error", "unhandled-rejection"])
        let allowedCategories = Set([
            "missing-promise-withresolvers", "service-worker", "chunk-load",
            "network", "syntax", "missing-function", "null-or-undefined", "other"
        ])
        guard let kind = payload["kind"], allowedKinds.contains(kind),
              let category = payload["category"], allowedCategories.contains(category) else { return }
        let host = message.frameInfo.securityOrigin.host.lowercased()
        guard host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") ||
                host == "auth.openai.com" || host == "chat.openai.com" else { return }
        WebDiagnostics.record(host: host, event: "JavaScript \(kind) \(category)")
    }
}
