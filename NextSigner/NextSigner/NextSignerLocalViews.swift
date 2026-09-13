import SwiftUI
import UIKit

struct NextSignerLocalSignView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    sourceCard
                    identityCard
                    credentialsCard
                    optionsCard
                    signCard
                }
                .padding()
            }
            .navigationTitle("Next Signer")
            .sheet(isPresented: $showPicker) {
                ManualDocumentPicker(
                    documentTypes: ["public.item", "public.data", "public.archive", "com.apple.itunes.ipa"],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        showPicker = false
                        guard let url = urls.first else { return }
                        let ext = url.pathExtension.lowercased()
                        guard ext == "ipa" || ext == "tipa" else {
                            store.errorMessage = "Choose an .ipa or .tipa file."
                            return
                        }
                        store.importIPA(from: url)
                        store.request.signingEnabled = true
                        local.signingSuccess = nil
                        local.signingError = nil
                    },
                    onCancel: { showPicker = false }
                )
                .ignoresSafeArea()
            }
            .alert("Next Signer", isPresented: Binding(
                get: { local.signingError != nil || store.errorMessage != nil },
                set: {
                    if !$0 {
                        local.signingError = nil
                        store.errorMessage = nil
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    local.signingError = nil
                    store.errorMessage = nil
                }
            } message: {
                Text(local.signingError ?? store.errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Local signing", systemImage: "iphone.and.arrow.forward")
                .font(.title2.bold())
            Text("The IPA is signed entirely on this iPhone. GitHub is not contacted until you manually publish a signed app from the Signed Apps tab.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if let url = store.request.ipaURL {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .lineLimit(2)
                            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.clearSelectedIPA()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 34))
                        Text("No IPA selected").font(.headline)
                        Text("Choose an IPA or TIPA from Files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                Button { showPicker = true } label: {
                    Label(store.request.ipaURL == nil ? "Choose IPA / TIPA" : "Choose Another IPA / TIPA", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        } label: {
            Label("Source IPA", systemImage: "app.dashed")
        }
    }

    private var identityCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                TextField("App name", text: $store.request.appName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                TextField("Bundle ID", text: $store.request.bundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Image(systemName: store.request.isValidBundleID ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.request.isValidBundleID ? .green : .orange)
                    Text(store.request.isValidBundleID ? "Bundle identifier format is valid." : "Enter a valid bundle identifier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } label: {
            Label("App identity", systemImage: "number")
        }
    }

    private var credentialsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                credentialRow("P12 certificate", ready: local.hasP12)
                credentialRow("Provisioning profile", ready: local.hasProvisioningProfile)
                credentialRow("P12 password", ready: local.p12PasswordIsStored)
                if !local.credentialsReady {
                    Text("Open the Profiles tab and import the three local signing items before signing.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Local signing profile ready", systemImage: "checkmark.shield.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            }
        } label: {
            Label("Local signing profile", systemImage: "checkmark.seal")
        }
    }

    private func credentialRow(_ title: String, ready: Bool) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ready ? .green : .secondary)
            Text(title)
            Spacer()
            Text(ready ? "Ready" : "Missing")
                .font(.caption)
                .foregroundStyle(ready ? .green : .secondary)
        }
    }

    private var optionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Install as duplicate app", isOn: Binding(
                    get: { store.request.duplicateSigning },
                    set: { store.setDuplicateSigning($0) }
                ))
                Text("Changes the bundle identifier so the signed copy can install beside the original app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Custom icon and tweak injection are not sent to GitHub in local-sign mode. The IPA itself is signed on-device and preserved unchanged apart from the requested app name/bundle ID and signature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Signing options", systemImage: "slider.horizontal.3")
        }
    }

    private var signCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if local.isSigning {
                    ProgressView(value: local.signingProgress)
                    Text(local.signingMessage.isEmpty ? "Signing locally…" : local.signingMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    store.request.signingEnabled = true
                    local.sign(request: store.request)
                } label: {
                    Label(local.isSigning ? "Signing on iPhone…" : "Sign IPA Locally", systemImage: "signature")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(
                    store.request.ipaURL == nil ||
                    store.request.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !store.request.isValidBundleID ||
                    !local.credentialsReady ||
                    local.isSigning
                )

                Text("No GitHub upload happens when this button is pressed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let success = local.signingSuccess {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            Label("Sign", systemImage: "checkmark.seal.fill")
        }
    }
}

