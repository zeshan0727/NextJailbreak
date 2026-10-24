import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: VPNViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var adding = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            settingsForm
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") { dismiss() }.accessibilityLabel("Close settings")
                    }
                }
                .sheet(isPresented: $adding) { AddServerView().environmentObject(model) }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let count = try model.importServers(from: result.get())
                        importMessage = "Imported \(count) new \(count == 1 ? "server" : "servers")."
                    } catch {
                        importMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
        }
    }

    private var settingsForm: some View {
        Form {
            Section("App Settings") {
                Toggle("Auto-connect on launch", isOn: $model.autoConnectOnLaunch)
                Text("Reconnects to the last successfully connected server when a matching, enabled system VPN configuration is available.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("Servers") {
                Button("Add server") { adding = true }
                Button("Import server list") { importing = true }
                if let message = importMessage { Text(message).font(.footnote) }
                Text("Import a JSON array of objects with name, country and ipAddress text fields. An optional UUID id is supported. Existing servers are preserved; duplicate addresses are skipped.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("VPN Configuration") {
                Button("Reload VPN configuration") { model.reloadConfiguration() }
                    .disabled(model.isLoading)
                Text("FreeLocalVPN reads only the Personal VPN configuration accessible to this app. Profiles belonging to other apps may not be accessible. This build does not include a VPN provider, credentials or a working public server feed. A server address alone cannot establish a secure tunnel.")
                    .font(.footnote).foregroundColor(.secondary)
                Text("VPN operation requires Apple's Personal VPN entitlement and a valid, authenticated provider configuration. This app never invents credentials or reports a connection before iOS confirms it.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            if model.errorMessage != nil { VPNErrorSection() }
            Section("Privacy") {
                Text("Server addresses and the auto-connect preference are stored locally. No credentials are stored by this app. Refreshing reachability contacts only the selected server addresses on TCP port 443.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Section("App Info") { Text("FreeLocalVPN v1.0") }
        }
    }
}

private struct AddServerView: View {
    @EnvironmentObject private var model: VPNViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var country = ""
    @State private var address = ""
    private var trimmedAddress: String { address.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !country.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        VPNViewModel.validAddress(trimmedAddress)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server details") {
                    TextField("Name", text: $name)
                    TextField("Country", text: $country)
                    TextField("Hostname or IP address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section {
                    Text("Use details from a trusted VPN provider. Do not include a URL scheme or port. Saving an address does not install authentication or a VPN configuration.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Add Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.addServer(name: name, country: country, address: trimmedAddress)
                        dismiss()
                    }.disabled(!valid)
                }
            }
        }
    }
}
