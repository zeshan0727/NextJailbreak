import Foundation
import UIKit

struct SignedIPAResult: Codable, Equatable {
    let requestID: String
    let appName: String
    let bundleID: String
    let version: String
    let build: String
    let filename: String
    let localURL: URL
    let temporaryURL: URL
    let sha256: String
    let sizeBytes: Int64
    let stagingObjectKey: String
    let createdAt: Date
}

private struct ManualSignStatusPayload: Decodable {
    let requestID: String
    let state: String
    let stage: String
    let message: String
    let runURL: String?
    let updatedAt: String?
    let resultURL: String?
    let resultFilename: String?
    let resultSHA256: String?
    let resultSize: Int64?
    let resultBundleID: String?
    let resultAppName: String?
    let resultVersion: String?
    let resultBuild: String?
    let stagingObjectKey: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case state
        case stage
        case message
        case runURL = "run_url"
        case updatedAt = "updated_at"
        case resultURL = "result_url"
        case resultFilename = "result_filename"
        case resultSHA256 = "result_sha256"
        case resultSize = "result_size"
        case resultBundleID = "result_bundle_id"
        case resultAppName = "result_app_name"
        case resultVersion = "result_version"
        case resultBuild = "result_build"
        case stagingObjectKey = "staging_object_key"
    }
}

