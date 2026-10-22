import SwiftUI
import WebKit

struct WebViewContainer: UIViewRepresentable {
    let model: BrowserModel
    let tab: BrowserTab
    func makeUIView(context: Context) -> WKWebView { model.webViews.webView(for: tab) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    // The store owns the view and delegate so changing tabs preserves page state.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) { uiView.removeFromSuperview() }
}
