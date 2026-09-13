import Foundation

struct AdHocInstallResult: Equatable {
    let manifestURL: URL
    let ipaURL: URL?
}

private struct AdHocInstallStatus: Decodable {
    let requestID: String
    let state: String
    let stage: String
    let message: String
    let runURL: String?
    let updatedAt: String?
    let manifestURL: String?
    let ipaURL: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
        case stage
        case message
        case runURL = "run_url"
        case updatedAt = "updated_at"
        case manifestURL = "manifest_url"
        case ipaURL = "ipa_url"
    }
}

actor AdHocInstallService {
    private struct Release: Decodable {
        let id: Int
        let tagName: String
        let uploadURL: String

        enum CodingKeys: String, CodingKey {
            case id
            case tagName = "tag_name"
            case uploadURL = "upload_url"
        }
    }

    private struct Asset: Decodable {
        let id: Int
        let name: String
    }

    private let token: String
    private let configuration: GitHubConfiguration
    private let session: URLSession
    private let apiVersion = "2026-03-10"
    private let stagingTag = "nextsigner-inbox"

    init(token: String, configuration: GitHubConfiguration, session: URLSession = .shared) {
        self.token = token
        self.configuration = configuration
        self.session = session
    }

    func prepareInstall(
        ipaURL: URL,
        appName: String,
        bundleID: String,
        version: String,
        build: String,
        progress: @Sendable (String) async -> Void
    ) async throws -> AdHocInstallResult {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }
        guard FileManager.default.fileExists(atPath: ipaURL.path) else {
            throw NSError(
                domain: "NextSigner.AdHocInstall",
                code: 5201,
                userInfo: [NSLocalizedDescriptionKey: "The signed IPA is no longer available on this iPhone."]
            )
        }

        let requestID = UUID().uuidString.lowercased()
        let release = try await ensureStagingRelease()
        let stamp = Int(Date().timeIntervalSince1970)
        let assetName = makeAssetName(original: ipaURL.lastPathComponent, stamp: stamp)

        await progress("Temporarily uploading the signed IPA for Apple installation…")
        try await uploadAsset(fileURL: ipaURL, name: assetName, release: release)

        await progress("Preparing Apple OTA installation manifest…")
        try await dispatchInstallOnly(
            requestID: requestID,
            assetName: assetName,
            appName: appName,
            bundleID: bundleID,
            version: version,
            build: build
        )

        let status = try await waitForInstallResult(requestID: requestID, releaseID: release.id) { message in
            await progress(message)
        }

        guard let rawManifest = status.manifestURL,
              let manifestURL = URL(string: rawManifest) else {
            throw NSError(
                domain: "NextSigner.AdHocInstall",
                code: 5202,
                userInfo: [NSLocalizedDescriptionKey: "The installation backend finished without returning an OTA manifest URL."]
            )
        }

        return AdHocInstallResult(
            manifestURL: manifestURL,
            ipaURL: status.ipaURL.flatMap(URL.init(string:))
        )
    }

    private func waitForInstallResult(
        requestID: String,
        releaseID: Int,
        progress: @Sendable (String) async -> Void
    ) async throws -> AdHocInstallStatus {
        let deadline = Date().addingTimeInterval(12 * 60)
        var lastSignature = ""

        while Date() < deadline {
            if let status = try await newestStatus(requestID: requestID, releaseID: releaseID) {
                let signature = "\(status.state)|\(status.stage)|\(status.message)|\(status.updatedAt ?? "")"
                if signature != lastSignature {
                    lastSignature = signature
                    await progress(status.message)
                }

                switch status.state.lowercased() {
                case "success":
                    return status
                case "failed", "failure":
                    let suffix = status.runURL.map { " Run: \($0)" } ?? ""
                    throw NSError(
                        domain: "NextSigner.AdHocInstall",
                        code: 5203,
                        userInfo: [NSLocalizedDescriptionKey: "\(status.stage): \(status.message)\(suffix)"]
                    )
                default:
                    break
                }
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        throw NSError(
            domain: "NextSigner.AdHocInstall",
            code: 5204,
            userInfo: [NSLocalizedDescriptionKey: "Timed out while preparing the Apple OTA installation."]
        )
    }

    private func newestStatus(requestID: String, releaseID: Int) async throws -> AdHocInstallStatus? {
        let prefix = "status-install-\(requestID)-"
        var candidates: [Asset] = []

        for page in 1...6 {
            let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/\(releaseID)/assets?per_page=100&page=\(page)&_ns=\(UUID().uuidString)")
            var req = request(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await session.data(for: req)
            try validate(response: response, data: data)
            let assets = try JSONDecoder().decode([Asset].self, from: data)
            candidates.append(contentsOf: assets.filter { $0.name.hasPrefix(prefix) })
            if assets.count < 100 { break }
        }

        guard let newest = candidates.max(by: { $0.id < $1.id }) else { return nil }
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/assets/\(newest.id)?_ns=\(UUID().uuidString)")
        var req = request(url: url)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(AdHocInstallStatus.self, from: data)
    }

    private func dispatchInstallOnly(
        requestID: String,
        assetName: String,
        appName: String,
        bundleID: String,
        version: String,
        build: String
    ) async throws {
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/dispatches")
        let payload: [String: Any] = [
            "event_type": "nextsigner_install_only",
            "client_payload": [
                "request_id": requestID,
                "staging_asset": assetName,
                "app_name": appName,
                "bundle_id": bundleID,
                "version": version,
                "build": build
            ]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request(url: url, method: "POST", body: body))
        try validate(response: response, data: data, accepted: [204])
    }

    private func ensureStagingRelease() async throws -> Release {
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases?per_page=100")
        let (data, response) = try await session.data(for: request(url: url))
        try validate(response: response, data: data)
        if let releases = try? JSONDecoder().decode([Release].self, from: data),
           let release = releases.first(where: { $0.tagName == stagingTag }) {
            return release
        }

        let createURL = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases")
        let payload: [String: Any] = [
            "tag_name": stagingTag,
            "target_commitish": configuration.branch,
            "name": "Next Signer Inbox",
            "body": "Private staging release used by Next Signer.",
            "draft": true,
            "prerelease": true,
            "make_latest": "false"
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (created, createdResponse) = try await session.data(for: request(url: createURL, method: "POST", body: body))
        try validate(response: createdResponse, data: created)
        return try JSONDecoder().decode(Release.self, from: created)
    }

    private func uploadAsset(fileURL: URL, name: String, release: Release) async throws {
        guard var components = URLComponents(string: release.uploadURL.components(separatedBy: "{").first ?? release.uploadURL) else {
            throw NextSignerError.malformedURL
        }
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        guard let url = components.url else { throw NextSignerError.malformedURL }
        var req = request(url: url, method: "POST")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: req, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "NextSigner.AdHocInstall",
                code: 5205,
                userInfo: [NSLocalizedDescriptionKey: "Temporary IPA upload failed. \(detail)".trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
    }

    private func makeAssetName(original: String, stamp: Int) -> String {
        let safe = original
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        return "\(stamp)-install-\(UUID().uuidString.prefix(8))-\(safe)"
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.timeoutInterval = 300
        return req
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "https://api.github.com\(path)") else { throw NextSignerError.malformedURL }
        return url
    }

    private func validate(response: URLResponse, data: Data, accepted: Set<Int>? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw NextSignerError.invalidResponse }
        let ok = accepted.map { $0.contains(http.statusCode) } ?? (200...299).contains(http.statusCode)
        guard ok else {
            let detail = String(data: data, encoding: .utf8) ?? "GitHub HTTP \(http.statusCode)"
            throw NSError(
                domain: "NextSigner.AdHocInstall",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }
    }
}
