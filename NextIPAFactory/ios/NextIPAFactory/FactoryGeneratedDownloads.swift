import Foundation
import SwiftUI
import ZIPFoundation

// Builds are read from GitHub Actions, not inferred from an agent response.
private struct FactoryCloudRunList: Decodable {
    let workflow_runs: [FactoryCloudRun]
}

struct FactoryCloudRun: Identifiable, Decodable {
    let id: Int
    let display_title: String?
    let status: String
    let conclusion: String?
    let html_url: String
    let head_sha: String?

    var appName: String {
        let title = display_title ?? ""
        if let match = title.range(of: "generate [a-z0-9][a-z0-9-]{1,35}", options: [.regularExpression, .caseInsensitive]) {
            return String(title[match].dropFirst("generate ".count))
        }
        return title.isEmpty ? "Generated app" : title
    }
}

private struct FactoryCloudArtifactList: Decodable {
    let artifacts: [FactoryCloudArtifact]
}

private struct FactoryCloudArtifact: Decodable {
    let id: Int
    let name: String
    let expired: Bool
}

private struct FactoryGitHubArtifactClient {
    let token: String
    let repo: String
    let branch: String

    private func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func url(_ suffix: String) throws -> URL {
        guard !token.isEmpty else {
            throw APIProblem(details: "Save your GitHub compiler token in Settings first.")
        }
        guard let url = URL(string: "https://api.github.com/repos/" + repo + suffix) else {
            throw APIProblem(details: "Invalid GitHub repository address.")
        }
        return url
    }

    private func read(_ suffix: String) async throws -> Data {
        let request = authorizedRequest(try url(suffix))
        return try await NetworkBridge.response(request)
    }

    func runs() async throws -> [FactoryCloudRun] {
        let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? branch
        let data = try await read("/actions/workflows/build-factory-generated-ipa.yml/runs?branch=" + encoded + "&per_page=20")
        return try JSONDecoder().decode(FactoryCloudRunList.self, from: data).workflow_runs
    }

    private func artifact(for runID: Int) async throws -> FactoryCloudArtifact {
        let data = try await read("/actions/runs/" + String(runID) + "/artifacts?per_page=100")
        let list = try JSONDecoder().decode(FactoryCloudArtifactList.self, from: data)
        guard let item = list.artifacts.first(where: { !$0.expired && $0.name.hasPrefix("Generated-") }) else {
            throw APIProblem(details: "No available IPA/TIPA artifact for this build. GitHub artifacts can expire.")
        }
        return item
    }

    func fetchPackage(for run: FactoryCloudRun) async throws -> URL {
        guard run.conclusion == "success" else {
            throw APIProblem(details: "Wait for the GitHub Actions build to succeed before downloading.")
        }

        let item = try await artifact(for: run.id)
        let archiveRequest = authorizedRequest(try url("/actions/artifacts/" + String(item.id) + "/zip"))
        let (temporaryFile, response) = try await URLSession.shared.download(for: archiveRequest)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw APIProblem(details: "GitHub artifact download failed. Check Actions permissions.")
        }

        let manager = FileManager.default
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("FactoryBuilds", isDirectory: true)
            .appendingPathComponent(String(run.id), isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)

        let zipURL = folder.appendingPathComponent("github-artifact.zip")
        if manager.fileExists(atPath: zipURL.path) {
            try manager.removeItem(at: zipURL)
        }
        try manager.moveItem(at: temporaryFile, to: zipURL)
        defer { try? manager.removeItem(at: zipURL) }

        let archive = try Archive(url: zipURL, accessMode: .read)
        let package = archive.first(where: {
            $0.type == .file && $0.path.lowercased().hasSuffix(".tipa")
        }) ?? archive.first(where: {
            $0.type == .file && $0.path.lowercased().hasSuffix(".ipa")
        })

        guard let package else {
            throw APIProblem(details: "Artifact ZIP contains no IPA or TIPA package.")
        }
        guard package.uncompressedSize > 0 && package.uncompressedSize < 500_000_000 else {
            throw APIProblem(details: "Package is empty or exceeds the 500 MB safety limit.")
        }

        // Only extract the selected IPA/TIPA, never arbitrary paths from a ZIP.
        let filename = URL(fileURLWithPath: package.path).lastPathComponent
        let destination = folder.appendingPathComponent(filename)
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try archive.extract(package, to: destination)
        return destination
    }
}

@MainActor
final class FactoryGeneratedDownloads: ObservableObject {
    @Published var builds: [FactoryCloudRun] = []
    @Published var packages: [Int: URL] = [:]
    @Published var message = "Your compiled applications appear here."
    @Published var isRefreshing = false
    @Published var downloadingRunID: Int?

