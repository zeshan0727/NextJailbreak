import SwiftUI

@main
struct AppForgeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .preferredColorScheme(state.preferences.appearance == "dark" ? .dark :
                    state.preferences.appearance == "light" ? .light : nil)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingSettings = false

    var body: some View {
        TabView(selection: $state.selectedTab) {
            PromptView().tabItem { Label("Prompt", systemImage: "text.bubble") }.tag(ForgeTab.requirement)
            CodeView().tabItem { Label("Code", systemImage: "curlybraces") }.tag(ForgeTab.code)
            GitHubView().tabItem { Label("GitHub", systemImage: "arrow.up.doc") }.tag(ForgeTab.github)
            BuildView().tabItem { Label("Build", systemImage: "hammer") }.tag(ForgeTab.status)
            DownloadsView().tabItem { Label("Downloads", systemImage: "square.and.arrow.down") }.tag(ForgeTab.downloads)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .overlay(alignment: .topTrailing) {
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17)).padding(12)
                    .background(.regularMaterial, in: Circle())
            }
            .padding(.trailing, 14).padding(.top, 5)
            .accessibilityLabel("AppForge Settings")
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .alert("AppForge", isPresented: Binding(
            get: { state.notice != nil },
            set: { if !$0 { state.notice = nil } }
        )) {
            Button("OK") { state.notice = nil }
        } message: { Text(state.notice ?? "") }
    }
}

struct ScreenHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
    }
}

struct ForgeButton: View {
    var title: String
    var symbol: String
    var loading = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if loading { ProgressView().tint(.white) }
                else { Image(systemName: symbol) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .disabled(loading)
    }
}
