import Foundation
import WebKit

/// WKUserContentController retains handlers, so tab is weakly referenced.
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
        let allowedSubtypes = Set([
            "regexp-flags", "regexp-syntax", "unexpected-token",
            "unexpected-identifier", "invalid-character", "unterminated",
            "module-syntax", "private-field", "cross-origin-script",
            "syntax-unspecified"
        ])
        guard let kind = payload["kind"], allowedKinds.contains(kind),
              let category = payload["category"], allowedCategories.contains(category) else { return }
        let host = message.frameInfo.securityOrigin.host.lowercased()
        guard host == "chatgpt.com" || host.hasSuffix(".chatgpt.com") ||
                host == "auth.openai.com" || host == "chat.openai.com" else { return }

        var event = "JavaScript \(kind) \(category)"
        if category == "syntax" {
            let detail = payload["detail"] ?? ""
            if allowedSubtypes.contains(detail) { event += " \(detail)" }
        }
        if let source = payload["sourceId"], source.range(of: #"^[0-9a-f]{8}$|^inline$"#, options: .regularExpression) != nil {
            event += " script-id=\(source)"
        }
        if let line = payload["line"], let column = payload["column"],
           let lineNumber = Int(line), let columnNumber = Int(column),
           (0...9999999).contains(lineNumber), (0...9999999).contains(columnNumber) {
            event += " line=\(lineNumber) col=\(columnNumber)"
        }
        WebDiagnostics.record(host: host, event: event)
    }
}
