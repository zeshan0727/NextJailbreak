import SwiftUI
import WebKit

final class BrowserViewModel: ObservableObject {
    @Published var urlString: String = ""
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showInvalidURLAlert: Bool = false
    @Published var history: [String] = []

    private let historyKey = "SimpleBrowserHistory"
    private let maxHistoryCount = 100

    init() {
        loadHistory()
    }

    func loadHistory() {
        if let saved = UserDefaults.standard.array(forKey: historyKey) as? [String] {
            history = saved
        }
    }

    func saveHistory() {
        UserDefaults.standard.set(history, forKey: historyKey)
    }

    func addToHistory(_ url: String) {
        guard !url.isEmpty else { return }
        if let idx = history.firstIndex(of: url) {
            history.remove(at: idx)
        }
        history.insert(url, at: 0)
        if history.count > maxHistoryCount {
            history.removeLast(history.count - maxHistoryCount)
        }
        saveHistory()
    }

    func validateURL(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        // If scheme missing, add https
        if url.scheme == nil {
            return URL(string: "https://" + urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return url
    }
}

struct ContentView: View {
    @StateObject private var viewModel = BrowserViewModel()
    @State private var webView = WKWebView()
    @FocusState private var urlFieldFocused: Bool
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                URLBarView(urlString: $viewModel.urlString,
                           history: viewModel.history,
                           onCommit: loadURL,
                           onClear: clearURL,
                           focused: _urlFieldFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color(UIColor.secondarySystemBackground))

                ProgressView(value: viewModel.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                    .frame(height: viewModel.isLoading ? 2 : 0)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.isLoading)

                ZStack {
                    WebViewWrapper(webView: webView,
                                   urlString: $viewModel.urlString,
                                   isLoading: $viewModel.isLoading,
                                   progress: $viewModel.progress,
                                   canGoBack: $viewModel.canGoBack,
                                   canGoForward: $viewModel.canGoForward,
                                   errorMessage: $viewModel.errorMessage)
                        .accessibilityLabel(Text("Web content area"))

                    if let error = viewModel.errorMessage {
                        ErrorOverlayView(errorMessage: error) {
                            viewModel.errorMessage = nil
                            reload()
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityAddTraits(.isModal)
                    }
                }

                ToolbarView(canGoBack: viewModel.canGoBack,
                            canGoForward: viewModel.canGoForward,
                            onBack: goBack,
                            onForward: goForward,
                            onReload: reload,
                            onShare: { showShareSheet = true })
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))
            }
            .navigationTitle("SimpleBrowser")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Invalid URL", isPresented: $viewModel.showInvalidURLAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid URL.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = viewModel.validateURL(viewModel.urlString) {
                    ActivityView(activityItems: [url])
                }
            }
            .onAppear {
                if let first = viewModel.history.first, let url = viewModel.validateURL(first) {
                    load(url: url)
                }
            }
        }
    }

    private func loadURL() {
        urlFieldFocused = false
        guard let url = viewModel.validateURL(viewModel.urlString) else {
            viewModel.showInvalidURLAlert = true
            return
        }
        load(url: url)
    }

    private func load(url: URL) {
        viewModel.errorMessage = nil
        webView.load(URLRequest(url: url))
        viewModel.addToHistory(url.absoluteString)
    }

    private func clearURL() {
        viewModel.urlString = ""
    }

    private func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    private func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    private func reload() {
        webView.reload()
    }
}

struct URLBarView: View {
    @Binding var urlString: String
    let history: [String]
    let onCommit: () -> Void
    let onClear: () -> Void
    @FocusState var focused: Bool

    @State private var filteredSuggestions: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Enter URL", text: $urlString, onCommit: onCommit)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .disableAutocorrection(true)
                    .focused($focused)
                    .accessibilityLabel(Text("URL input field"))
                    .accessibilityHint(Text("Enter website address"))
                    .onChange(of: urlString) { newValue in
                        updateSuggestions(for: newValue)
                    }

