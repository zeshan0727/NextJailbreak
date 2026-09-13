import SwiftUI
import UIKit
import PhotosUI

struct NextSignerRootView: View {
    @StateObject private var store = SignerStore()

    var body: some View {
        TabView {
            NextSignerManualSignView(store: store)
                .tabItem { Label("Sign", systemImage: "signature") }

            NextSignerLibraryView(store: store)
                .tabItem { Label("Library", systemImage: "square.stack.3d.up.fill") }

            NextSignerActivityView(store: store)
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }

            SigningProfileView(store: store)
                .tabItem { Label("Profiles", systemImage: "checkmark.seal.fill") }

            NextSignerSettingsPlusView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(.accentColor)
    }
}

private enum PickerTarget: Int, Identifiable {
    case app
    case icon
    case tweaks
    var id: Int { rawValue }
}

private struct NextSignerSignView: View {
    @ObservedObject var store: SignerStore
    @State private var pickerTarget: PickerTarget?
    @State private var selectedPhotoIcon: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    appCard
                    detailsCard
                    advancedCard
                    publishCard
                }
                .padding()
            }
            .navigationTitle("Next Signer")
            .sheet(item: $pickerTarget) { target in
                UIKitDocumentPicker(
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
            .alert("Next Signer", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "Unknown error")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Publish. Sign when needed.", systemImage: "paperplane.circle.fill")
                .font(.title2.bold())
            Text("Publish an IPA exactly as selected, or enable signing for bundle changes, duplicate installs, custom icons and tweak injection before publishing through Cloudflare R2.")
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
                            Text(url.lastPathComponent)
                                .font(.headline)
                                .lineLimit(2)
                            Text(fileSizeText(url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { store.clearSelectedIPA() } label: {
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
            Label("App", systemImage: "app.dashed")
        }
    }

    private var detailsCard: some View {
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
                         ? "Bundle identifier format is valid. Keep it under com.nextsolution.* when using the wildcard Ad Hoc profile."
                         : "Enter a valid reverse-DNS bundle identifier, for example com.nextsolution.myapp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Signing identity", systemImage: "number")
        }
    }

    private var advancedCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Enable signing", isOn: $store.request.signingEnabled)
                    .fontWeight(.semibold)
                Text(store.request.signingEnabled
                     ? "Sign & Publish uses the saved P12 and provisioning profile."
                     : "Publish Only uploads the IPA unchanged. It must already contain a usable signature if you want OTA installation to work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                Text("Photos uses Apple’s native photo picker. Files still accepts PNG, JPG and JPEG.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

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
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
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
                    Text("Only inject tweaks you trust and that are compatible with the target app. DEB support extracts dylibs; packages needing extra jailbreak services may not work in a sideloaded app.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Advanced signing", systemImage: "slider.horizontal.3")
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

    private var publishCard: some View {
        GroupBox {
            VStack(spacing: 12) {
                if store.isWorking {
                    ProgressView(value: store.progress)
                    Text(store.activeJob?.detail ?? "Working…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let success = store.successMessage {
                    Label(success, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button { store.signAndPublish() } label: {
                    Label(
                        store.isWorking
                            ? (store.request.signingEnabled ? "Signing & Publishing…" : "Publishing…")
                            : (store.request.signingEnabled ? "Sign & Publish" : "Publish"),
                        systemImage: store.request.signingEnabled ? "signature" : "paperplane.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!store.request.isReady || store.isWorking || !store.tokenIsStored)

                if !store.tokenIsStored {
                    Text("Add your GitHub token once in Settings before the first use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Publish", systemImage: "arrow.up.circle")
        }
    }

    private func documentTypes(for target: PickerTarget) -> [String] {
        switch target {
        case .app:
            return ["public.item", "public.data", "public.archive", "com.apple.itunes.ipa"]
        case .icon:
            return ["public.image", "public.png", "public.jpeg"]
        case .tweaks:
            return ["public.item", "public.data", "public.archive"]
        }
    }

    private func handlePickedFiles(_ urls: [URL], for target: PickerTarget) {
        switch target {
        case .app:
            guard let url = urls.first else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "ipa" || ext == "tipa" else {
                store.errorMessage = "Please choose an .ipa or .tipa file."
                return
            }
            store.importIPA(from: url)
        case .icon:
            if let url = urls.first { store.importCustomIcon(from: url) }
        case .tweaks:
            store.importTweaks(from: urls)
        }
    }

    private func fileSizeText(_ url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize else { return "IPA / TIPA" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

private struct PendingLibraryOperation: Identifiable {
    let id = UUID()
    let app: PublishedApp
    let action: LibraryAction
}

private struct NextSignerLibraryView: View {
    @ObservedObject var store: SignerStore
    @State private var searchText = ""
    @State private var pendingOperation: PendingLibraryOperation?

    private var filteredApps: [PublishedApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.libraryApps }
        return store.libraryApps.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.bundleId.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = store.libraryMessage {
                    Section {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundColor(.green)
                    }
                }

                if let error = store.libraryErrorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }

                if store.libraryIsLoading && store.libraryApps.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView("Loading library…"); Spacer() }
                            .padding(.vertical, 24)
                    }
                } else if filteredApps.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "square.stack.3d.up.slash")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(searchText.isEmpty ? "No published apps" : "No matching apps")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    Section("Published apps") {
                        ForEach(filteredApps) { app in
                            publishedAppRow(app)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search apps")
            .refreshable { await store.refreshLibrary() }
            .task {
                if store.libraryApps.isEmpty { await store.refreshLibrary() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await store.refreshLibrary() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.libraryIsLoading)
                }
            }
            .alert(
                pendingOperation?.action == .deleteApp ? "Delete app and stored files?" : "Clean old versions?",
                isPresented: Binding(
                    get: { pendingOperation != nil },
                    set: { if !$0 { pendingOperation = nil } }
                ),
                presenting: pendingOperation
            ) { operation in
                Button("Cancel", role: .cancel) { pendingOperation = nil }
                Button(operation.action == .deleteApp ? "Delete" : "Clean", role: .destructive) {
                    pendingOperation = nil
                    Task { await store.manageLibrary(app: operation.app, action: operation.action) }
                }
            } message: { operation in
                if operation.action == .deleteApp {
                    Text("This removes \(operation.app.name) from the site and deletes all managed R2 versions for this app.")
                } else {
                    Text("This keeps the current \(operation.app.version) build and deletes older R2 versions for \(operation.app.name).")
                }
            }
        }
    }

    @ViewBuilder
    private func publishedAppRow(_ app: PublishedApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                libraryIcon(app)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.headline)
                    Text("v\(app.version) · build \(app.build)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(app.bundleId)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if store.libraryManagingAppID == app.id {
                    ProgressView()
                }
            }

            HStack(spacing: 10) {
                if app.available ?? false, app.manifest != nil {
                    Button { install(app) } label: {
                        Label("Install", systemImage: "arrow.down.app.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Menu {
                    if let download = app.downloadURL, let url = URL(string: download) {
                        Link(destination: url) {
                            Label("Open Download", systemImage: "arrow.down.circle")
                        }
                    }
                    if app.isR2Backed {
                        Button {
                            pendingOperation = PendingLibraryOperation(app: app, action: .cleanOldVersions)
                        } label: {
                            Label("Clean Old Versions", systemImage: "externaldrive.badge.minus")
                        }
                    }
                    Button(role: .destructive) {
                        pendingOperation = PendingLibraryOperation(app: app, action: .deleteApp)
                    } label: {
                        Label("Delete from Site & Storage", systemImage: "trash")
                    }
                } label: {
                    Label("Manage", systemImage: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .disabled(store.libraryManagingAppID != nil)
            }

            HStack(spacing: 8) {
                if let storage = app.storage {
                    Label(storage, systemImage: "externaldrive.fill")
                }
                if let bytes = app.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func libraryIcon(_ app: PublishedApp) -> some View {
        if let url = absoluteURL(app.icon) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "app.fill").resizable().scaledToFit().padding(11)
                case .empty:
                    ProgressView()
                @unknown default:
                    Image(systemName: "app.fill").resizable().scaledToFit().padding(11)
                }
            }
            .frame(width: 58, height: 58)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Image(systemName: "app.fill")
                .font(.title2)
                .frame(width: 58, height: 58)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func install(_ app: PublishedApp) {
        guard let manifest = absoluteURL(app.manifest) else { return }
        let encoded = manifest.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? manifest.absoluteString
        guard let installURL = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") else { return }
        UIApplication.shared.open(installURL)
    }

    private func absoluteURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let absolute = URL(string: value), absolute.scheme != nil { return absolute }
        return URL(string: value, relativeTo: URL(string: "https://nextjailbreak.com")!)?.absoluteURL
    }
}

private struct NextSignerActivityView: View {
    @ObservedObject var store: SignerStore

    var body: some View {
        NavigationStack {
            List {
                if let job = store.activeJob {
                    Section("Current job") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: icon(for: job.stage))
                                Text(job.requestedAppName).font(.headline)
                                Spacer()
                                Text(job.stage.rawValue).font(.caption.bold())
                            }
                            Text(job.sourceName).font(.caption).foregroundStyle(.secondary)
                            Text(job.requestedBundleID).font(.caption2).foregroundStyle(.secondary)
                            Text(job.detail).font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "signature")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("No signing jobs yet").font(.headline)
                            Text("Your latest Sign & Publish job will appear here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                }

                Section("Private apps") {
                    Link(destination: URL(string: "https://nextjailbreak.com/install/")!) {
                        Label("Open Web Library", systemImage: "safari")
                    }
                    Text("Use the Library tab for native browsing, installation and storage cleanup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activity")
        }
    }

    private func icon(for stage: SigningJob.Stage) -> String {
        switch stage {
        case .preparing: return "gearshape.2"
        case .uploading: return "arrow.up.circle"
        case .queued: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}

private struct NextSignerSettingsView: View {
    @ObservedObject var store: SignerStore
    @State private var revealToken = false

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

                Section("Required token permissions") {
                    Label("Contents: Read and write", systemImage: "doc.badge.gearshape")
                    Label("Actions: Read and write (signing workflow)", systemImage: "bolt.horizontal.circle")
                    Text("Library deletion now uses repository dispatch, so it no longer depends on the Actions API. Scope the token only to the NextSolution repository.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Signing security") {
                    Text("The P12 certificate, password, provisioning profile and Cloudflare R2 keys remain in encrypted GitHub Actions secrets. They are never stored inside Next Signer.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            .onDisappear { store.persistConfiguration() }
        }
    }
}

private struct UIKitDocumentPicker: UIViewControllerRepresentable {
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
        let parent: UIKitDocumentPicker
        init(parent: UIKitDocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !urls.isEmpty else { parent.onCancel(); return }
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
