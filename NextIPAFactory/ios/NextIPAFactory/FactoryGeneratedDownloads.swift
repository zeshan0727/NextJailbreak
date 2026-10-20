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

    func refresh(repo: String, branch: String, token: String) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            builds = try await FactoryGitHubArtifactClient(token: token, repo: repo, branch: branch).runs()
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

struct FactoryGeneratedBuildsSection: View {
    @EnvironmentObject private var factory: LocalFactoryState
    @StateObject private var cloud = FactoryGeneratedDownloads()

    var body: some View {
        FactoryCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Generated apps", systemImage: "square.stack.3d.up.fill").font(.headline)
                    Spacer()
                    Button {
                        Task {
                            await cloud.refresh(repo: factory.repo, branch: factory.branch, token: factory.githubToken)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(cloud.isRefreshing)
                    .accessibilityLabel("Refresh generated app builds")
                }

                Text("Download completed iPhone builds here. No GitHub website is needed.")
                    .font(.caption).foregroundStyle(.secondary)

                if cloud.isRefreshing {
                    ProgressView("Loading cloud builds...")
                }

                ForEach(Array(cloud.builds.prefix(12))) { run in
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(run.display_title ?? "Generated app build").font(.subheadline.bold()).lineLimit(3)
                        HStack(spacing: 6) {
                            Image(systemName: run.conclusion == "success" ? "checkmark.circle.fill" :
                                  run.conclusion == "failure" ? "xmark.circle.fill" : "clock")
                                .foregroundStyle(run.conclusion == "success" ? Color.green :
                                                 run.conclusion == "failure" ? Color.red : Color.orange)
                            Text(run.conclusion ?? run.status).font(.caption)
                            Spacer()
                            Text("#" + String(run.id)).font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        if let fileURL = cloud.packages[run.id] {
                            ShareLink(item: fileURL) {
                                Label("Share to TrollStore", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(.indigo)
                            Text("Choose TrollStore from the share sheet to confirm installation.")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else if run.conclusion == "success" {
                            Button {
                                Task {
                                    await cloud.download(run, repo: factory.repo, branch: factory.branch, token: factory.githubToken)
                                }
                            } label: {
                                Label(cloud.downloadingRunID == run.id ? "Downloading..." : "Download IPA / TIPA",
                                      systemImage: "arrow.down.to.line")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent).tint(.indigo)
                            .disabled(cloud.downloadingRunID != nil)
                        } else {
                            Text("Download available after a successful build.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                Text(cloud.message)
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .task {
            await cloud.refresh(repo: factory.repo, branch: factory.branch, token: factory.githubToken)
        }
    }
}
