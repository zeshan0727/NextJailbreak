import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var settings: SettingsStore
    @State private var confirmClear = false
    @State private var clearing = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    Picker("Search engine", selection: $settings.value.searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Toggle("HTTPS-first addresses", isOn: $settings.value.httpsFirst)
                    Toggle("Restore regular tabs", isOn: $settings.value.restoreSession)
                        .onChange(of: settings.value.restoreSession) { _ in model.save() }
                } header: { Text("Privacy & Security") } footer: {
                    Text("HTTPS-first upgrades addresses you enter. Turn it off for HTTP-only local devices. Restored tabs stay offline until you tap Resume. Private tabs are never saved.")
                }
                Section("Appearance") {
                    Picker("Theme", selection: $settings.value.appearance) {
                        ForEach(BrowserSettings.Appearance.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                }
                Section {
                    Button(clearing ? "Clearing…" : "Clear Website Data", role: .destructive) { confirmClear = true }.disabled(clearing)
                } header: { Text("Website Storage") } footer: { Text("Removes cookies, caches and local storage for all regular tabs and returns them to the start page. This signs you out of websites.") }
                Section("Diagnostics") {
                    Button("Open Local Browser Test") { model.openLocalTest(); dismiss() }
                    LabeledContent("Version", value: "1.0.0 • Milestone 1")
                    LabeledContent("Minimum iOS", value: "16.0")
                    Text("NovaBrowser uses the WebKit engine installed with iOS. The compatibility engine, advanced pop-up controls, userscripts and VPN are scheduled in later milestones.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            .confirmationDialog("Clear website data and return regular tabs to the start page?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Website Data", role: .destructive) {
                    clearing = true
                    Task { await model.clearWebsiteData(); clearing = false }
                }
            }
        }
    }
}
