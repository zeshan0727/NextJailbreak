import SwiftUI
import UIKit

/// Latest app build is pinned separately from older releases, sorted newest first.
struct DownloadsView: View {
    @EnvironmentObject private var state: AppState
    @State private var shareURL: URL?
    @State private var showingShare = false
    @State private var showingFiles = false

    private var pinned: GitHubRelease? { state.currentBuildRelease ?? state.latestProjectRelease }
    private var otherReleases: [GitHubRelease] { state.releases.filter { $0.id != pinned?.id } }

    var body: some View {
        NavigationStack {
            List {
                Section("GitHub repository") {
                    ScreenHeading(title: "Downloads", subtitle: "Find and download your generated app's IPA.")
                    TextField("Owner", text: $state.downloadsOwner)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Repository", text: $state.downloadsRepo)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {
                        Button { Task { await state.refreshReleases() } } label: {
                            Label("Refresh builds", systemImage: "arrow.clockwise")
                        }.disabled(state.downloadsRefreshing)
                        Spacer()
                        if state.downloadsRefreshing { ProgressView() }
                    }
                    if !state.lastOwner.isEmpty &&
                        (state.downloadsOwner != state.lastOwner || state.downloadsRepo != state.lastRepo) {
                        Button("Use latest build's repository") {
                            state.selectLastBuildDownloads()
                            Task { await state.refreshReleases() }
                        }
                    }
                    if let checked = state.downloadsCheckedAt {
                        Text("Checked: \(checked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = state.downloadsError {
                        Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let url = URL(string: "https://github.com/\(state.downloadsOwner)/\(state.downloadsRepo)/releases") {
                        Link("See all releases on GitHub", destination: url).font(.footnote)
                    }
                }
                Section("Latest generated IPA") {
                    if let app = state.project?.appName {
                        LabeledContent("App", value: app)
                    }
                    if !state.lastCommitSHA.isEmpty {
                        LabeledContent("Build commit", value: String(state.lastCommitSHA.prefix(12)))
                    }
                    if let release = pinned {
                        if state.currentBuildRelease != nil {
                            Label("IPA from your most recent build", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Showing the latest available IPA for this app. The most recent commit may not have a published release yet.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        ForEach(release.ipaAssets) { asset in
                            IPAReleaseRow(release: release, asset: asset)
                        }
                    } else if state.downloadsRefreshing {
                        ProgressView("Finding your app…")
                    } else if state.releases.isEmpty {
                        Text("No IPA assets found in this repository. Confirm the GitHub build succeeded and the release publishing step completed.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No release matches the selected app. Check the repository above; other IPA releases are below.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Download progress") {
                    if state.downloads.busy {
                        Text("Downloading \(state.downloads.currentName)")
                        ProgressView(value: state.downloads.progress)
                    }
                    if let error = state.downloads.error {
                        Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if let url = state.downloads.completedFile {
                        Label("Saved verified IPA", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Share with TrollStore / Files") {
                            shareURL = url; showingShare = true
                        }
                    }
                }
                Section("Other available IPA releases") {
                    if otherReleases.isEmpty {
                        Text("No other IPA releases found.").foregroundStyle(.secondary)
                    }
                    ForEach(otherReleases) { release in
                        ForEach(release.ipaAssets) { asset in
                            IPAReleaseRow(release: release, asset: asset)
                        }
                    }
                }
                Section("Saved on this iPhone") {
                    if state.downloads.files.isEmpty {
                        Text("No saved IPA files.").foregroundStyle(.secondary)
                    }
                    ForEach(state.downloads.files) { file in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(file.name).font(.headline)
                            Text(file.size.forgeSize).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 20) {
                                Button("Share") { shareURL = file.url; showingShare = true }
                                Button("Files") { showingFiles = true }
                                Button("Delete", role: .destructive) {
                                    do { try state.downloads.delete(file) }
                                    catch { state.notice = error.localizedDescription }
                                }
                            }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await state.refreshReleases() }
            .task { await state.refreshReleases() }
            .onChange(of: state.selectedTab) { tab in
                if tab == .more && state.moreSection == .downloads {
                    Task { await state.refreshReleases() }
                }
            }
            .sheet(isPresented: $showingShare) {
                if let url = shareURL { ShareSheet(items: [url]) }
            }
            .alert("Open in Files", isPresented: $showingFiles) {
                Button("Open Files") {
                    if let url = URL(string: "shareddocuments://") { UIApplication.shared.open(url) }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Files → Browse → On My iPhone → AppForge")
            }
        }
    }
}

private struct IPAReleaseRow: View {
    @EnvironmentObject private var state: AppState
    let release: GitHubRelease
    let asset: GitHubAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(asset.name).font(.headline)
            Text("\(release.tag_name) • \(asset.size.forgeSize)")
                .font(.caption).foregroundStyle(.secondary)
            if let published = release.published_at {
                Text("Published \(published.prefix(10))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                Button {
                    Task {
                        await state.downloads.start(asset: asset,
                            releaseTag: release.tag_name,
                            token: Keychain.read("github"),
                            owner: state.downloadsOwner,
                            repo: state.downloadsRepo)
                    }
                } label: {
                    Label("Download IPA", systemImage: "arrow.down.circle.fill")
                }
                .disabled(state.downloads.busy)
                if let url = URL(string: asset.browser_download_url) {
                    Link("GitHub", destination: url)
                }
            }.buttonStyle(.borderless)
        }.padding(.vertical, 6)
    }
}
