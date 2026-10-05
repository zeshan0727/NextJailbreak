import SwiftUI
import UIKit

struct NextSignerLocalSignView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                NSBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        hero
                        sourceCard
                        identityCard
                        credentialsCard
                        optionsCard
                        signCard
                    }
                    .nsPagePadding()
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Sign")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { local.refreshCredentials() }
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

    private var hero: some View {
        NSGlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                NSPageHeader(
                    eyebrow: "Next Signer 1.5",
                    title: "Sign on your iPhone",
                    subtitle: "Private, local IPA signing with your saved certificate and provisioning profile. Publishing stays a separate action.",
                    systemImage: "signature"
                )

                HStack(spacing: 8) {
                    NSStatusChip(
                        text: local.credentialsReady ? "Profile ready" : "Profile needed",
                        systemImage: local.credentialsReady ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                        tint: local.credentialsReady ? NSTheme.mint : NSTheme.warning
                    )
                    NSStatusChip(text: "On-device", systemImage: "iphone", tint: NSTheme.cyan)
                }
            }
        }
    }

    private var sourceCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                NSSectionHeader("Source app", subtitle: "IPA or TIPA from Files", systemImage: "shippingbox.fill")

                if let url = store.request.ipaURL {
                    HStack(spacing: 13) {
                        NSIconBadge(systemImage: "app.fill", size: 54, tint: NSTheme.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(2)

                            Text(fileSizeText(url))
                                .font(.caption)
                                .foregroundStyle(NSTheme.textSecondary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            store.clearSelectedIPA()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(NSTheme.danger)
                                .frame(width: 38, height: 38)
                                .background(NSTheme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    VStack(spacing: 10) {
                        NSIconBadge(systemImage: "square.and.arrow.down.fill", size: 58, tint: NSTheme.violet)
                        Text("Choose an app to sign")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("The file stays on this device during local signing.")
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Button {
                    showPicker = true
                } label: {
                    Label(
                        store.request.ipaURL == nil ? "Choose IPA / TIPA" : "Choose Another App",
                        systemImage: "folder.fill"
                    )
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.cyan))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var identityCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                NSSectionHeader("App identity", subtitle: "Name and bundle identifier for the signed copy", systemImage: "character.cursor.ibeam")

                TextField("App name", text: $store.request.appName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .textFieldStyle(NSModernTextFieldStyle())

                TextField("Bundle ID", text: $store.request.bundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textFieldStyle(NSModernTextFieldStyle())

                HStack(spacing: 8) {
                    Image(systemName: store.request.isValidBundleID ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(store.request.isValidBundleID ? NSTheme.mint : NSTheme.warning)

                    Text(store.request.isValidBundleID ? "Bundle identifier is valid" : "Enter a valid reverse-DNS bundle identifier")
                        .font(.caption)
                        .foregroundStyle(NSTheme.textSecondary)

                    Spacer()
                }
            }
        }
    }

    private var credentialsCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                NSSectionHeader("Signing profile", subtitle: "Stored only on this iPhone", systemImage: "person.badge.key.fill")

                credentialRow("P12 certificate", systemImage: "key.fill", ready: local.hasP12)
                credentialRow("Provisioning profile", systemImage: "doc.badge.gearshape", ready: local.hasProvisioningProfile)
                credentialRow("P12 password", systemImage: "lock.fill", ready: local.p12PasswordIsStored)

                Divider().overlay(Color.white.opacity(0.08))

                if local.credentialsReady {
                    NSStatusChip(text: "Ready for local signing", systemImage: "checkmark.shield.fill", tint: NSTheme.mint)
                } else {
                    Text("Complete the missing item in Profiles before signing.")
                        .font(.footnote)
                        .foregroundStyle(NSTheme.warning)
                }
            }
        }
    }

    private func credentialRow(_ title: String, systemImage: String, ready: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(ready ? NSTheme.mint : Color.white.opacity(0.38))
                .frame(width: 26)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)

            Spacer()

            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? NSTheme.mint : Color.white.opacity(0.25))
        }
    }

    private var optionsCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                NSSectionHeader("Signing options", subtitle: "Control how the signed copy is installed", systemImage: "slider.horizontal.3")

                Toggle(isOn: Binding(
                    get: { store.request.duplicateSigning },
                    set: { store.setDuplicateSigning($0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Install as duplicate")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Generate a unique bundle ID so it can sit beside the original app.")
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)
                    }
                }
                .tint(NSTheme.cyan)
            }
        }
    }

    private var signCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                NSSectionHeader("Ready to sign", subtitle: "No GitHub upload happens here", systemImage: "checkmark.seal.fill")

                if local.isSigning {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: local.signingProgress)
                            .tint(NSTheme.cyan)
                        Text(local.signingMessage.isEmpty ? "Signing locally…" : local.signingMessage)
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)
                    }
                }

                Button {
                    store.request.signingEnabled = true
                    local.sign(request: store.request)
                } label: {
                    Label(local.isSigning ? "Signing on iPhone…" : "Sign IPA Locally", systemImage: "signature")
                }
                .buttonStyle(NSPrimaryButtonStyle())
                .disabled(
                    store.request.ipaURL == nil ||
                    store.request.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !store.request.isValidBundleID ||
                    !local.credentialsReady ||
                    local.isSigning
                )
                .opacity(
                    store.request.ipaURL == nil ||
                    !store.request.isValidBundleID ||
                    !local.credentialsReady ? 0.45 : 1
                )

                if let success = local.signingSuccess {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(NSTheme.mint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "IPA / TIPA" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct NextSignerSignedAppsView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @State private var shareURL: URL?
    @State private var deleteCandidate: LocalSignedApp?

    var body: some View {
        NavigationStack {
            ZStack {
                NSBackground()

                ScrollView {
                    LazyVStack(spacing: 14) {
                        NSPageHeader(
                            eyebrow: "Local Vault",
                            title: "Signed Apps",
                            subtitle: "Install, publish, share or remove signed IPAs saved on this iPhone.",
                            systemImage: "checkmark.seal.fill"
                        )

                        if let message = local.publishMessage {
                            NSGlassCard {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(NSTheme.mint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let error = local.publishError {
                            NSGlassCard {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(NSTheme.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }

                        if local.signedApps.isEmpty {
                            emptyState
                        } else {
                            HStack {
                                Text("\(local.signedApps.count) SIGNED APP\(local.signedApps.count == 1 ? "" : "S")")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(NSTheme.textSecondary)
                                Spacer()
                            }

                            ForEach(local.signedApps) { app in
                                signedAppCard(app)
                            }
                        }
                    }
                    .nsPagePadding()
                    .padding(.bottom, 16)
                }
                .refreshable { local.refreshSignedApps() }
            }
            .navigationTitle("Signed Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { local.refreshSignedApps() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(NSTheme.cyan)
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

    private var emptyState: some View {
        NSGlassCard {
            VStack(spacing: 13) {
                NSIconBadge(systemImage: "checkmark.seal", size: 60, tint: NSTheme.violet)
                Text("Your signed apps will live here")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Sign an IPA from the Sign tab. The finished IPA is saved locally and appears here automatically.")
                    .font(.footnote)
                    .foregroundStyle(NSTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }

    private func signedAppCard(_ app: LocalSignedApp) -> some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 13) {
                    NSIconBadge(systemImage: "app.badge.checkmark.fill", size: 58, tint: NSTheme.mint)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.appName)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text(app.bundleID)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.white.opacity(0.48))
                            .lineLimit(1)

                        Text([app.version.isEmpty ? nil : "v\(app.version)", app.build.isEmpty ? nil : "build \(app.build)"].compactMap { $0 }.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)
                    }

                    Spacer()
                }

                HStack(spacing: 8) {
                    if app.sizeBytes > 0 {
                        NSStatusChip(
                            text: ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file),
                            systemImage: "shippingbox.fill",
                            tint: NSTheme.blue
                        )
                    }
                    NSStatusChip(
                        text: app.minimumOS,
                        systemImage: "iphone",
                        tint: NSTheme.violet
                    )
                }

                Text("Signed \(app.signedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.40))

                if local.installingID == app.id {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressView().tint(NSTheme.mint)
                        Text(local.installMessage ?? "Preparing Apple OTA installation…")
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)
                    }
                }

                if local.publishingID == app.id {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressView(value: local.publishProgress)
                            .tint(NSTheme.cyan)
                        Text("Publishing signed IPA to site…")
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)
                    }
                }

                HStack(spacing: 9) {
                    Button {
                        local.install(app, using: store)
                    } label: {
                        Label("Install", systemImage: "arrow.down.app.fill")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.mint))
                    .disabled(local.installingID != nil || local.publishingID != nil)

                    Button {
                        local.publish(app, using: store)
                    } label: {
                        Label("Publish", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.cyan))
                    .disabled(local.publishingID != nil || local.installingID != nil)
                }

                HStack(spacing: 9) {
                    Button {
                        shareURL = app.ipaURL
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.blue))

                    Button(role: .destructive) {
                        deleteCandidate = app
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.danger))
                    .disabled(local.publishingID == app.id || local.installingID == app.id)
                }

                Text("Install uses temporary Apple OTA staging. Publish is separate and only runs when you press Publish.")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.42))
            }
        }
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
            ZStack {
                NSBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        NSPageHeader(
                            eyebrow: "Local Security",
                            title: "Signing Profile",
                            subtitle: "Your P12, provisioning profile and password stay on this iPhone for on-device signing.",
                            systemImage: "person.badge.key.fill"
                        )

                        readinessCard
                        certificateCard
                        passwordCard
                        provisioningCard

                        if let message = local.signingSuccess {
                            NSGlassCard {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(NSTheme.mint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let error = local.signingError {
                            NSGlassCard {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(NSTheme.danger)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .nsPagePadding()
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
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

    private var readinessCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                NSSectionHeader("Readiness", subtitle: "Three items are required", systemImage: "checkmark.shield.fill")
                profileStatus("P12 certificate", systemImage: "key.fill", ready: local.hasP12)
                profileStatus("P12 password", systemImage: "lock.fill", ready: local.p12PasswordIsStored)
                profileStatus("Provisioning profile", systemImage: "doc.badge.gearshape", ready: local.hasProvisioningProfile)

                if local.credentialsReady {
                    NSStatusChip(text: "Ready for local signing", systemImage: "checkmark.circle.fill", tint: NSTheme.mint)
                }
            }
        }
    }

    private var certificateCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                NSSectionHeader("Certificate", subtitle: "PKCS#12 signing identity", systemImage: "key.fill")

                Button {
                    pickerTarget = .p12
                } label: {
                    Label(local.hasP12 ? "Replace P12 Certificate" : "Import P12 Certificate", systemImage: "folder.badge.plus")
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.cyan))

                if local.hasP12 {
                    Button(role: .destructive) {
                        local.removeCredential(.p12)
                    } label: {
                        Label("Remove P12", systemImage: "trash")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.danger))
                }
            }
        }
    }

    private var passwordCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                NSSectionHeader("Certificate password", subtitle: "Stored in iOS Keychain", systemImage: "lock.fill")

                SecureField("P12 password", text: $local.p12Password)
                    .textContentType(.password)
                    .textFieldStyle(NSModernTextFieldStyle())

                Button {
                    local.saveP12Password()
                } label: {
                    Label(local.p12PasswordIsStored ? "Update Keychain Password" : "Save Password to Keychain", systemImage: "key.fill")
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.violet))
            }
        }
    }

    private var provisioningCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                NSSectionHeader("Provisioning profile", subtitle: "Ad Hoc .mobileprovision", systemImage: "doc.badge.gearshape")

                Button {
                    pickerTarget = .provisioning
                } label: {
                    Label(local.hasProvisioningProfile ? "Replace Provisioning Profile" : "Import Provisioning Profile", systemImage: "folder.badge.plus")
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.cyan))

                if local.hasProvisioningProfile {
                    Button(role: .destructive) {
                        local.removeCredential(.provisioning)
                    } label: {
                        Label("Remove Provisioning Profile", systemImage: "trash")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.danger))
                }
            }
        }
    }

    private func profileStatus(_ title: String, systemImage: String, ready: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(ready ? NSTheme.mint : Color.white.opacity(0.35))
                .frame(width: 28)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer()
            Text(ready ? "Ready" : "Missing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(ready ? NSTheme.mint : NSTheme.warning)
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
            ZStack {
                NSBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        NSPageHeader(
                            eyebrow: "Configuration",
                            title: "Settings",
                            subtitle: "Local signing stays local. GitHub is used only for OTA staging and publishing actions you explicitly start.",
                            systemImage: "gearshape.fill"
                        )

                        architectureCard
                        publishingCard
                        tokenCard
                        backupCard
                        securityCard
                        aboutCard
                    }
                    .nsPagePadding()
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { local.refreshCredentials() }
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

    private var architectureCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 13) {
                NSSectionHeader("Architecture", subtitle: "Local first, cloud only when requested", systemImage: "cpu.fill")

                settingStatus(
                    "Local signing",
                    detail: local.credentialsReady ? "Ready on this iPhone" : "Complete Profiles setup",
                    systemImage: "iphone",
                    ready: local.credentialsReady
                )

                settingStatus(
                    "Publishing connection",
                    detail: store.tokenIsStored ? "GitHub PAT saved" : "PAT not configured",
                    systemImage: "cloud.fill",
                    ready: store.tokenIsStored
                )
            }
        }
    }

    private var publishingCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 11) {
                NSSectionHeader("Publishing repository", subtitle: "Used only when staging or publishing", systemImage: "arrow.triangle.branch")

                TextField("Owner", text: $store.configuration.owner)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(NSModernTextFieldStyle())

                TextField("Repository", text: $store.configuration.repository)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(NSModernTextFieldStyle())

                TextField("Branch", text: $store.configuration.branch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(NSModernTextFieldStyle())

                TextField("Workflow file", text: $store.configuration.workflowFile)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(NSModernTextFieldStyle())
            }
        }
    }

    private var tokenCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                NSSectionHeader("Fine-grained GitHub PAT", subtitle: "Contents: Read and write", systemImage: "lock.shield.fill")

                if revealToken {
                    TextField("github_pat_…", text: $store.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(NSModernTextFieldStyle())
                } else {
                    SecureField("github_pat_…", text: $store.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(NSModernTextFieldStyle())
                }

                Toggle("Show token", isOn: $revealToken)
                    .tint(NSTheme.cyan)
                    .foregroundStyle(.white)

                Button {
                    store.saveToken()
                } label: {
                    Label("Save PAT to Keychain", systemImage: "lock.fill")
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.cyan))

                NSStatusChip(
                    text: store.tokenIsStored ? "PAT saved" : "PAT not configured",
                    systemImage: store.tokenIsStored ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                    tint: store.tokenIsStored ? NSTheme.mint : NSTheme.warning
                )
            }
        }
    }

    private var backupCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                NSSectionHeader("Backup & Restore", subtitle: "Repository settings and PAT", systemImage: "externaldrive.fill")

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
                    Label("Backup Current Config", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.blue))

                Button {
                    restorePicker = true
                } label: {
                    Label("Restore Config Backup", systemImage: "arrow.clockwise.icloud")
                }
                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.violet))

                Text("Config backups contain your GitHub PAT. They do not contain the P12 certificate or provisioning profile.")
                    .font(.caption)
                    .foregroundStyle(NSTheme.warning)

                if let backupMessage {
                    Label(backupMessage, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(NSTheme.mint)
                }

                if let backupError {
                    Label(backupError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(NSTheme.danger)
                }
            }
        }
    }

    private var securityCard: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 11) {
                NSSectionHeader("Local signing security", subtitle: "Credential storage status", systemImage: "shield.lefthalf.filled")

                settingStatus("P12 certificate", detail: local.hasP12 ? "Stored locally" : "Not stored", systemImage: "key.fill", ready: local.hasP12)
                settingStatus("Provisioning profile", detail: local.hasProvisioningProfile ? "Stored locally" : "Not stored", systemImage: "doc.badge.gearshape", ready: local.hasProvisioningProfile)
                settingStatus("P12 password", detail: local.p12PasswordIsStored ? "Stored in Keychain" : "Not stored", systemImage: "lock.fill", ready: local.p12PasswordIsStored)

                Text("Signing credentials are not uploaded when you sign an IPA.")
                    .font(.caption)
                    .foregroundStyle(NSTheme.textSecondary)
            }
        }
    }

    private var aboutCard: some View {
        NSGlassCard {
            HStack(spacing: 13) {
                NSIconBadge(systemImage: "signature", size: 54, tint: NSTheme.violet)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Signer")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Version 1.5.1  •  Build 27")
                        .font(.caption)
                        .foregroundStyle(NSTheme.textSecondary)
                    Text("Local signing + Apple OTA + private publishing")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.42))
                }
                Spacer()
            }
        }
    }

    private func settingStatus(_ title: String, detail: String, systemImage: String, ready: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(ready ? NSTheme.mint : NSTheme.warning)
                .frame(width: 27)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(NSTheme.textSecondary)
            }
            Spacer()
            Image(systemName: ready ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(ready ? NSTheme.mint : Color.white.opacity(0.25))
        }
    }
}
