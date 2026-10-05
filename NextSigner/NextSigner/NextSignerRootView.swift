import SwiftUI
import UIKit

private enum NextSignerTab: String, CaseIterable, Identifiable {
    case sign
    case signed
    case library
    case activity
    case profiles
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sign: return "Sign"
        case .signed: return "Signed"
        case .library: return "Library"
        case .activity: return "Activity"
        case .profiles: return "Profiles"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .sign: return "signature"
        case .signed: return "checkmark.seal"
        case .library: return "square.stack.3d.up"
        case .activity: return "waveform.path.ecg"
        case .profiles: return "person.badge.key"
        case .settings: return "gearshape"
        }
    }

    var selectedIcon: String {
        switch self {
        case .sign: return "signature"
        case .signed: return "checkmark.seal.fill"
        case .library: return "square.stack.3d.up.fill"
        case .activity: return "waveform.path.ecg"
        case .profiles: return "person.badge.key.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct NextSignerRootView: View {
    @StateObject private var store = SignerStore()
    @StateObject private var local = LocalSigningController()
    @State private var selection: NextSignerTab = .sign

    var body: some View {
        ZStack {
            NSBackground()

            selectedView
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NSFloatingTabBar(selection: $selection)
                .padding(.horizontal, 12)
                .padding(.top, 7)
                .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selection {
        case .sign:
            NextSignerLocalSignView(store: store, local: local)
        case .signed:
            NextSignerSignedAppsView(store: store, local: local)
        case .library:
            NextSignerLibraryView(store: store)
        case .activity:
            NextSignerActivityView(store: store, local: local)
        case .profiles:
            NextSignerLocalProfileView(local: local)
        case .settings:
            NextSignerLocalSettingsView(store: store, local: local)
        }
    }
}

private struct NSFloatingTabBar: View {
    @Binding var selection: NextSignerTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NextSignerTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selection == tab ? tab.selectedIcon : tab.icon)
                            .font(.system(size: 16, weight: .semibold))

                        if selection == tab {
                            Text(tab.title)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.52))
                    .frame(height: 42)
                    .padding(.horizontal, selection == tab ? 11 : 8)
                    .background {
                        Group {
                            if selection == tab {
                                NSTheme.accentGradient
                            } else {
                                LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(7)
        .frame(maxWidth: .infinity)
        .background(NSTheme.elevated.opacity(0.97), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.20), radius: 8, x: 0, y: 4)
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
            ZStack {
                NSBackground()

                ScrollView {
                    LazyVStack(spacing: 14) {
                        NSPageHeader(
                            eyebrow: "Cloud Library",
                            title: "Published Apps",
                            subtitle: "Browse, install and manage the apps already available through your Next Jailbreak library.",
                            systemImage: "square.stack.3d.up.fill"
                        )

                        if let message = store.libraryMessage {
                            NSGlassCard {
                                Label(message, systemImage: "checkmark.circle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(NSTheme.mint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if let error = store.libraryErrorMessage {
                            NSGlassCard {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(NSTheme.warning)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if store.libraryIsLoading && store.libraryApps.isEmpty {
                            NSGlassCard {
                                HStack(spacing: 12) {
                                    ProgressView()
                                        .tint(NSTheme.cyan)
                                    Text("Refreshing published library…")
                                        .foregroundStyle(NSTheme.textSecondary)
                                    Spacer()
                                }
                            }
                        } else if filteredApps.isEmpty {
                            NSGlassCard {
                                VStack(spacing: 12) {
                                    NSIconBadge(systemImage: "square.stack.3d.up.slash", size: 52, tint: NSTheme.violet)
                                    Text(searchText.isEmpty ? "No published apps yet" : "No matching apps")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(searchText.isEmpty ? "Published apps will appear here automatically." : "Try a different app name or bundle identifier.")
                                        .font(.caption)
                                        .foregroundStyle(NSTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            }
                        } else {
                            HStack {
                                Text("\(filteredApps.count) APP\(filteredApps.count == 1 ? "" : "S")")
                                    .font(.caption2.weight(.bold))
                                    .tracking(1.1)
                                    .foregroundStyle(NSTheme.textSecondary)
                                Spacer()
                            }
                            .padding(.top, 2)

                            ForEach(filteredApps) { app in
                                publishedAppCard(app)
                            }
                        }
                    }
                    .nsPagePadding()
                    .padding(.bottom, 16)
                }
                .refreshable { await store.refreshLibrary() }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search apps or bundle IDs")
            .task {
                if store.libraryApps.isEmpty { await store.refreshLibrary() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await store.refreshLibrary() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(NSTheme.cyan)
                    .disabled(store.libraryIsLoading)
                }
            }
            .confirmationDialog(
                pendingOperation?.action == .deleteApp ? "Delete app and stored files?" : "Clean old versions?",
                isPresented: Binding(
                    get: { pendingOperation != nil },
                    set: { if !$0 { pendingOperation = nil } }
                ),
                titleVisibility: .visible,
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

    private func publishedAppCard(_ app: PublishedApp) -> some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    libraryIcon(app)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Text("v\(app.version)  •  build \(app.build)")
                            .font(.caption)
                            .foregroundStyle(NSTheme.textSecondary)

                        Text(app.bundleId)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if store.libraryManagingAppID == app.id {
                        ProgressView()
                            .tint(NSTheme.cyan)
                    } else if app.available ?? false {
                        NSStatusChip(text: "Ready", systemImage: "checkmark.circle.fill", tint: NSTheme.mint)
                    }
                }

                HStack(spacing: 8) {
                    if let storage = app.storage {
                        NSStatusChip(text: storage, systemImage: "externaldrive.fill", tint: NSTheme.violet)
                    }
                    if let bytes = app.sizeBytes {
                        NSStatusChip(
                            text: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file),
                            systemImage: "shippingbox.fill",
                            tint: NSTheme.blue
                        )
                    }
                }

                HStack(spacing: 9) {
                    if app.available ?? false, app.manifest != nil {
                        Button {
                            install(app)
                        } label: {
                            Label("Install", systemImage: "arrow.down.app.fill")
                        }
                        .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.mint))
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
                        Label("Manage", systemImage: "ellipsis")
                    }
                    .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.blue))
                    .disabled(store.libraryManagingAppID != nil)

                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func libraryIcon(_ app: PublishedApp) -> some View {
        if let url = absoluteURL(app.icon) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "app.fill").resizable().scaledToFit().padding(13).foregroundStyle(.white)
                case .empty:
                    ProgressView().tint(NSTheme.cyan)
                @unknown default:
                    Image(systemName: "app.fill").resizable().scaledToFit().padding(13).foregroundStyle(.white)
                }
            }
            .frame(width: 62, height: 62)
            .background(NSTheme.softGradient)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
        } else {
            NSIconBadge(systemImage: "app.fill", size: 62, tint: NSTheme.violet)
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
    @ObservedObject var local: LocalSigningController

    var body: some View {
        NavigationStack {
            ZStack {
                NSBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        NSPageHeader(
                            eyebrow: "System",
                            title: "Activity",
                            subtitle: "A clean view of signing readiness, local output and the latest publishing operation.",
                            systemImage: "waveform.path.ecg"
                        )

                        statusOverview

                        if let job = store.activeJob {
                            currentJobCard(job)
                        } else {
                            NSGlassCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    NSSectionHeader("Publishing queue", subtitle: "No cloud job is active", systemImage: "cloud")
                                    Text("Local signing does not create a cloud job. Publishing activity appears here only after you explicitly publish an app.")
                                        .font(.footnote)
                                        .foregroundStyle(NSTheme.textSecondary)
                                }
                            }
                        }

                        NSGlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                NSSectionHeader("Web library", subtitle: "Open the public installer page", systemImage: "safari")
                                Link(destination: URL(string: "https://nextjailbreak.com/install/")!) {
                                    Label("Open Next Jailbreak Library", systemImage: "arrow.up.right")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(NSSecondaryButtonStyle(tint: NSTheme.cyan))
                            }
                        }
                    }
                    .nsPagePadding()
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                local.refreshCredentials()
                local.refreshSignedApps()
            }
        }
    }

    private var statusOverview: some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                NSSectionHeader("Readiness", subtitle: "Current Next Signer state", systemImage: "gauge.with.dots.needle.67percent")

                HStack(spacing: 9) {
                    NSStatusChip(
                        text: local.credentialsReady ? "Signer ready" : "Profile incomplete",
                        systemImage: local.credentialsReady ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
                        tint: local.credentialsReady ? NSTheme.mint : NSTheme.warning
                    )

                    NSStatusChip(
                        text: "\(local.signedApps.count) signed",
                        systemImage: "checkmark.seal.fill",
                        tint: NSTheme.blue
                    )
                }

                NSStatusChip(
                    text: store.tokenIsStored ? "Publishing connected" : "Publishing PAT missing",
                    systemImage: store.tokenIsStored ? "cloud.fill" : "cloud.slash.fill",
                    tint: store.tokenIsStored ? NSTheme.cyan : NSTheme.warning
                )
            }
        }
    }

    private func currentJobCard(_ job: SigningJob) -> some View {
        NSGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    NSSectionHeader("Latest publishing job", subtitle: job.sourceName, systemImage: icon(for: job.stage))
                    Spacer()
                    NSStatusChip(
                        text: job.stage.rawValue,
                        systemImage: icon(for: job.stage),
                        tint: job.stage == .failed ? NSTheme.danger : NSTheme.cyan
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.requestedAppName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(job.requestedBundleID)
                        .font(.caption.monospaced())
                        .foregroundStyle(NSTheme.textSecondary)
                    Text(job.detail)
                        .font(.footnote)
                        .foregroundStyle(Color.white.opacity(0.76))
                        .padding(.top, 2)
                }
            }
        }
    }

    private func icon(for stage: SigningJob.Stage) -> String {
        switch stage {
        case .preparing: return "gearshape.2.fill"
        case .uploading: return "arrow.up.circle.fill"
        case .queued: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }
}
