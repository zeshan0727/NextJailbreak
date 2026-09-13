import PhotosUI
import SwiftUI
import UIKit

struct NextSignerManualSignView: View {
    @ObservedObject var store: SignerStore
    @StateObject private var flow = ManualSignController()
    @State private var pickerTarget: ManualPickerTarget?
    @State private var selectedPhotoIcon: PhotosPickerItem?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    appCard
                    identityCard
                    advancedCard
                    signCard
                    if flow.result != nil { signedResultCard }
                }
                .padding()
            }
            .navigationTitle("Next Signer")
            .sheet(item: $pickerTarget) { target in
                ManualDocumentPicker(
                    documentTypes: documentTypes(for: target),
                    allowsMultipleSelection: target == .tweaks,
                    onPick: { urls in
                        pickerTarget = nil
                        handlePickedFiles(urls, for: target)
                    },
                    onCancel: { pickerTarget = nil }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let shareURL { NextSignerShareSheet(items: [shareURL]) }
            }
            .alert("Next Signer", isPresented: Binding(
                get: { flow.errorMessage != nil || store.errorMessage != nil },
                set: { if !$0 { flow.errorMessage = nil; store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {
                    flow.errorMessage = nil
                    store.errorMessage = nil
                }
            } message: {
                Text(flow.errorMessage ?? store.errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sign first. Publish when you choose.", systemImage: "signature")
                .font(.title2.bold())
            Text("Next Signer signs the IPA first and saves the signed copy on this iPhone. Nothing is added to the website until you manually tap Publish to Site.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if let url = store.request.ipaURL {
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.title2)
                            .frame(width: 42, height: 42)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent).font(.headline).lineLimit(2)
                            Text(fileSizeText(url)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            store.clearSelectedIPA()
                            flow.forgetResult()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 34))
                        Text("No IPA selected").font(.headline)
                        Text("Choose an IPA or TIPA from Files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Button { pickerTarget = .app } label: {
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

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: store.request.isValidBundleID ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(store.request.isValidBundleID ? .green : .orange)
                    Text(store.request.isValidBundleID
                         ? "Bundle identifier format is valid."
                         : "Enter a valid bundle identifier, for example com.nextsolution.myapp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } label: {
            Label("Signing identity", systemImage: "number")
        }
    }

    private var advancedCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("Signing is always enabled in this workflow.", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)

                Divider()

                Toggle("Install as duplicate app", isOn: Binding(
                    get: { store.request.duplicateSigning },
                    set: { store.setDuplicateSigning($0) }
                ))
                Text("Creates a unique bundle ID so the signed copy can install beside the original.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 12) {
                    customIconPreview
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Custom app icon").font(.headline)
                        Text(store.request.customIconURL?.lastPathComponent ?? "Keep the original IPA icon")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                HStack {
                    PhotosPicker(selection: $selectedPhotoIcon, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button { pickerTarget = .icon } label: {
                        Label("Files", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    if store.request.customIconURL != nil {
                        Button("Remove", role: .destructive) { store.clearCustomIcon() }
                            .buttonStyle(.bordered)
                    }
                }
                .onChange(of: selectedPhotoIcon) { item in
                    guard let item else { return }
                    Task { @MainActor in
                        defer { selectedPhotoIcon = nil }
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self),
                                  let image = UIImage(data: data),
                                  let pngData = image.pngData() else {
                                store.errorMessage = "The selected photo could not be converted to PNG."
                                return
                            }
                            store.importCustomIconPNGData(pngData)
                        } catch {
                            store.errorMessage = "Unable to load the selected photo: \(error.localizedDescription)"
                        }
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tweak injection").font(.headline)
                        Text("Attach .dylib files or .deb packages containing dylibs.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.request.tweakURLs.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                }

                ForEach(store.request.tweakURLs, id: \.self) { url in
                    HStack {
                        Image(systemName: url.pathExtension.lowercased() == "deb" ? "shippingbox" : "puzzlepiece.extension")
                        Text(url.lastPathComponent).font(.caption).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { store.removeTweak(url) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button { pickerTarget = .tweaks } label: {
                    Label("Attach Tweaks", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !store.request.tweakURLs.isEmpty {
                    Toggle("Inject into app extensions", isOn: $store.request.injectTweaksIntoExtensions)
                    Toggle("Weak dylib injection", isOn: $store.request.weakTweakInjection)
                }
            }
        } label: {
            Label("Advanced signing", systemImage: "slider.horizontal.3")
        }
    }

    private var signCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if flow.isSigning {
                    ProgressView(value: flow.progress)
                    Text(flow.statusMessage.isEmpty ? "Signing…" : flow.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    store.request.signingEnabled = true
                    flow.sign(using: store)
                } label: {
                    Label(flow.isSigning ? "Signing IPA…" : "Sign IPA", systemImage: "signature")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.request.ipaURL == nil || !store.request.isValidBundleID || store.request.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || flow.isSigning || flow.isPublishing || !store.tokenIsStored)

                Text("Signing does not publish the app to the website. The signed IPA is downloaded into Documents → Signed IPAs on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("1. Sign", systemImage: "checkmark.seal")
        }
    }

    private var signedResultCard: some View {
        GroupBox {
            if let result = flow.result {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Signed IPA Ready", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.filename).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Text([result.version.isEmpty ? nil : "v\(result.version)", result.build.isEmpty ? nil : "build \(result.build)"].compactMap { $0 }.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(result.bundleID).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: result.sizeBytes, countStyle: .file))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Label("Saved on this iPhone in Documents / Signed IPAs", systemImage: "iphone.and.arrow.forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        flow.install()
                    } label: {
                        Label("Install", systemImage: "arrow.down.app.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)

                    Button {
                        shareURL = result.localURL
                    } label: {
                        Label("Save / Share Signed IPA", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Divider()

                    if flow.isPublishing {
                        ProgressView(value: flow.progress)
                        Text("Publishing the already-signed IPA to the website…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        flow.publishToSite(using: store)
                    } label: {
                        Label(flow.isPublishing ? "Publishing…" : "Publish to Site", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(flow.isSigning || flow.isPublishing)

                    Text("Publishing starts only when you press this button. It uploads the already-signed IPA unchanged and creates/updates the installer entry on the site.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let message = flow.publishMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    Button("Forget Current Signed Result", role: .destructive) {
                        flow.forgetResult()
                    }
                    .font(.caption)
                }
            }
        } label: {
            Label("2. Signed IPA", systemImage: "shippingbox.and.arrow.backward")
        }
    }

    @ViewBuilder
    private var customIconPreview: some View {
        if let url = store.request.customIconURL, let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 13))
        } else {
            Image(systemName: "app.fill")
                .font(.title2)
                .frame(width: 54, height: 54)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func documentTypes(for target: ManualPickerTarget) -> [String] {
        switch target {
        case .app:
            return ["public.item", "public.data", "public.archive", "com.apple.itunes.ipa"]
        case .icon:
            return ["public.image", "public.png", "public.jpeg"]
        case .tweaks:
            return ["public.item", "public.data", "public.archive"]
        case .config:
            return ["public.json", "public.text", "public.data", "public.item"]
        }
    }

    private func handlePickedFiles(_ urls: [URL], for target: ManualPickerTarget) {
        switch target {
        case .app:
            guard let url = urls.first else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "ipa" || ext == "tipa" else {
                store.errorMessage = "Please choose an .ipa or .tipa file."
                return
            }
            flow.forgetResult()
            store.importIPA(from: url)
            store.request.signingEnabled = true
        case .icon:
            if let url = urls.first { store.importCustomIcon(from: url) }
        case .tweaks:
            store.importTweaks(from: urls)
        case .config:
            break
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let bytes = values.fileSize else { return "IPA / TIPA" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

enum ManualPickerTarget: Int, Identifiable {
    case app
    case icon
    case tweaks
    case config
    var id: Int { rawValue }
}

struct NextSignerSettingsPlusView: View {
    @ObservedObject var store: SignerStore
    @State private var revealToken = false
    @State private var shareURL: URL?
    @State private var restorePicker = false
    @State private var backupMessage: String?
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("GitHub") {
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

                Section("Fine-grained token") {
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
                    Label(store.tokenIsStored ? "Token stored on this device" : "Token not configured",
                          systemImage: store.tokenIsStored ? "lock.fill" : "lock.open")
                        .font(.caption)
                        .foregroundColor(store.tokenIsStored ? .green : .gray)
                }

                Section("Backup & Restore") {
                    Button {
                        do {
                            store.persistConfiguration()
                            shareURL = try NextSignerConfigBackupManager.createBackup(store: store)
                            backupMessage = "Backup created. Choose Save to Files or another secure destination."
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

                    Text("The backup includes the saved GitHub PAT plus repository and signing settings. Treat the backup file like a password and keep it private.")
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

                Section("Required token permissions") {
                    Label("Contents: Read and write", systemImage: "doc.badge.gearshape")
                    Label("Actions: Read and write", systemImage: "bolt.horizontal.circle")
                    Label("Secrets: Read and write", systemImage: "lock.shield")
                    Text("Scope the token only to the NextJailbreak repository.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Signing security") {
                    Text("P12, password, provisioning profile and Cloudflare R2 credentials remain in GitHub Actions secrets. Config backup does not contain the P12 or provisioning profile files.")
                        .font(.footnote)
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

private struct NextSignerConfigBackup: Codable {
    let formatVersion: Int
    let createdAt: Date
    let owner: String
    let repository: String
    let branch: String
    let workflowFile: String
    let githubToken: String
    let duplicateSigning: Bool
    let injectTweaksIntoExtensions: Bool
    let weakTweakInjection: Bool
}

@MainActor
enum NextSignerConfigBackupManager {
    static func createBackup(store: SignerStore) throws -> URL {
        let token = KeychainStore.load(account: "github-token") ?? store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        let backup = NextSignerConfigBackup(
            formatVersion: 1,
            createdAt: Date(),
            owner: store.configuration.owner,
            repository: store.configuration.repository,
            branch: store.configuration.branch,
            workflowFile: store.configuration.workflowFile,
            githubToken: token,
            duplicateSigning: store.request.duplicateSigning,
            injectTweaksIntoExtensions: store.request.injectTweaksIntoExtensions,
            weakTweakInjection: store.request.weakTweakInjection
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Config Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = folder.appendingPathComponent("NextSigner-Config-\(formatter.string(from: Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func restore(from source: URL, into store: SignerStore) throws {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: source)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(NextSignerConfigBackup.self, from: data)
        guard backup.formatVersion == 1 else {
            throw NSError(domain: "NextSigner.ConfigBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported Next Signer config backup version."])
        }

        store.configuration.owner = backup.owner
        store.configuration.repository = backup.repository.caseInsensitiveCompare("NextSolution") == .orderedSame ? "NextJailbreak" : backup.repository
        store.configuration.branch = backup.branch
        store.configuration.workflowFile = backup.workflowFile
        store.request.duplicateSigning = backup.duplicateSigning
        store.request.injectTweaksIntoExtensions = backup.injectTweaksIntoExtensions
        store.request.weakTweakInjection = backup.weakTweakInjection
        store.token = backup.githubToken
        store.persistConfiguration()
        store.saveToken()
    }
}

struct ManualDocumentPicker: UIViewControllerRepresentable {
    let documentTypes: [String]
    let allowsMultipleSelection: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ManualDocumentPicker
        init(parent: ManualDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { parent.onCancel(); return }
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

struct NextSignerShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
