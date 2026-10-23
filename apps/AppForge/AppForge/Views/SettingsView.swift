import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var aiSecret = ""
    @State private var gitSecret = ""

    private func save() { state.saveSecrets(ai: aiSecret, github: gitSecret) }

    var body: some View {
        NavigationStack {
            Form {
                Section("AI provider — OpenAI-compatible") {
                    TextField("HTTPS base URL", text: $state.preferences.aiBaseURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Exact model ID", text: $state.preferences.aiModel)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API key", text: $aiSecret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Test AI connection") {
                        save()
                        Task { await state.testAI() }
                    }.disabled(state.busyTest)
                    Text("Use a model/provider that supports OpenAI-compatible /chat/completions. Free usage and quotas are provider-specific.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("GitHub access") {
                    SecureField("Personal access token", text: $gitSecret)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("GitHub username", text: $state.preferences.githubUsername)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Default repository", text: $state.preferences.defaultRepo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Test GitHub token") {
                        save()
                        Task { await state.testGitHub() }
                    }.disabled(state.busyTest)
                    DisclosureGroup("Fine-grained token guide") {
                        Text("GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token. Choose your account and grant access to the intended repositories. Repository permissions: Contents (Read and write), Actions (Read and write), and Workflows (Read and write) to update .github/workflows. New repository creation may require a classic token or a supported authentication method; fine-grained tokens can be restricted to existing repositories. Never place the token in your generated source or public repo.")
                            .font(.caption)
                    }
                }
                Section("Crash report repair") {
                    NavigationLink(destination: DiagnosticsView()) {
                        Label("Import .ips Report", systemImage: "stethoscope")
                    }
                    Text("You can also access Crash Diagnostics from Code or Build. The report is parsed locally; only a sanitized summary is sent to AI when needed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Automatic build repair") {
                    Toggle("Fix and rebuild automatically", isOn: $state.autoRepairEnabled)
                    Text("On compiler failure, AppForge reads logs, asks your configured AI to correct the Swift source, commits the fix and rebuilds. Up to two attempts. Keep the app open; OpenAI API usage can incur charges.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance & build") {
                    Picker("Theme", selection: $state.preferences.appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented)
                    TextField("iOS deployment target", text: $state.preferences.minimumIOS)
                        .keyboardType(.numbersAndPunctuation)
                    Text("Generated projects are tested for iOS 16+ APIs by prompting the model, not by static analysis.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Local data") {
                    Button("Clear prompt history and generated code", role: .destructive) { state.clearHistoryAndCache() }
                }
                Section("About") {
                    LabeledContent("App", value: "AppForge 1.0.7")
                    Text("No external backend, tracking, or analytics. Secrets use iOS Keychain. Requests go directly to your selected AI provider and GitHub.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Done") { save(); dismiss() }
                }
            }
            .onAppear {
                aiSecret = Keychain.read("ai")
                gitSecret = Keychain.read("github")
            }
        }
    }
}
