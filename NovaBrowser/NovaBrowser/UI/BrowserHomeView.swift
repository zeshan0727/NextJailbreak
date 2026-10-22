import SwiftUI
import WebKit

struct BrowserHomeView: View {
    @ObservedObject var model: BrowserViewModel
    @ObservedObject var settings: BrowserSettings
    @State private var showingTabs = false
    @State private var showingLibrary = false
    @State private var showingSettings = false
    @State private var showingFind = false
    @State private var confirmingChatGPTReset = false
    @State private var findText = ""
    @State private var zoom: Double = 1
    @State private var sharePayload: SharePayload?

    var body: some View {
        VStack(spacing: 0) {
            if let tab = model.activeTab {
                BrowserChromeView(tab: tab, model: model, showTabs: { showingTabs = true },
                                  showLibrary: { showingLibrary = true }, showSettings: { showingSettings = true },
                                  showFind: { showingFind = true },
                                  repairChatGPT: { confirmingChatGPTReset = true }, share: { shareCurrent(tab) },
                                  zoom: { zoomTab(tab) })
                ZStack {
                    Color(uiColor: .systemBackground)
                    TabContentView(tab: tab)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: settings.appearance) { newValue in model.applyAppearance(newValue) }
        .sheet(isPresented: $showingTabs) { TabSwitcherView(model: model) }
        .sheet(isPresented: $showingLibrary) { LibraryView(model: model) }
        .sheet(isPresented: $showingSettings) { SettingsView(settings: model.settings, model: model) }
        .confirmationDialog("Reset ChatGPT website data?",
                            isPresented: $confirmingChatGPTReset,
                            titleVisibility: .visible) {
            Button("Clear ChatGPT login data and reload", role: .destructive) {
                model.repairChatGPTSession()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will sign you out of ChatGPT in NovaBrowser and clear related OpenAI cookies and cached website data. Other browser sites are not cleared.")
        }
        .sheet(isPresented: $showingFind) {
            NavigationStack {
                Form {
                    TextField("Find on page", text: $findText)
                        .submitLabel(.search)
                        .onSubmit { findNext() }
                    Button("Find Next") { findNext() }
                    Button("Done") { showingFind = false }
                }
                .navigationTitle("Find in Page")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $sharePayload) { payload in ActivitySheet(items: [payload.url]) }
        .alert("NovaBrowser", isPresented: Binding(get: { model.errorMessage != nil }, set: {
            if !$0 { model.errorMessage = nil }
        })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func shareCurrent(_ tab: BrowserTab) {
        if let url = URL(string: tab.address) { sharePayload = SharePayload(url: url) }
    }

    private func findNext() {
        guard let tab = model.activeTab, !findText.isEmpty else { return }
        let config = WKFindConfiguration()
        tab.webView.find(findText, configuration: config) { result in
            if !result.matchFound { model.errorMessage = "No matches found." }
        }
    }

    private func zoomTab(_ tab: BrowserTab) {
        zoom = zoom >= 1.5 ? 0.8 : zoom + 0.2
        tab.zoom(CGFloat(zoom))
    }
}

struct SharePayload: Identifiable {
    var id = UUID()
    let url: URL
}

struct TabContentView: View {
    @ObservedObject var tab: BrowserTab
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            if tab.isSuspended {
                VStack(spacing: 14) {
                    Image(systemName: "arrow.clockwise.circle").font(.largeTitle)
                    Text(tab.title).font(.headline).lineLimit(2)
                    Text("This tab was restored without connecting to the network.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Load Restored Page") { tab.resume() }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else if tab.address.isEmpty {
                startPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BrowserWebView(tab: tab).id(tab.id)
            }
        }
    }

    var startPage: some View {
        VStack(spacing: 16) {
            Image(systemName: "safari.fill")
                .font(.system(size: 68))
                .foregroundStyle(.cyan)
            Text("NovaBrowser")
                .font(.largeTitle.weight(.semibold))
            Text("Your web, your way")
                .foregroundStyle(.secondary)
            Text("Type an address or search above to start browsing.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(26)
    }

}


struct ActivitySheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