    private func cachedPackage(for runID: Int) -> URL? {
        let manager = FileManager.default
        let directory = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FactoryBuilds", isDirectory: true)
            .appendingPathComponent(String(runID), isDirectory: true)
        guard let items = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        return items.first(where: { $0.pathExtension.lowercased() == "tipa" })
            ?? items.first(where: { $0.pathExtension.lowercased() == "ipa" })
    }

    func refresh(repo: String, branch: String, token: String) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            builds = try await FactoryGitHubArtifactClient(token: token, repo: repo, branch: branch).runs()
            for run in builds where packages[run.id] == nil {
                packages[run.id] = cachedPackage(for: run.id)
            }
            message = builds.isEmpty ? "No generated app builds yet." : "Showing recent cloud compiler runs."
        } catch {
            message = "Could not load generated builds: " + error.localizedDescription
        }
    }

    func download(_ run: FactoryCloudRun, repo: String, branch: String, token: String) async {
        guard downloadingRunID == nil else { return }
        downloadingRunID = run.id
        message = "Downloading and extracting IPA/TIPA from GitHub..."
        defer { downloadingRunID = nil }
        do {
            let package = try await FactoryGitHubArtifactClient(token: token, repo: repo, branch: branch).fetchPackage(for: run)
            packages[run.id] = package
            message = "Ready. Tap Share to TrollStore and select TrollStore in the iOS share sheet."
        } catch {
            message = "Download failed: " + error.localizedDescription
        }
    }
}

struct FactoryDownloadsTab: View {
    @EnvironmentObject private var factory: LocalFactoryState
    @StateObject private var cloud = FactoryGeneratedDownloads()
    @State private var query = ""

    private var filtered: [FactoryCloudRun] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? cloud.builds : cloud.builds.filter {
            $0.appName.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FactoryCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("My generated apps", systemImage: "square.stack.3d.up.fill")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    Task { await cloud.refresh(repo: factory.repo, branch: factory.branch, token: factory.githubToken) }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .disabled(cloud.isRefreshing)
                                .accessibilityLabel("Refresh downloads")
                            }
                            Text("Compiled IPAs and TIPAs, organized by app name. Tap Download, then share to TrollStore.")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Search app name", text: $query)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            .padding(10)
                            .background(Color.indigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    if cloud.isRefreshing {
                        ProgressView("Refreshing cloud builds...")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    if !cloud.message.isEmpty {
                        Text(cloud.message)
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 4)
                    }
                    if filtered.isEmpty && !cloud.isRefreshing {
                        FactoryCard {
                            Label("No matching generated apps yet.", systemImage: "tray")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(filtered.prefix(20))) { run in
                        FactoryCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "app.fill")
                                        .font(.title2)
                                        .foregroundStyle(.indigo)
                                        .frame(width: 42, height: 42)
                                        .background(Color.indigo.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(run.appName).font(.subheadline.bold())
                                            .textSelection(.enabled)
                                        Text("Build " + String(run.id))
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 5)
                                    Label(run.conclusion == "success" ? "Ready" :
                                          run.conclusion == "failure" ? "Failed" :
                                          (run.status == "queued" ? "Queued" : "Building"),
                                          systemImage: run.conclusion == "success" ? "checkmark.circle.fill" :
                                          run.conclusion == "failure" ? "xmark.circle.fill" : "clock")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(run.conclusion == "success" ? Color.green :
                                                         run.conclusion == "failure" ? Color.red : Color.orange)
                                }
                                if let file = cloud.packages[run.id] {
                                    ShareLink(item: file) {
                                        Label("Install via TrollStore / Share", systemImage: "square.and.arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent).tint(.indigo)
                                    Text("Saved on this iPhone as " + file.lastPathComponent)
                                        .font(.caption2).foregroundStyle(.secondary)
                                } else if run.conclusion == "success" {
                                    Button {
                                        Task {
                                            await cloud.download(run, repo: factory.repo, branch: factory.branch, token: factory.githubToken)
                                        }
                                    } label: {
                                        HStack {
                                            if cloud.downloadingRunID == run.id {
                                                ProgressView().tint(.white)
                                            } else {
                                                Image(systemName: "arrow.down.to.line")
                                            }
                                            Text(cloud.downloadingRunID == run.id ? "Downloading..." : "Download IPA / TIPA")
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.borderedProminent).tint(.indigo)
                                    .disabled(cloud.downloadingRunID != nil)
                                } else {
                                    Text(run.conclusion == "failure" ?
                                         "Build failed. Review the compiler logs on GitHub." :
                                         "Waiting for GitHub compilation.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("Downloads")
            .background(Color(red: 0.962, green: 0.967, blue: 0.988))
            .refreshable {
                await cloud.refresh(repo: factory.repo, branch: factory.branch, token: factory.githubToken)
            }
            .task {
                await cloud.refresh(repo: factory.repo, branch: factory.branch, token: factory.githubToken)
            }
        }
    }
}
