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

    /// Multi-file atomic commit using Git blobs, tree, commit, then head ref update.
    func push(project: ForgeProject, owner: String, repo: String, branch: String, message: String,
              sourceBranch: String) async throws -> String {
        let repoPath = "/repos/\(owner)/\(repo)"
        guard !branch.isEmpty, !branch.contains(".."), !branch.hasPrefix("/"), !branch.hasSuffix("/") else {
            throw ForgeError.message("Invalid branch name")
        }
        let parent: String
        let mustCreateBranch: Bool
        do {
            let ref: GitReference = try await decoded(GitReference.self, "\(repoPath)/git/ref/heads/\(branch)")
            parent = ref.object.sha
            mustCreateBranch = false
        } catch {
            // Do not quietly mask permissions/network faults: only create when the branch isn't listed.
            let knownBranches = try await branches(owner: owner, repo: repo)
            if knownBranches.contains(where: { $0.name == branch }) { throw error }
            let origin: GitReference = try await decoded(GitReference.self, "\(repoPath)/git/ref/heads/\(sourceBranch)")
            parent = origin.object.sha
            mustCreateBranch = true
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
        if mustCreateBranch {
            _ = try await fetch("\(repoPath)/git/refs", method: "POST", body: [
                "ref": "refs/heads/\(branch)", "sha": commit.sha
            ])
        } else {
            _ = try await fetch("\(repoPath)/git/refs/heads/\(branch)", method: "PATCH", body: [
                "sha": commit.sha, "force": false
            ])
        }
        return commit.sha
    }

    func latestRun(owner: String, repo: String, sha: String) async throws -> GitHubRun? {
        let response: GitRunList = try await decoded(GitRunList.self,
            "/repos/\(owner)/\(repo)/actions/runs?head_sha=\(sha)&per_page=20")
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

    func releases(owner: String, repo: String) async throws -> [GitHubRelease] {
        try await decoded([GitHubRelease].self, "/repos/\(owner)/\(repo)/releases?per_page=60")
    }
}