                if !urlString.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel(Text("Clear URL"))
                    .accessibilityHint(Text("Clears the URL input field"))
                }
            }
            .padding(8)
            .background(Color(UIColor.systemBackground))
            .cornerRadius(8)

            if focused && !filteredSuggestions.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredSuggestions, id: \ .self) { suggestion in
                            Button(action: {
                                urlString = suggestion
                                focused = false
                                onCommit()
                            }) {
                                Text(suggestion)
                                    .foregroundColor(.primary)
                                    .font(.body)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .accessibilityLabel(Text("Autocomplete suggestion: \(suggestion)"))
                        }
                    }
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(8)
                    .shadow(radius: 2)
                }
                .frame(maxHeight: 120)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func updateSuggestions(for input: String) {
        let lower = input.lowercased()
        if lower.isEmpty {
            filteredSuggestions = []
        } else {
            filteredSuggestions = history.filter { $0.lowercased().contains(lower) }
                .prefix(5)
                .map { $0 }
        }
    }
}

struct ToolbarView: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onReload: () -> Void
    let onShare: () -> Void

    var body: some View {
        HStack(spacing: 40) {
            Button(action: onBack) {
                Image(systemName: "chevron.backward")
                    .font(.title2)
            }
            .disabled(!canGoBack)
            .accessibilityLabel(Text("Back"))
            .accessibilityHint(Text(canGoBack ? "Go back to previous page" : "No back history"))

            Button(action: onForward) {
                Image(systemName: "chevron.forward")
                    .font(.title2)
            }
            .disabled(!canGoForward)
            .accessibilityLabel(Text("Forward"))
            .accessibilityHint(Text(canGoForward ? "Go forward to next page" : "No forward history"))

            Button(action: onReload) {
                Image(systemName: "arrow.clockwise")
                    .font(.title2)
            }
            .accessibilityLabel(Text("Reload"))
            .accessibilityHint(Text("Reload the current page"))

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
            }
            .accessibilityLabel(Text("Share"))
            .accessibilityHint(Text("Share the current page URL"))
        }
        .foregroundColor(.blue)
        .padding(.horizontal, 20)
    }
}

struct ErrorOverlayView: View {
    let errorMessage: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)

            Text("Failed to load page")
                .font(.title2)
                .bold()

            Text(errorMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: onRetry) {
                Text("Retry")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .accessibilityLabel(Text("Retry loading page"))
        }
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.95))
        .cornerRadius(12)
        .shadow(radius: 10)
        .padding(40)
    }
}

struct WebViewWrapper: UIViewRepresentable {
    let webView: WKWebView
    @Binding var urlString: String
    @Binding var isLoading: Bool
    @Binding var progress: Double
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.addObserver(context.coordinator, forKeyPath: "estimatedProgress", options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: "loading", options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: "canGoBack", options: .new, context: nil)
        webView.addObserver(context.coordinator, forKeyPath: "canGoForward", options: .new, context: nil)
        webView.allowsBackForwardNavigationGestures = true
        webView.accessibilityTraits = .allowsDirectInteraction
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No update needed here
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewWrapper

        init(_ parent: WebViewWrapper) {
            self.parent = parent
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard let webView = object as? WKWebView else { return }

            DispatchQueue.main.async {
                switch keyPath {
                case "estimatedProgress":
                    self.parent.progress = webView.estimatedProgress
                case "loading":
                    self.parent.isLoading = webView.isLoading
                    if !webView.isLoading {
                        self.parent.progress = 1.0
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            self.parent.progress = 0.0
                        }
                    }
                case "canGoBack":
                    self.parent.canGoBack = webView.canGoBack
                case "canGoForward":
                    self.parent.canGoForward = webView.canGoForward
                default:
                    break
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.parent.urlString = webView.url?.absoluteString ?? ""
                self.parent.errorMessage = nil
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.errorMessage = error.localizedDescription
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.errorMessage = error.localizedDescription
            }
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.removeObserver(coordinator, forKeyPath: "estimatedProgress")
        uiView.removeObserver(coordinator, forKeyPath: "loading")
        uiView.removeObserver(coordinator, forKeyPath: "canGoBack")
        uiView.removeObserver(coordinator, forKeyPath: "canGoForward")
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
