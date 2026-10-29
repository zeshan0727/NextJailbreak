import SwiftUI
import UIKit

struct NextSignerLocalSignView: View {
    @ObservedObject var store: SignerStore
    @ObservedObject var local: LocalSigningController
    @State private var showPicker = false
    @State private var capabilityPicker: ManualPickerTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    sourceCard
                    identityCard
                    credentialsCard
                    entitlementCard
                    optionsCard
                    signCard
                }
                .padding()
            }
            .navigationTitle("Sign IPA")
            .navigationBarTitleDisplayMode(.inline)
            .background(SignerDesign.canvas.ignoresSafeArea())
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
            .sheet(item: $capabilityPicker) { target in
                ManualDocumentPicker(
                    documentTypes: ["public.item"],
                    allowsMultipleSelection: false,
                    onPick: { urls in
                        capabilityPicker = nil
                        guard let url = urls.first else { return }
                        switch target {
                        case .provisioning: store.importProvisioningProfile(from: url)
                        case .entitlements: store.importEntitlements(from: url)
                        default: break
                        }
                    },
                    onCancel: { capabilityPicker = nil }
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
        VStack(alignment: .leading, spacing: 13) {
            Label("LOCAL SIGNING", systemImage: "lock.shield.fill")
                .font(.caption2.bold())
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.85))
            Text("Your IPA.\nYour signature.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Sign securely on your iPhone. Nothing is uploaded unless you choose Publish.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
            HStack {
                Image(systemName: local.credentialsReady ? "checkmark.seal.fill" : "exclamationmark.shield.fill")
                Text(local.credentialsReady ? "Signing profile ready" : "Set up signing credentials first")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
        }
        .padding(21)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignerDesign.hero, in: RoundedRectangle(cornerRadius: 24))
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
                TextField("Bundle ID", text: Binding(
                    get: { store.request.bundleID },
                    set: { updated in
                        let previous = store.request.bundleID
                        if store.request.iCloudContainerIdentifier == "iCloud." + previous {
                            store.request.iCloudContainerIdentifier = "iCloud." + updated
                        }
                        store.request.bundleID = updated
                    }
                ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textFieldStyle(.roundedBorder)
                if store.request.ipaURL != nil {
                    Text("Bundle ID is read from the original IPA's Info.plist. Keep it unchanged for an explicit iCloud App ID unless your selected profile also authorizes the replacement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                credentialRow("Provisioning profile", ready: local.hasProvisioningProfile || store.request.customProvisioningURL != nil)
                credentialRow("P12 password", ready: local.p12PasswordIsStored)
                if !(local.hasP12 && local.p12PasswordIsStored && (local.hasProvisioningProfile || store.request.customProvisioningURL != nil)) {
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

    private var entitlementCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable iCloud Documents (CloudDocuments)", isOn: Binding(
                    get: { store.request.enableICloudDocuments },
                    set: { enabled in
                        store.request.enableICloudDocuments = enabled
                        if enabled {
                            store.clearEntitlements()
                            if store.request.duplicateSigning { store.setDuplicateSigning(false) }
                            if store.request.iCloudContainerIdentifier.isEmpty {
                                store.request.iCloudContainerIdentifier = "iCloud." + store.request.bundleID
                            }
                        }
                    }
                ))
                if store.request.enableICloudDocuments {
                    TextField("iCloud container ID", text: $store.request.iCloudContainerIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("For Next Ledger: iCloud.com.nextsolution.dailyledger. Requires an explicit Ad Hoc profile for the exact app ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text("App-specific Ad Hoc profile").font(.subheadline.bold())
                Text(store.request.customProvisioningURL?.lastPathComponent ?? "Use local profile from Profiles tab")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack {
                    Button { capabilityPicker = .provisioning } label: {
                        Label("Choose .mobileprovision", systemImage: "doc.badge.gearshape")
                    }.buttonStyle(.bordered)
                    if store.request.customProvisioningURL != nil {
                        Button("Remove", role: .destructive) { store.clearProvisioningProfile() }
                    }
                }
                Divider()
                Text("Custom signing entitlements").font(.subheadline.bold())
                Text(store.request.customEntitlementsURL?.lastPathComponent
                     ?? (store.request.enableICloudDocuments ? "Generated for iCloud Documents" : "Use profile-derived defaults"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { capabilityPicker = .entitlements } label: {
                        Label("Choose .entitlements / .plist", systemImage: "doc.text")
                    }.buttonStyle(.bordered).disabled(store.request.enableICloudDocuments)
                    if store.request.customEntitlementsURL != nil {
                        Button("Remove", role: .destructive) { store.clearEntitlements() }
                    }
                }
                Text("Next Signer verifies the profile's capability permissions and checks the final executable's entitlements before saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            Label("Provisioning & Entitlements", systemImage: "checkmark.shield")
        }
    }

    private var optionsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Install as duplicate app", isOn: Binding(
                    get: { store.request.duplicateSigning },
                    set: { store.setDuplicateSigning($0) }
                ))
                .disabled(store.request.enableICloudDocuments)
                Text("Changes the bundle identifier so the signed copy can install beside the original app. Disabled for explicit iCloud App IDs.")
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
                    (!local.hasP12 || !local.p12PasswordIsStored ||
                     (!local.hasProvisioningProfile && store.request.customProvisioningURL == nil)) ||
                    (store.request.enableICloudDocuments &&
                     (!store.request.iCloudContainerIdentifier.hasPrefix("iCloud.") ||
                      store.request.duplicateSigning)) ||
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
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIDs = Set<UUID>()
    @State private var sortOrder = SortOrder.recent
    @State private var batchScope: BatchScope?
    @State private var showAllFailures = false

    private enum SortOrder: String, CaseIterable {
        case recent = "Newest"
        case name = "Name"
        case size = "Size"
    }
    private enum BatchScope: Equatable {
        case all
        case selected
        case single(UUID)
    }

    private var filteredApps: [LocalSignedApp] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var apps = local.signedApps.filter {
            q.isEmpty || $0.appName.localizedCaseInsensitiveContains(q) ||
                $0.bundleID.localizedCaseInsensitiveContains(q) ||
                $0.filename.localizedCaseInsensitiveContains(q)
        }
        switch sortOrder {
        case .recent: apps.sort { $0.signedAt > $1.signedAt }
        case .name: apps.sort { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
        case .size: apps.sort { $0.sizeBytes > $1.sizeBytes }
        }
        return apps
    }

    private var selectedApps: [LocalSignedApp] {
        local.signedApps.filter { selectedIDs.contains($0.id) }
    }

    private var requestedTargets: [LocalSignedApp] {
        switch batchScope {
        case .all: return local.signedApps
        case .selected: return selectedApps
        case let .single(id): return local.signedApps.filter { $0.id == id }
        case nil: return []
        }
    }

    private var isBusy: Bool {
        local.isBatchResigning || local.isSigning ||
            local.installingID != nil || local.publishingID != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heading
                    bulkActions
                    if local.isBatchResigning || local.batchResignMessage != nil ||
                       !local.batchResignFailures.isEmpty {
                        batchStatus
                    }
                    if let message = local.publishMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if let error = local.publishError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 14))
                    }
                    HStack {
                        SignerSectionHeader(
                            title: "Saved IPAs",
                            subtitle: "\(filteredApps.count) apps · originals kept during re-signing"
                        )
                        if !local.signedApps.isEmpty {
                            Button(isSelecting ? "Done" : "Select") {
                                isSelecting.toggle()
                                if !isSelecting { selectedIDs.removeAll() }
                            }
                            .font(.subheadline.weight(.semibold))
                            .disabled(local.isBatchResigning)
                        }
                    }

                    if !filteredApps.isEmpty {
                        HStack {
                            if isSelecting {
                                Button(allVisibleAreSelected ? "Deselect visible" : "Select all visible") {
                                    let ids = Set(filteredApps.map(\.id))
                                    if allVisibleAreSelected {
                                        selectedIDs.subtract(ids)
                                    } else {
                                        selectedIDs.formUnion(ids)
                                    }
                                }
                                .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(selectedApps.count) selected")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            } else {
                                Spacer()
                                Picker("Sort", selection: $sortOrder) {
                                    ForEach(SortOrder.allCases, id: \.self) { item in
                                        Text(item.rawValue).tag(item)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }

                    if filteredApps.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredApps) { app in
                                appCard(app)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(SignerDesign.canvas.ignoresSafeArea())
            .navigationTitle("Signed Apps")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search name, bundle ID or file")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { local.refreshSignedApps() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isBusy)
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
                    if let app = deleteCandidate {
                        local.deleteSignedApp(app)
                        selectedIDs.remove(app.id)
                    }
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            } message: {
                Text("Only this saved IPA is removed. Other signed copies are unaffected.")
            }
            .confirmationDialog(
                "Re-sign \(requestedTargets.count) saved app(s)?",
                isPresented: Binding(
                    get: { batchScope != nil },
                    set: { if !$0 { batchScope = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Re-sign \(requestedTargets.count) app(s)") {
                    let apps = requestedTargets
                    batchScope = nil
                    selectedIDs.removeAll()
                    isSelecting = false
                    local.resignBatch(apps)
                }
                Button("Cancel", role: .cancel) { batchScope = nil }
            } message: {
                Text("Uses your current local P12 and default provisioning profile. Original IPAs are kept. Special iCloud, App Groups and custom entitlements may need a matching profile and individual signing. Nothing is published automatically.")
            }
        }
    }

    private var allVisibleAreSelected: Bool {
        !filteredApps.isEmpty && filteredApps.allSatisfy { selectedIDs.contains($0.id) }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(SignerDesign.blue)
                    .frame(width: 48, height: 48)
                    .background(SignerDesign.blue.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your signed library").font(.title2.bold())
                    Text("Install, publish, share or re-sign")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(local.signedApps.count)")
                    .font(.title2.bold().monospacedDigit())
            }
            .padding(17)
            .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var bulkActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("Bulk re-sign", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                Spacer()
                SignerStatusDot(ready: local.credentialsReady,
                                label: local.credentialsReady ? "Ready" : "Needs profile")
            }
            Text("Refresh app signatures using the current saved certificate and default provisioning profile. No upload or publish.")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    batchScope = .all
                } label: {
                    Label("Re-sign All", systemImage: "arrow.clockwise.circle.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || !local.credentialsReady || local.signedApps.isEmpty)

                Button {
                    if !isSelecting {
                        isSelecting = true
                    } else {
                        batchScope = .selected
                    }
                } label: {
                    Label(
                        isSelecting ? "Re-sign (\(selectedApps.count))" : "Choose Apps",
                        systemImage: "checkmark.circle"
                    )
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || !local.credentialsReady ||
                          local.signedApps.isEmpty || (isSelecting && selectedApps.isEmpty))
            }
            if !local.credentialsReady {
                Label("Configure the P12, password and provisioning profile in Home → Manage signing profiles.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(17)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var batchStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(local.isBatchResigning ? "Re-signing in progress" : "Batch result",
                      systemImage: local.isBatchResigning ? "hourglass" : "checkmark.circle")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(local.batchResignCompleted)/\(local.batchResignTotal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: local.batchResignFraction)
                .tint(SignerDesign.blue)

            if local.isBatchResigning {
                Text("Current: \(local.batchResignCurrent)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Stop after current app", role: .cancel) {
                    local.cancelBatchResign()
                }
                .font(.caption.weight(.semibold))
            }
            if let message = local.batchResignMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if !local.batchResignFailures.isEmpty {
                DisclosureGroup(
                    "\(local.batchResignFailures.count) failed · View reasons",
                    isExpanded: $showAllFailures
                ) {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(local.batchResignFailures, id: \.self) { failure in
                            Text(failure)
                                .font(.caption2).foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 7)
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(17)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "square.stack.3d.up.slash" : "magnifyingglass")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "No signed apps yet" : "No matches")
                .font(.headline)
            Text(searchText.isEmpty
                 ? "Sign your first IPA locally from the Sign tab."
                 : "Try searching for a different app name or bundle ID.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private func appCard(_ app: LocalSignedApp) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                if isSelecting {
                    Button {
                        if selectedIDs.contains(app.id) {
                            selectedIDs.remove(app.id)
                        } else {
                            selectedIDs.insert(app.id)
                        }
                    } label: {
                        Image(systemName: selectedIDs.contains(app.id)
                              ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(selectedIDs.contains(app.id)
                                             ? SignerDesign.blue : .secondary)
                    }
                    .accessibilityLabel("Select \(app.appName)")
                }

                Image(systemName: "app.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(SignerDesign.blue)
                    .frame(width: 49, height: 49)
                    .background(SignerDesign.blue.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.appName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(app.bundleID)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Menu {
                    Button {
                        shareURL = app.ipaURL
                    } label: { Label("Share IPA", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) {
                        deleteCandidate = app
                    } label: { Label("Delete IPA", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .frame(width: 32, height: 32)
                }
                .disabled(isBusy)
            }

            HStack(spacing: 9) {
                if !app.version.isEmpty {
                    Text("v\(app.version)")
                }
                if app.sizeBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                }
                Text(app.signedAt, style: .date)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            if local.installingID == app.id {
                ProgressView()
                Text(local.installMessage ?? "Preparing installation…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if local.publishingID == app.id {
                ProgressView(value: local.publishProgress)
                Text("Publishing…").font(.caption).foregroundStyle(.secondary)
            }

            Divider().opacity(0.6)

            HStack(spacing: 9) {
                Button {
                    local.install(app, using: store)
                } label: { Label("Install", systemImage: "arrow.down.app") }
                    .buttonStyle(.borderedProminent)
                    .tint(SignerDesign.blue)
                    .disabled(isBusy || isSelecting)

                Button {
                    local.publish(app, using: store)
                } label: { Label("Publish", systemImage: "paperplane") }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || isSelecting)

                Spacer(minLength: 0)
                Button {
                    batchScope = .single(app.id)
                } label: { Label("Re-sign", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .disabled(isBusy || isSelecting || !local.credentialsReady)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(15)
        .background(SignerDesign.card, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(selectedIDs.contains(app.id)
                              ? SignerDesign.blue.opacity(0.6)
                              : SignerDesign.hairline, lineWidth: 1)
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
    @AppStorage("nextsigner.appearance") private var appearance = SignerAppearance.system.rawValue
    @State private var showingProfiles = false
    @State private var showingActivity = false
    @State private var revealToken = false
    @State private var shareURL: URL?
    @State private var restorePicker = false
    @State private var backupMessage: String?
    @State private var backupError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(SignerAppearance.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("System follows your iPhone appearance. Light and Dark override it for Next Signer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Workspace") {
                    Button { showingProfiles = true } label: {
                        Label("Signing profiles & certificates", systemImage: "person.badge.key.fill")
                    }
                    Button { showingActivity = true } label: {
                        Label("Signing & publishing activity", systemImage: "clock.arrow.circlepath")
                    }
                }

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
            .scrollContentBackground(.hidden)
            .background(SignerDesign.canvas.ignoresSafeArea())
            .onDisappear { store.persistConfiguration() }
            .sheet(isPresented: $showingProfiles) {
                NextSignerLocalProfileView(local: local)
            }
            .sheet(isPresented: $showingActivity) {
                NextSignerActivityView(store: store)
            }
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
