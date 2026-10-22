import SwiftUI
import UIKit

struct DownloadsView: View {
    @EnvironmentObject private var state: AppState
    @State private var shareURL: URL?
    @State private var showSharing = false
    @State private var showFilesHelp = false

    private var repository: String {
        let owner = state.lastOwner.isEmpty ? state.preferences.githubUsername : state.lastOwner
        let repo = state.lastRepo.isEmpty ? state.chosenRepo : state.lastRepo
        return "\(owner)/\(repo)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScreenHeading(title: "Downloads", subtitle: "Release assets from \(repository).")
                    Button {
                        Task { await state.refreshReleases() }
                    } label: { Label("Refresh releases", systemImage: "arrow.clockwise") }
                    if state.downloads.busy {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Downloading \(state.downloads.currentName)")
                            ProgressView(value: state.downloads.progress)
                            Text("\(Int(state.downloads.progress * 100))%")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let error = state.downloads.error {
                        Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled)
                    }
                    if let file = state.downloads.completedFile {
                        Label("Verified IPA: \(file.lastPathComponent)", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Button("Share IPA with TrollStore / Files") {
                            shareURL = file; showSharing = true
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Section("Available GitHub Releases") {
                    if state.releases.isEmpty { Text("No releases found yet").foregroundStyle(.secondary) }
                    ForEach(state.releases) { release in
                        ForEach(release.assets.filter { $0.name.lowercased().hasSuffix(".ipa") }) { asset in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(asset.name).font(.subheadline.bold())
                                    Text("\(release.tag_name) • \(asset.size.forgeSize)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task {
                                        let owner = state.lastOwner.isEmpty ? state.preferences.githubUsername : state.lastOwner
                                        let repo = state.lastRepo.isEmpty ? state.chosenRepo : state.lastRepo
                                        await state.downloads.start(asset: asset, releaseTag: release.tag_name, token: Keychain.read("github"), owner: owner, repo: repo)
                                    }
                                } label: { Label("Download IPA", systemImage: "arrow.down.circle.fill") }
                                    .disabled(state.downloads.busy)
                                if let url = URL(string: asset.browser_download_url) {
                                    Link("GitHub", destination: url).font(.caption)
                                }
                            }
                            .buttonStyle(.borderless)
                            .padding(.vertical, 5)
                        }
                    }
                }
                Section("Saved on this iPhone") {
                    if state.downloads.files.isEmpty { Text("No saved IPA files").foregroundStyle(.secondary) }
                    ForEach(state.downloads.files) { file in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "doc.zipper")
                                VStack(alignment: .leading) {
                                    Text(file.name).font(.headline)
                                    Text(file.size.forgeSize).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 16) {
                                Button("Share") { shareURL = file.url; showSharing = true }
                                Button("Files") { showFilesHelp = true }
                                Button("Delete", role: .destructive) {
                                    do { try state.downloads.delete(file) }
                                    catch { state.notice = error.localizedDescription }
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }.padding(.vertical, 5)
                    }
                }
                Section {
                    Text("AppForge downloads IPA assets and verifies Payload/*.app before saving. Use TrollStore or another compatible signing method to install.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Downloads").navigationBarTitleDisplayMode(.inline)
            .refreshable { await state.refreshReleases() }
            .task { await state.refreshReleases() }
            .sheet(isPresented: $showSharing) {
                if let url = shareURL { ShareSheet(items: [url]) }
            }
            .alert("Open in Files", isPresented: $showFilesHelp) {
                Button("Open Files") {
                    if let url = URL(string: "shareddocuments://") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("In Files, choose Browse → On My iPhone → AppForge. Files sharing is enabled for this app.")
            }
        }
    }
}
