import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var settings: BrowserSettings
    @ObservedObject var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(BrowserAppearance.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("System follows your iPhone appearance. Light and Dark override the browser interface and preferred web color scheme.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Search") {
                    Picker("Search Engine", selection: $settings.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                }
                Section("Site Compatibility") {
                    Picker("Global User Agent", selection: Binding(
                        get: { settings.globalSiteSettings.userAgentPreset },
                        set: { settings.globalSiteSettings.userAgentPreset = $0 }
                    )) {
                        ForEach(UserAgentPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Toggle("Request Desktop Sites", isOn: Binding(
                        get: { settings.globalSiteSettings.desktopMode },
                        set: { settings.globalSiteSettings.desktopMode = $0 }
                    ))
                    Toggle("Enable JavaScript", isOn: Binding(
                        get: { settings.globalSiteSettings.javaScriptEnabled },
                        set: { settings.globalSiteSettings.javaScriptEnabled = $0 }
                    ))
                    Toggle("Legacy WebKit Compatibility Shims", isOn: $settings.legacyPolyfillsEnabled)
                    Button("Apply Settings to Open Tabs") { model.reloadTabsForCompatibility() }
                    Text("User-agent presets only change the browser identity sent to sites. They cannot upgrade iOS 16 WebKit. Compatibility shims add missing JavaScript APIs where possible; reload pages after changing settings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Milestone 2 — Compatibility Preview") {
                    LabeledContent("Engine", value: "iOS WebKit")
                    LabeledContent("Downloads", value: "Files → NovaBrowser")
                    LabeledContent("Version", value: "1.0.6")
                }
                Section("Web Compatibility Check") {
                    Button("Run Compatibility Check on Current Tab") { model.runCompatibilityCheck() }
                    Text(model.compatibilityReport)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy Web Diagnostics") {
                        UIPasteboard.general.string = WebDiagnostics.read() + "\n\n" + model.compatibilityReport
                    }
                    ShareLink("Share Web Diagnostics", item: WebDiagnostics.fileURL)
                    Text("Captures JavaScript syntax-error categories, script fingerprints, line/column numbers and main-document HTTP status. It does not save script URLs, error text, page queries, cookies or chat messages. Review before sharing.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Diagnostics") {
                    Button("Copy Launch Diagnostics") { UIPasteboard.general.string = LaunchDiagnostics.read() }
                    ShareLink("Share Launch Diagnostics", item: LaunchDiagnostics.fileURL)
                    Text("Startup milestones are saved to Files > On My iPhone > NovaBrowser > NovaBrowserDiagnostics.txt.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