struct NextSignerSignedAppsView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @State private var shareURL: URL?
    @State private var deleteCandidate: LocalSignedApp?

    var body: some View {
        NavigationStack {
            Group {
                if local.signedApps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("No signed apps yet")
                            .font(.headline)
                        Text("Sign an IPA locally from the Sign tab. It will appear here automatically.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if let message = local.publishMessage {
                            Section {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        if let error = local.publishError {
                            Section {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }

                        ForEach(local.signedApps) { app in
                            Section {
                                signedAppRow(app)
                            }
                        }
                    }
                    .refreshable { local.refreshSignedApps() }
                }
            }
            .navigationTitle("Signed Apps")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { local.refreshSignedApps() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { local.refreshSignedApps() }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let shareURL { NextSignerShareSheet(items: [shareURL]) }
            }
            .confirmationDialog(
                "Delete signed IPA from this iPhone?",
                isPresented: Binding(
                    get: { deleteCandidate != nil },
                    set: { if !$0 { deleteCandidate = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let app = deleteCandidate { local.deleteSignedApp(app) }
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            }
        }
    }

    private func signedAppRow(_ app: LocalSignedApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "app.badge.checkmark.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.appName).font(.headline)
                    Text(app.bundleID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if !app.version.isEmpty { Text("v\(app.version)") }
                        if !app.build.isEmpty { Text("build \(app.build)") }
                        if app.sizeBytes > 0 { Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file)) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(app.filename)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if local.installingID == app.id {
                ProgressView()
                Text(local.installMessage ?? "Preparing Apple OTA installation…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if local.publishingID == app.id {
                ProgressView(value: local.publishProgress)
                Text("Publishing signed IPA to site…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    local.install(app, using: store)
                } label: {
                    Label("Install", systemImage: "arrow.down.app.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(local.installingID != nil || local.publishingID != nil)

                Button {
                    local.publish(app, using: store)
                } label: {
                    Label("Publish", systemImage: "paperplane.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(local.publishingID != nil || local.installingID != nil)
            }

            HStack(spacing: 8) {
                Button {
                    shareURL = app.ipaURL
                } label: {
                    Label("Share IPA", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    deleteCandidate = app
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(local.publishingID == app.id || local.installingID == app.id)
            }

            Text("Install uses Apple OTA Ad Hoc installation. The already-signed IPA is staged temporarily over HTTPS and is not added to your site. Publish remains a separate manual action.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NextSignerLocalProfileView: View {
    @ObservedObject var local: LocalSigningController
    @State private var pickerTarget: LocalProfilePickerTarget?

    private enum LocalProfilePickerTarget: Int, Identifiable {
        case p12
        case provisioning
        var id: Int { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("On-device signing profile", systemImage: "iphone.badge.checkmark")
                        .font(.headline)
                    Text("These signing credentials stay on this iPhone and are used by the local Zsign engine. Signing an IPA does not contact GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("P12 certificate") {
                    statusRow("Certificate", ready: local.hasP12)
                    Button {
                        pickerTarget = .p12
                    } label: {
                        Label(local.hasP12 ? "Replace P12" : "Import P12", systemImage: "key.fill")
                    }
                    if local.hasP12 {
                        Button("Remove P12", role: .destructive) { local.removeCredential(.p12) }
                    }
                }

                Section("P12 password") {
                    SecureField("P12 password", text: $local.p12Password)
                        .textContentType(.password)
                    Button("Save Password to Keychain") { local.saveP12Password() }
                    statusRow("Password", ready: local.p12PasswordIsStored)
                }

                Section("Provisioning profile") {
                    statusRow("Provisioning profile", ready: local.hasProvisioningProfile)
                    Button {
                        pickerTarget = .provisioning
                    } label: {
                        Label(local.hasProvisioningProfile ? "Replace .mobileprovision" : "Import .mobileprovision", systemImage: "doc.badge.gearshape")
                    }
                    if local.hasProvisioningProfile {
                        Button("Remove Provisioning Profile", role: .destructive) { local.removeCredential(.provisioning) }
                    }
                }

                Section("Status") {
                    if local.credentialsReady {
                        Label("Ready for local signing", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Complete the missing items above", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if let message = local.signingSuccess {
                        Text(message).font(.caption).foregroundStyle(.green)
                    }
                    if let error = local.signingError {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Profiles")
            .onAppear { local.refreshCredentials() }
            .sheet(item: $pickerTarget) { target in
                ProfileDocumentPicker(
                    onPick: { urls in
                        pickerTarget = nil
                        guard let url = urls.first else { return }
                        let ext = url.pathExtension.lowercased()
                        switch target {
                        case .p12:
                            guard ext == "p12" else {
                                local.signingError = "Choose a .p12 certificate file."
                                return
                            }
                            local.importCredential(from: url, kind: .p12)
                        case .provisioning:
                            guard ext == "mobileprovision" else {
                                local.signingError = "Choose a .mobileprovision file."
                                return
                            }
                            local.importCredential(from: url, kind: .provisioning)
                        }
                    },
                    onCancel: { pickerTarget = nil }
                )
                .ignoresSafeArea()
            }
        }
    }

    private func statusRow(_ title: String, ready: Bool) -> some View {
        HStack {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? .green : .secondary)
            Text(title)
            Spacer()
            Text(ready ? "Saved locally" : "Not configured")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct NextSignerLocalSettingsView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @State private var revealToken = false
    @State private var shareURL: URL?
    @State private var restorePicker = false
    @State private var backupMessage: String?
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("GitHub is used only after you manually tap Publish on a signed app. Local signing, local IPA storage and TrollStore installation work without GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Architecture")
                }

                Section("GitHub publishing") {
                    TextField("Owner", text: $store.configuration.owner)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Repository", text: $store.configuration.repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Branch", text: $store.configuration.branch)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Workflow file", text: $store.configuration.workflowFile)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Fine-grained PAT") {
                    if revealToken {
                        TextField("github_pat_…", text: $store.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        SecureField("github_pat_…", text: $store.token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle("Show token", isOn: $revealToken)
                    Button("Save Token to Keychain") { store.saveToken() }
                    Label(store.tokenIsStored ? "PAT stored on this device" : "PAT not configured",
                          systemImage: store.tokenIsStored ? "lock.fill" : "lock.open")
                        .font(.caption)
                        .foregroundStyle(store.tokenIsStored ? .green : .secondary)
                }

                Section("Backup & Restore") {
                    Button {
                        do {
                            store.persistConfiguration()
                            shareURL = try NextSignerConfigBackupManager.createBackup(store: store)
                            backupMessage = "Backup created. Save it somewhere secure."
                            backupError = nil
                        } catch {
                            backupError = error.localizedDescription
                        }
                    } label: {
                        Label("Backup Current Config", systemImage: "externaldrive.badge.plus")
                    }

                    Button {
                        restorePicker = true
                    } label: {
                        Label("Restore Config Backup", systemImage: "arrow.clockwise.icloud")
                    }

                    Text("The config backup includes the saved GitHub PAT and repository/settings. It does not contain the P12 certificate or provisioning profile.")
                        .font(.caption)
                        .foregroundStyle(.orange)

                    if let backupMessage {
                        Label(backupMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    if let backupError {
                        Label(backupError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("Publishing PAT permissions") {
                    Label("Contents: Read and write", systemImage: "doc.badge.gearshape")
                    Text("The PAT is only needed to upload the already-signed IPA to the private inbox and request the site/R2 publishing workflow. Secrets permission is no longer needed for local signing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Local signing security") {
                    Label(local.hasP12 ? "P12 stored locally" : "P12 not stored", systemImage: "key.fill")
                    Label(local.hasProvisioningProfile ? "Provisioning profile stored locally" : "Provisioning profile not stored", systemImage: "doc.badge.gearshape")
                    Label(local.p12PasswordIsStored ? "P12 password in Keychain" : "P12 password not stored", systemImage: "lock.fill")
                    Text("Signing credentials are kept in the app's protected local storage/Keychain and are not uploaded when you sign an IPA.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onDisappear { store.persistConfiguration() }
            .sheet(isPresented: $restorePicker) {
                ManualDocumentPicker(
                    documentTypes: ["public.json", "public.text", "public.data", "public.item"],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        restorePicker = false
                        guard let url = urls.first else { return }
                        do {
                            try NextSignerConfigBackupManager.restore(from: url, into: store)
                            backupMessage = "Configuration and GitHub PAT restored successfully."
                            backupError = nil
                        } catch {
                            backupError = error.localizedDescription
                        }
                    },
                    onCancel: { restorePicker = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let shareURL { NextSignerShareSheet(items: [shareURL]) }
            }
        }
    }
}
