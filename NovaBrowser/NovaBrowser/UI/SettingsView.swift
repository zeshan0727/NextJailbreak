import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var settings: BrowserSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Search") {
                    Picker("Search Engine", selection: $settings.searchEngine) {
                        ForEach(SearchEngine.allCases) { engine in
                            Text(engine.rawValue).tag(engine)
                        }
                    }
                }
                Section("Milestone 1") {
                    LabeledContent("Web engine", value: "Apple WebKit")
                    LabeledContent("Private tabs", value: "Ephemeral storage")
                    LabeledContent("Downloads", value: "Files → NovaBrowser")
                    LabeledContent("Version", value: "1.0.1")
                }
                Section("Diagnostics") {
                    Button("Copy Launch Diagnostics") {
                        UIPasteboard.general.string = LaunchDiagnostics.read()
                    }
                    ShareLink("Share Launch Diagnostics", item: LaunchDiagnostics.fileURL)
                    Text("The diagnostics file is also available in Files > On My iPhone > NovaBrowser > NovaBrowserDiagnostics.txt. It contains startup events, not visited URLs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Text("Compatibility overrides and pop-up blocking controls will be exposed when the Milestone 2 engine is integrated. The site settings model and policy dispatch are already in the codebase.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