actor ManualSigningService {
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

    func sign(
        ipaURL: URL,
        appName: String,
        bundleID: String,
        customIconURL: URL?,
        tweakURLs: [URL],
        duplicateSigning: Bool,
        injectExtensions: Bool,
        weakInjection: Bool,
        progress: @Sendable (Double, String) async -> Void
    ) async throws -> SignedIPAResult {
        guard configuration.isValid else { throw NextSignerError.invalidConfiguration }

        let requestID = UUID().uuidString.lowercased()
        let release = try await ensureStagingRelease()
        let stamp = Int(Date().timeIntervalSince1970)

        await progress(0.05, "Opening private signing inbox")
        let ipaAsset = makeStagingAssetName(original: ipaURL.lastPathComponent, stamp: stamp, role: "app")
        try await uploadAsset(fileURL: ipaURL, name: ipaAsset, release: release)
        await progress(0.42, "IPA uploaded")

        var iconAsset = ""
        if let customIconURL {
            iconAsset = makeStagingAssetName(original: customIconURL.lastPathComponent, stamp: stamp, role: "icon")
            try await uploadAsset(fileURL: customIconURL, name: iconAsset, release: release)
        }
        await progress(0.50, "Signing options uploaded")

        var tweakAssets: [String] = []
        for (index, url) in tweakURLs.enumerated() {
            let name = makeStagingAssetName(original: url.lastPathComponent, stamp: stamp, role: "tweak\(index + 1)")
            try await uploadAsset(fileURL: url, name: name, release: release)
            tweakAssets.append(name)
            let fraction = Double(index + 1) / Double(max(tweakURLs.count, 1))
            await progress(0.50 + 0.18 * fraction, "Uploading tweak \(index + 1) of \(tweakURLs.count)")
        }

        let tweakJSONData = try JSONSerialization.data(withJSONObject: tweakAssets)
        let tweakJSON = String(data: tweakJSONData, encoding: .utf8) ?? "[]"

        try await dispatchSignOnly(
            requestID: requestID,
            assetName: ipaAsset,
            appName: appName,
            bundleID: bundleID,
            customIconAsset: iconAsset,
            tweakAssetsJSON: tweakJSON,
            duplicateSigning: duplicateSigning,
            injectExtensions: injectExtensions,
            weakInjection: weakInjection
        )
        await progress(0.72, "GitHub accepted the signing request")

        let status = try await waitForSignedResult(requestID: requestID, releaseID: release.id) { value, message in
            await progress(value, message)
        }

        guard
            let rawURL = status.resultURL,
            let temporaryURL = URL(string: rawURL),
            let filename = status.resultFilename,
            let stagingKey = status.stagingObjectKey
        else {
            throw NSError(
                domain: "NextSigner.SignOnly",
                code: 4101,
                userInfo: [NSLocalizedDescriptionKey: "Signing finished but GitHub did not return the signed IPA download information."]
            )
        }

        await progress(0.96, "Downloading signed IPA to this iPhone")
        let localURL = try await downloadSignedIPA(from: temporaryURL, filename: filename)
        let result = SignedIPAResult(
            requestID: requestID,
            appName: status.resultAppName ?? appName,
            bundleID: status.resultBundleID ?? bundleID,
            version: status.resultVersion ?? "",
            build: status.resultBuild ?? "",
            filename: filename,
            localURL: localURL,
            temporaryURL: temporaryURL,
            sha256: status.resultSHA256 ?? "",
            sizeBytes: status.resultSize ?? fileSize(localURL),
            stagingObjectKey: stagingKey,
            createdAt: Date()
        )
        await progress(1.0, "Signed IPA saved on device")
        return result
    }

    func cleanupTemporaryObject(_ objectKey: String) async {
        guard objectKey.hasPrefix("staging/nextsigner/") else { return }
        do {
            let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/dispatches")
            let payload: [String: Any] = [
                "event_type": "nextsigner_cleanup_signed_staging",
                "client_payload": ["object_key": objectKey]
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await session.data(for: request(url: url, method: "POST", body: body))
            try validate(response: response, data: data, accepted: [204])
        } catch {
            // Cleanup is best-effort and must never turn a successful publish into a failure.
        }
    }

    private func waitForSignedResult(
        requestID: String,
        releaseID: Int,
        progress: @Sendable (Double, String) async -> Void
    ) async throws -> ManualSignStatusPayload {
        let deadline = Date().addingTimeInterval(35 * 60)
        var lastSignature = ""

        while Date() < deadline {
            if let status = try await newestStatus(requestID: requestID, releaseID: releaseID) {
                let signature = "\(status.state)|\(status.stage)|\(status.message)|\(status.updatedAt ?? "")"
                if signature != lastSignature {
                    lastSignature = signature
                    await progress(progressValue(stage: status.stage, state: status.state), status.message)
                }

                switch status.state.lowercased() {
                case "success":
                    return status
                case "failed", "failure":
                    let suffix = status.runURL.map { " Run: \($0)" } ?? ""
                    throw NSError(
                        domain: "NextSigner.SignOnly",
                        code: 4102,
                        userInfo: [NSLocalizedDescriptionKey: "\(status.stage): \(status.message)\(suffix)"]
                    )
                default:
                    break
                }
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }

        throw NSError(
            domain: "NextSigner.SignOnly",
            code: 4103,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the signing workflow after 35 minutes."]
        )
    }

    private func newestStatus(requestID: String, releaseID: Int) async throws -> ManualSignStatusPayload? {
        var candidates: [Asset] = []
        let prefix = "status-\(requestID)-"
        let legacy = "status-\(requestID).json"

        for page in 1...8 {
            let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/\(releaseID)/assets?per_page=100&page=\(page)&_ns=\(UUID().uuidString)")
            var req = request(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await session.data(for: req)
            try validate(response: response, data: data)
            let assets = try JSONDecoder().decode([Asset].self, from: data)
            candidates.append(contentsOf: assets.filter { $0.name.hasPrefix(prefix) || $0.name == legacy })
            if assets.count < 100 { break }
        }

        guard let newest = candidates.max(by: { $0.id < $1.id }) else { return nil }
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/releases/assets/\(newest.id)?_ns=\(UUID().uuidString)")
        var req = request(url: url)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("no-cache, no-store, max-age=0", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NextSignerError.invalidResponse }
        if http.statusCode == 404 || String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("BlobNotFound") == true {
            return nil
        }
        try validate(response: response, data: data)
        return try JSONDecoder().decode(ManualSignStatusPayload.self, from: data)
    }

    private func dispatchSignOnly(
        requestID: String,
        assetName: String,
        appName: String,
        bundleID: String,
        customIconAsset: String,
        tweakAssetsJSON: String,
        duplicateSigning: Bool,
        injectExtensions: Bool,
        weakInjection: Bool
    ) async throws {
        let url = try apiURL("/repos/\(configuration.owner)/\(configuration.repository)/dispatches")
        let body: [String: Any] = [
            "event_type": "nextsigner_sign_only",
            "client_payload": [
                "request_id": requestID,
                "staging_asset": assetName,
                "requested_name": appName,
                "requested_bundle_id": bundleID,
                "custom_icon_asset": customIconAsset,
                "tweak_assets_json": tweakAssetsJSON,
                "duplicate_signing": duplicateSigning ? "true" : "false",
                "inject_extensions": injectExtensions ? "true" : "false",
                "weak_injection": weakInjection ? "true" : "false"
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request(url: url, method: "POST", body: encoded))
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
        let encoded = try JSONSerialization.data(withJSONObject: payload)
        let (created, createdResponse) = try await session.data(for: request(url: createURL, method: "POST", body: encoded))
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
        let (_, response) = try await session.upload(for: req, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NextSignerError.uploadFailed
        }
    }

    private func downloadSignedIPA(from url: URL, filename: String) async throws -> URL {
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 300
        let (tempURL, response) = try await session.download(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "NextSigner.SignOnly", code: 4104, userInfo: [NSLocalizedDescriptionKey: "The signed IPA could not be downloaded to this device."])
        }

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Signed IPAs", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeName = filename.replacingOccurrences(of: "/", with: "-")
        let destination = folder.appendingPathComponent(safeName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
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
        let allowed = accepted ?? Set(200...299)
        guard allowed.contains(http.statusCode) else {
            let message: String
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let apiMessage = object["message"] as? String {
                message = apiMessage
            } else {
                message = String(data: data, encoding: .utf8) ?? "Unknown error"
            }
            throw NextSignerError.http(http.statusCode, message)
        }
    }

    private func makeStagingAssetName(original: String, stamp: Int, role: String) -> String {
        let safe = original.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        return "\(stamp)-\(role)-\(safe)"
    }

    private func progressValue(stage: String, state: String) -> Double {
        if state.lowercased() == "success" { return 0.94 }
        switch stage.lowercased() {
        case "received": return 0.73
        case "validate": return 0.76
        case "download": return 0.79
        case "zsign": return 0.82
        case "customize": return 0.85
        case "sign": return 0.89
        case "metadata": return 0.91
        case "staging upload", "verify": return 0.93
        default: return 0.80
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}

@MainActor
final class ManualSignController: ObservableObject {
    @Published var result: SignedIPAResult?
    @Published var isSigning = false
    @Published var isPublishing = false
    @Published var progress: Double = 0
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var publishMessage: String?

    private let persistedKey = "nextsigner.latestSignedResult"

    init() {
        if let data = UserDefaults.standard.data(forKey: persistedKey),
           let decoded = try? JSONDecoder().decode(SignedIPAResult.self, from: data),
           FileManager.default.fileExists(atPath: decoded.localURL.path) {
            result = decoded
        }
    }

    func sign(using store: SignerStore) {
        guard !isSigning && !isPublishing else { return }
        guard let ipaURL = store.request.ipaURL else {
            errorMessage = "Choose an IPA or TIPA first."
            return
        }
        guard !store.request.appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              store.request.isValidBundleID else {
            errorMessage = "Enter a valid app name and bundle identifier before signing."
            return
        }
        guard store.configuration.isValid else {
            errorMessage = NextSignerError.invalidConfiguration.localizedDescription
            return
        }
        let token = KeychainStore.load(account: "github-token") ?? store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = NextSignerError.missingToken.localizedDescription
            return
        }

        store.persistConfiguration()
        isSigning = true
        progress = 0
        statusMessage = "Preparing signing request"
        errorMessage = nil
        publishMessage = nil
        result = nil
        UserDefaults.standard.removeObject(forKey: persistedKey)

        let snapshot = store.request
        store.activeJob = SigningJob(
            sourceName: ipaURL.lastPathComponent,
            requestedBundleID: snapshot.bundleID,
            requestedAppName: snapshot.appName,
            stage: .preparing,
            detail: "Signing IPA first. Nothing will be published to the site automatically."
        )

        let service = ManualSigningService(token: token, configuration: store.configuration)
        Task {
            do {
                store.activeJob?.stage = .uploading
                let signed = try await service.sign(
                    ipaURL: ipaURL,
                    appName: snapshot.appName,
                    bundleID: snapshot.bundleID,
                    customIconURL: snapshot.customIconURL,
                    tweakURLs: snapshot.tweakURLs,
                    duplicateSigning: snapshot.duplicateSigning,
                    injectExtensions: snapshot.injectTweaksIntoExtensions,
                    weakInjection: snapshot.weakTweakInjection,
                    progress: { value, message in
                        await MainActor.run {
                            self.progress = value
                            self.statusMessage = message
                            store.activeJob?.detail = message
                        }
                    }
                )
                result = signed
                persist(signed)
                store.activeJob?.stage = .queued
                store.activeJob?.detail = "Signed IPA saved on device. Choose Install or Publish to Site."
                statusMessage = "Signed IPA saved on device"
            } catch {
                store.activeJob?.stage = .failed
                store.activeJob?.detail = error.localizedDescription
                errorMessage = error.localizedDescription
            }
            isSigning = false
        }
    }

    func publishToSite(using store: SignerStore) {
        guard !isSigning && !isPublishing else { return }
        guard let result else {
            errorMessage = "Sign an IPA first."
            return
        }
        guard FileManager.default.fileExists(atPath: result.localURL.path) else {
            errorMessage = "The signed IPA is no longer available on this device. Sign it again."
            return
        }
        let token = KeychainStore.load(account: "github-token") ?? store.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = NextSignerError.missingToken.localizedDescription
            return
        }

        isPublishing = true
        publishMessage = nil
        errorMessage = nil
        let service = GitHubService(token: token, configuration: store.configuration)
        let cleanupService = ManualSigningService(token: token, configuration: store.configuration)

        Task {
            do {
                _ = try await service.uploadAndDispatch(
                    ipaURL: result.localURL,
                    appName: result.appName,
                    bundleID: result.bundleID,
                    customIconURL: nil,
                    tweakURLs: [],
                    signingEnabled: false,
                    duplicateSigning: false,
                    injectExtensions: false,
                    weakInjection: false,
                    progress: { value in
                        await MainActor.run { self.progress = value }
                    }
                )
                publishMessage = "Published to the site successfully."
                await cleanupService.cleanupTemporaryObject(result.stagingObjectKey)
            } catch {
                errorMessage = error.localizedDescription
            }
            isPublishing = false
        }
    }

    func install() {
        guard let result else {
            errorMessage = "Sign an IPA first."
            return
        }
        let encoded = result.temporaryURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? result.temporaryURL.absoluteString
        guard let url = URL(string: "apple-magnifier://install?url=\(encoded)") else {
            errorMessage = "Could not create the TrollStore installation URL."
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    self.errorMessage = "TrollStore could not be opened. Save/share the IPA and install it manually."
                }
            }
        }
    }

    func forgetResult() {
        result = nil
        progress = 0
        statusMessage = ""
        publishMessage = nil
        UserDefaults.standard.removeObject(forKey: persistedKey)
    }

    private func persist(_ result: SignedIPAResult) {
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: persistedKey)
        }
    }
}
