import Foundation

private struct GitReference: Decodable {
    struct Object: Decodable { let sha: String }
    let object: Object
}
private struct GitCommit: Decodable {
    struct Tree: Decodable { let sha: String }
    let sha: String
    let tree: Tree
}
private struct GitSHA: Decodable { let sha: String }
private struct GitRunList: Decodable { let workflow_runs: [GitHubRun] }
private struct GitJobList: Decodable { let jobs: [GitHubJob] }

/// Direct GitHub REST client. No intermediary server and no Git credentials in the repository.
struct GitHubClient {
    let token: String
    private let root = "https://api.github.com"

    private func resource(_ path: String) throws -> URL {
        guard let url = URL(string: root + path) else { throw ForgeError.message("Invalid GitHub API path") }
        return url
    }

    private func fetch(_ path: String, method: String = "GET", body: Any? = nil,
                       accept: String = "application/vnd.github+json") async throws -> Data {
        guard !token.isEmpty else { throw ForgeError.message("Set GitHub token in Settings") }
        var request = URLRequest(url: try resource(path))
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch let error as URLError where error.code == .notConnectedToInternet {
            throw ForgeError.message("Device is offline. GitHub needs a network connection")
        }
        guard let http = response as? HTTPURLResponse else { throw ForgeError.message("Invalid GitHub response") }
        switch http.statusCode {
        case 200...299: return data
        case 401: throw ForgeError.message("GitHub token is invalid or expired (401)")
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw ForgeError.message("GitHub API rate limit reached (403)")
            }
            throw ForgeError.message("GitHub rejected permission (403). Check Contents, Actions and Workflows permissions")
        case 404: throw ForgeError.message("GitHub resource not found (404). Check repo name, branch, or token access")
        case 409: throw ForgeError.message("GitHub reported a conflict (409). Try again on the latest branch")
        case 422: throw ForgeError.message("GitHub rejected request (422): \(String(decoding: data.prefix(250), as: UTF8.self))")
        case 429: throw ForgeError.message("GitHub API rate limited this operation (429)")
        default: throw ForgeError.message("GitHub HTTP \(http.statusCode): \(String(decoding: data.prefix(350), as: UTF8.self))")
        }
    }

    private func decoded<T: Decodable>(_ type: T.Type, _ path: String, method: String = "GET", body: Any? = nil) async throws -> T {
        let data = try await fetch(path, method: method, body: body)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func testToken() async throws -> String {
        struct User: Decodable { let login: String }
        return try await decoded(User.self, "/user").login
    }

    func repositories() async throws -> [GitHubRepo] {
        try await decoded([GitHubRepo].self, "/user/repos?per_page=100&sort=updated&affiliation=owner")
    }

    func branches(owner: String, repo: String) async throws -> [GitHubBranch] {
        try await decoded([GitHubBranch].self, "/repos/\(owner)/\(repo)/branches?per_page=100")
    }

    func createRepo(name: String, isPrivate: Bool) async throws -> GitHubRepo {
        try await decoded(GitHubRepo.self, "/user/repos", method: "POST", body: [
            "name": name, "private": isPrivate, "auto_init": true,
            "description": "Created using AppForge"
        ])
    }

    /// Create a new isolated branch for each app. A rebuild can update ONLY the
    /// branch that AppForge created, and only at the exact head SHA it last pushed.
    /// Never write to main/master or an arbitrary existing branch.
    func push(project: ForgeProject, owner: String, repo: String, branch: String, message: String,
              sourceBranch: String, expectedHeadSHA: String?) async throws -> String {
        let repoPath = "/repos/\(owner)/\(repo)"
        let allowed = #"^appforge/[a-z0-9][a-z0-9-]{0,43}-[a-f0-9]{12}$"#
        guard branch.range(of: allowed, options: .regularExpression) != nil,
              branch != sourceBranch,
              sourceBranch != branch else {
            throw ForgeError.message("Unsafe branch rejected. AppForge creates only unique appforge/<app>-<id> branches.")
        }

        let isRepair = expectedHeadSHA != nil
        let parent: String
        if let expectedHeadSHA {
            // Abort rather than overwrite changes pushed from another device/user.
            let head: GitReference = try await decoded(GitReference.self,
                                                       "\(repoPath)/git/ref/heads/\(branch)")
            guard head.object.sha == expectedHeadSHA else {
                throw ForgeError.message("This app's branch changed on GitHub. Push blocked to avoid overwriting another commit.")
            }
            parent = head.object.sha
        } else {
            // A new project MUST fork from the repo's actual default branch.
            // Never reuse an existing branch, even if a collision occurs.
            let origin: GitReference = try await decoded(GitReference.self,
                                                         "\(repoPath)/git/ref/heads/\(sourceBranch)")
            parent = origin.object.sha
        }

        let prior: GitCommit = try await decoded(GitCommit.self, "\(repoPath)/git/commits/\(parent)")
        var entries = [[String: Any]]()
        for file in project.files {
            let blob: GitSHA = try await decoded(GitSHA.self, "\(repoPath)/git/blobs", method: "POST", body: [
                "content": file.content, "encoding": "utf-8"
            ])
            entries.append(["path": file.path, "mode": "100644", "type": "blob", "sha": blob.sha])
        }
        let tree: GitSHA = try await decoded(GitSHA.self, "\(repoPath)/git/trees", method: "POST", body: [
            "base_tree": prior.tree.sha, "tree": entries
        ])
        let commit: GitSHA = try await decoded(GitSHA.self, "\(repoPath)/git/commits", method: "POST", body: [
            "message": message.isEmpty ? "Build app from AppForge" : message,
            "tree": tree.sha, "parents": [parent]
        ])
        if isRepair {
            _ = try await fetch("\(repoPath)/git/refs/heads/\(branch)", method: "PATCH", body: [
                "sha": commit.sha, "force": false
            ])
        } else {
            // GitHub rejects this POST if the branch already exists (HTTP 422).
            // Unlike the old implementation, we NEVER fall back to updating it.
            _ = try await fetch("\(repoPath)/git/refs", method: "POST", body: [
                "ref": "refs/heads/\(branch)", "sha": commit.sha
            ])
        }
        return commit.sha
    }

    func defaultBranch(owner: String, repo: String) async throws -> String {
        let result: GitHubRepo = try await decoded(GitHubRepo.self, "/repos/\(owner)/\(repo)")
        return result.default_branch
    }

    func latestRun(owner: String, repo: String, sha: String) async throws -> GitHubRun? {
        let response: GitRunList = try await decoded(GitRunList.self,
            "/repos/\(owner)/\(repo)/actions/workflows/build.yml/runs?head_sha=\(sha)&per_page=100")
        return response.workflow_runs.filter { $0.head_sha == sha && $0.path == ".github/workflows/build.yml" }
            .sorted { $0.created_at > $1.created_at }.first
    }

    func jobs(owner: String, repo: String, run: Int) async throws -> [GitHubJob] {
        let response: GitJobList = try await decoded(GitJobList.self,
            "/repos/\(owner)/\(repo)/actions/runs/\(run)/jobs?per_page=100")
        return response.jobs
    }

    /// This job-specific logs endpoint redirects to plaintext (not the run-wide ZIP archive).
    func jobLog(owner: String, repo: String, job: Int) async throws -> String {
        let data = try await fetch("/repos/\(owner)/\(repo)/actions/jobs/\(job)/logs", accept: "application/vnd.github+json")
        guard let content = String(data: data, encoding: .utf8) else {
            throw ForgeError.message("Could not decode job log")
        }
        return String(content.suffix(30_000))
    }

    func dispatch(owner: String, repo: String, branch: String) async throws {
        _ = try await fetch("/repos/\(owner)/\(repo)/actions/workflows/build.yml/dispatches",
                            method: "POST", body: ["ref": branch])
    }

    /// GitHub orders releases by the tag commit date, not necessarily publication date.
    /// Fetch multiple pages, then sort by actual publication time so fresh IPAs appear first.
    func releases(owner: String, repo: String) async throws -> [GitHubRelease] {
        var found: [GitHubRelease] = []
        var seen = Set<Int>()
        for page in 1...3 {
            let part = try await decoded([GitHubRelease].self,
                "/repos/\(owner)/\(repo)/releases?per_page=100&page=\(page)")
            for release in part where seen.insert(release.id).inserted {
                found.append(release)
            }
            if part.count < 100 { break }
        }
        return found.filter { !$0.ipaAssets.isEmpty }
            .sorted { $0.sortDate > $1.sortDate }
    }
    private struct GitContentFile: Decodable {
        let content: String?
        let encoding: String?
        let type: String
    }

    /// Read one file from an immutable successful build commit, not the mutable branch head.
    private func snapshotText(owner: String, repo: String, path: String, sha: String) async throws -> String {
        guard sha.count == 40, sha.allSatisfy({ $0.isHexDigit }),
              !path.contains(".."), !path.hasPrefix("/") else {
            throw ForgeError.message("Unsafe GitHub snapshot path or commit identifier.")
        }
        let response: GitContentFile = try await decoded(GitContentFile.self,
            "/repos/\(owner)/\(repo)/contents/\(path)?ref=\(sha)")
        guard response.type == "file", response.encoding == "base64",
              let encoded = response.content,
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              data.count <= 1_500_000,
              let source = String(data: data, encoding: .utf8) else {
            throw ForgeError.message("Cannot read \(path) from the selected successful commit.")
        }
        return source
    }

    /// Lists recent successfully compiled AppForge apps, even when a branch's
    /// newest HEAD later failed. A row points to the original passing commit.
    func successfulAppBuilds(owner: String, repo: String) async throws -> [GitHubRun] {
        var runs: [GitHubRun] = []
        var seen = Set<String>()
        for page in 1...4 {
            let response: GitRunList = try await decoded(GitRunList.self,
                "/repos/\(owner)/\(repo)/actions/workflows/build.yml/runs?status=success&per_page=100&page=\(page)")
            for run in response.workflow_runs {
                guard run.conclusion == "success", run.status == "completed",
                      run.head_sha.count == 40,
                      run.path == ".github/workflows/build.yml",
                      let branch = run.head_branch, branch.hasPrefix("appforge/"),
                      seen.insert(branch).inserted else { continue }
                runs.append(run)
            }
            if response.workflow_runs.count < 100 { break }
        }
        return runs.sorted { $0.created_at > $1.created_at }
    }

    /// Restore only app source listed by the successful project's project.yml.
    /// Other applications in the shared repository are never imported.
    func successfulProject(owner: String, repo: String, sha: String, minimumIOS: String) async throws -> ForgeProject {
        let config = try await snapshotText(owner: owner, repo: repo, path: "project.yml", sha: sha)
        let plist = try await snapshotText(owner: owner, repo: repo, path: "Info.plist", sha: sha)
        guard let nameLine = config.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("name:")
        }), let bundleLine = config.split(separator: "\n").first(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("PRODUCT_BUNDLE_IDENTIFIER:")
        }) else {
            throw ForgeError.message("Build has no recognizable AppForge XcodeGen metadata.")
        }
        let name = String(nameLine.split(separator: ":", maxSplits: 1).last ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        let bundle = String(bundleLine.split(separator: ":", maxSplits: 1).last ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        let sourceNames = config.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- Sources/") && $0.hasSuffix(".swift") }
            .map { String($0.dropFirst(2)) }
            .filter { $0 != "Sources/AppEntry.swift" }
        let unique = Array(Set(sourceNames)).sorted()
        guard !name.isEmpty, !bundle.isEmpty, !unique.isEmpty, unique.count <= 30 else {
            throw ForgeError.message("Only AppForge-created Swift source builds with up to 30 files can be restored.")
        }
        var swift: [ForgeFile] = []
        for name in unique {
            guard !name.contains("..") && name.hasPrefix("Sources/") else {
                throw ForgeError.message("Unsafe source file in successful build.")
            }
            let contents = try await snapshotText(owner: owner, repo: repo, path: name, sha: sha)
            swift.append(ForgeFile(path: name, content: contents))
        }
        var rebuilt = try ProjectFactory.scaffold(
            ForgeProject(appName: name, bundleId: bundle, files: swift),
            minIOS: minimumIOS
        )
        // Preserve the exact old privacy declarations and custom plist metadata.
        if let original = rebuilt.files.firstIndex(where: { $0.path == "Info.plist" }) {
            rebuilt.files[original].content = plist
        }
        return rebuilt
    }


}
