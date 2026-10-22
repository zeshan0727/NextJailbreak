import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var tab: BrowserTab

    func makeUIView(context: Context) -> WKWebView { tab.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
