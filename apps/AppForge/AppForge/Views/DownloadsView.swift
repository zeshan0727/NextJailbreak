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
                        ProgressView(value: state.downloads.progress) {
                            Text("Downloading…")
                        }
                    }
                    if let error = state.downloads.error { Text(error).foregroundStyle(.red).font(.caption) }
                }
                Section("Available GitHub Releases") {
                    if state.releases.isEmpty { Text("No releases found yet").foregroundStyle(.secondary) }
                    ForEach(state.releases) { release in
                        ForEach(release.assets.filter { ["ipa", "tipa"].contains($0.name.split(separator: ".").last.map(String.init)?.lowercased() ?? "") }) { asset in
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
                                        await state.downloads.start(asset: asset, token: Keychain.read("github"), owner: owner, repo: repo)
                                    }
                                } label: { Image(systemName: "arrow.down.circle.fill").font(.title2) }
                                    .disabled(state.downloads.busy)
                            }.padding(.vertical, 5)
                        }
                    }
                }
                Section("Saved on this iPhone") {
                    if state.downloads.files.isEmpty { Text("No local IPA/TIPA files").foregroundStyle(.secondary) }
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
                                if file.url.pathExtension == "ipa" {
                                    Button("Save as .tipa") {
                                        do { try state.downloads.saveAsTIPA(file) }
                                        catch { state.notice = error.localizedDescription }
                                    }
                                }
                                Button("Files") { showFilesHelp = true }
                                Button("Delete", role: .destructive) {
                                    do { try state.downloads.delete(file) }
                                    catch { state.notice = error.localizedDescription }
                                }
                            }.font(.caption)
                        }.padding(.vertical, 5)
                    }
                }
                Section {
                    Text("These are unsigned archives. Renaming .ipa to .tipa does not sign the app. Device installation requires a compatible signer or supported TrollStore environment.")
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
