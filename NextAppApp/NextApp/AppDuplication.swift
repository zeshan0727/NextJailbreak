import Foundation
import Network
import UIKit
import ZIPFoundation

struct DuplicateAppResult: Identifiable, Hashable {
    let index: Int
    let name: String
    let bundleId: String
    let fileURL: URL

    var id: String { bundleId }
}

enum DuplicateAppError: LocalizedError {
    case unavailable
    case invalidManifest
    case invalidArchive
    case appBundleMissing
    case infoPlistMissing
    case invalidBundleIdentifier
    case cannotOpenTrollStore

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This app does not have a downloadable IPA."
        case .invalidManifest:
            return "The app install manifest does not contain a valid IPA URL."
        case .invalidArchive:
            return "The downloaded IPA could not be extracted."
        case .appBundleMissing:
            return "The IPA does not contain an application bundle."
        case .infoPlistMissing:
            return "The app Info.plist could not be read."
        case .invalidBundleIdentifier:
            return "The app bundle identifier could not be prepared for duplication."
        case .cannotOpenTrollStore:
            return "TrollStore could not be opened. Enable TrollStore's URL Scheme or use the Share button."
        }
    }
}

enum DuplicateAppEngine {
    private struct PlistSnapshot {
        let url: URL
        let original: [String: Any]
        let originalBundleId: String?
        let isMainApp: Bool
    }

    static func createCopies(
        of app: NextAppItem,
        count: Int,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> [DuplicateAppResult] {
        try await Task.detached(priority: .userInitiated) {
            let copyCount = min(max(count, 1), 10)
            let fileManager = FileManager.default

            progress("Finding the IPA…")
            let sourceURL = try await resolveDownloadURL(for: app)

            let workspace = fileManager.temporaryDirectory
                .appendingPathComponent("NextAppDuplicate-\(UUID().uuidString)", isDirectory: true)
            let sourceIPA = workspace.appendingPathComponent("source.ipa")
            let extracted = workspace.appendingPathComponent("extracted", isDirectory: true)

            try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: workspace) }

            progress("Downloading \(app.name)…")
            var request = URLRequest(url: sourceURL)
            request.timeoutInterval = 900
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("NextApp/1.0.2", forHTTPHeaderField: "User-Agent")

            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            try? fileManager.removeItem(at: sourceIPA)
            do {
                try fileManager.moveItem(at: temporaryURL, to: sourceIPA)
            } catch {
                try fileManager.copyItem(at: temporaryURL, to: sourceIPA)
            }

            try Task.checkCancellation()
            progress("Extracting the app…")

            do {
                try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
                try fileManager.unzipItem(at: sourceIPA, to: extracted)
            } catch {
                throw DuplicateAppError.invalidArchive
            }

            guard let mainAppURL = locateMainApp(in: extracted) else {
                throw DuplicateAppError.appBundleMissing
            }

            let mainInfoURL = mainAppURL.appendingPathComponent("Info.plist")
            guard let mainInfo = try readPlist(at: mainInfoURL),
                  let originalRootId = mainInfo["CFBundleIdentifier"] as? String,
                  !originalRootId.isEmpty else {
                throw DuplicateAppError.infoPlistMissing
            }

            let snapshots = try collectPlistSnapshots(
                inside: mainAppURL,
                mainInfoURL: mainInfoURL
            )

            removeOldSignatures(in: mainAppURL)

            let outputDirectory = documentsDirectory()
                .appendingPathComponent("NextAppDuplicates", isDirectory: true)
                .appendingPathComponent(safeFileName(app.id), isDirectory: true)

            try fileManager.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let existing = try? fileManager.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: nil
            )
            existing?.forEach { try? fileManager.removeItem(at: $0) }

            var results: [DuplicateAppResult] = []
            results.reserveCapacity(copyCount)

            for index in 1...copyCount {
                try Task.checkCancellation()

                progress("Creating duplicate \(index) of \(copyCount)…")

                let duplicateRootId = makeDuplicateBundleIdentifier(
                    base: originalRootId,
                    index: index
                )

                try applyDuplicateMetadata(
                    snapshots: snapshots,
                    originalRootId: originalRootId,
                    duplicateRootId: duplicateRootId,
                    appName: app.name,
                    index: index
                )

                let fileName = "\(safeFileName(app.name))-Duplicate-\(index).ipa"
                let outputURL = outputDirectory.appendingPathComponent(fileName)
                try? fileManager.removeItem(at: outputURL)

                try fileManager.zipItem(
                    at: extracted,
                    to: outputURL,
                    shouldKeepParent: false,
                    compressionMethod: .deflate
                )

                results.append(
                    DuplicateAppResult(
                        index: index,
                        name: "\(app.name) \(index)",
                        bundleId: duplicateRootId,
                        fileURL: outputURL
                    )
                )
            }

            progress("Ready to install")
            return results
        }.value
    }

    private static func resolveDownloadURL(for app: NextAppItem) async throws -> URL {
        if let raw = app.downloadURL,
           let url = URL(string: raw),
           url.scheme != nil {
            return url
        }

        guard app.available,
              let manifestURL = URL(
                string: app.manifest,
                relativeTo: AppInstaller.baseURL
              )?.absoluteURL else {
            throw DuplicateAppError.unavailable
        }

        var request = URLRequest(url: manifestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            throw DuplicateAppError.invalidManifest
        }

        for item in items {
            guard let assets = item["assets"] as? [[String: Any]] else { continue }

            for asset in assets {
                guard (asset["kind"] as? String) == "software-package",
                      let value = asset["url"] as? String,
                      let url = URL(string: value) else {
                    continue
                }
                return url
            }
        }

        throw DuplicateAppError.invalidManifest
    }

    private static func locateMainApp(in extracted: URL) -> URL? {
        let payload = extracted.appendingPathComponent("Payload", isDirectory: true)

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: payload,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return contents.first { $0.pathExtension.lowercased() == "app" }
    }

    private static func collectPlistSnapshots(
        inside mainAppURL: URL,
        mainInfoURL: URL
    ) throws -> [PlistSnapshot] {
        let fileManager = FileManager.default
        var snapshots: [PlistSnapshot] = []

        guard let enumerator = fileManager.enumerator(
            at: mainAppURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [],
            errorHandler: nil
        ) else {
            throw DuplicateAppError.infoPlistMissing
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "Info.plist" else { continue }

            let bundleDirectory = url.deletingLastPathComponent()
            let ext = bundleDirectory.pathExtension.lowercased()
            guard ext == "app" || ext == "appex" else { continue }

            guard let dictionary = try readPlist(at: url) else { continue }

            snapshots.append(
                PlistSnapshot(
                    url: url,
                    original: dictionary,
                    originalBundleId: dictionary["CFBundleIdentifier"] as? String,
                    isMainApp: url.standardizedFileURL == mainInfoURL.standardizedFileURL
                )
            )
        }

        if !snapshots.contains(where: { $0.isMainApp }) {
            guard let dictionary = try readPlist(at: mainInfoURL) else {
                throw DuplicateAppError.infoPlistMissing
            }

            snapshots.append(
                PlistSnapshot(
                    url: mainInfoURL,
                    original: dictionary,
                    originalBundleId: dictionary["CFBundleIdentifier"] as? String,
                    isMainApp: true
                )
            )
        }

        return snapshots
    }

    private static func applyDuplicateMetadata(
        snapshots: [PlistSnapshot],
        originalRootId: String,
        duplicateRootId: String,
        appName: String,
        index: Int
    ) throws {
        for snapshot in snapshots {
            var dictionary = snapshot.original

            if let currentId = snapshot.originalBundleId, !currentId.isEmpty {
                let replacement: String

                if snapshot.isMainApp {
                    replacement = duplicateRootId
                } else if currentId == originalRootId {
                    replacement = duplicateRootId
                } else if currentId.hasPrefix(originalRootId + ".") {
                    replacement = duplicateRootId + String(currentId.dropFirst(originalRootId.count))
                } else {
                    replacement = makeDuplicateBundleIdentifier(
                        base: currentId,
                        index: index
                    )
                }

                dictionary["CFBundleIdentifier"] = replacement
            }

            if snapshot.isMainApp {
                let duplicateName = "\(appName) \(index)"
                dictionary["CFBundleDisplayName"] = duplicateName
                dictionary["CFBundleName"] = duplicateName
            }

            let data = try PropertyListSerialization.data(
                fromPropertyList: dictionary,
                format: .xml,
                options: 0
            )
            try data.write(to: snapshot.url, options: .atomic)
        }
    }

    private static func readPlist(at url: URL) throws -> [String: Any]? {
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
    }

    private static func removeOldSignatures(in appURL: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: appURL,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: nil
        ) else {
            return
        }

        var targets: [URL] = []

        for case let url as URL in enumerator {
            if url.lastPathComponent == "_CodeSignature"
                || url.lastPathComponent == "embedded.mobileprovision" {
                targets.append(url)
            }
        }

        targets
            .sorted { $0.pathComponents.count > $1.pathComponents.count }
            .forEach { try? fileManager.removeItem(at: $0) }
    }

    private static func makeDuplicateBundleIdentifier(
        base: String,
        index: Int
    ) -> String {
        let cleaned = base
            .split(separator: ".")
            .map { component in
                component
                    .map { character in
                        character.isLetter || character.isNumber || character == "-"
                            ? character
                            : "-"
                    }
                    .reduce(into: "") { $0.append($1) }
            }
            .filter { !$0.isEmpty }
            .joined(separator: ".")

        let safeBase = cleaned.isEmpty ? "com.nextapp.duplicate" : cleaned
        return "\(safeBase).nextdup\(index)"
    }

    private static func safeFileName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))

        let name = value.unicodeScalars
            .map { allowed.contains($0) ? Character(String($0)) : "_" }
            .reduce("") { $0 + String($1) }

        return name.isEmpty ? "app" : name
    }

    private static func documentsDirectory() -> URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    }
}

final class DuplicateIPAInstallBridge {
    static let shared = DuplicateIPAInstallBridge()

    private let queue = DispatchQueue(label: "com.nextsolution.nextapp.duplicate-install")
    private var listener: NWListener?
    private var servedFileURL: URL?
    private var requestPath = ""
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    func install(
        fileURL: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        stop()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(.failure(URLError(.fileDoesNotExist)))
            return
        }

        do {
            let token = UUID().uuidString.lowercased()
            let path = "/\(token).ipa"

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port.any
            )

            let listener = try NWListener(using: parameters)
            self.listener = listener
            self.servedFileURL = fileURL
            self.requestPath = path

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }

            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let listener else { return }

                switch state {
                case .ready:
                    guard let port = listener.port else {
                        DispatchQueue.main.async {
                            completion(.failure(URLError(.cannotConnectToHost)))
                        }
                        self.stop()
                        return
                    }

                    let localURL = URL(
                        string: "http://127.0.0.1:\(port.rawValue)\(path)"
                    )!

                    var components = URLComponents()
                    components.scheme = "apple-magnifier"
                    components.host = "install"
                    components.queryItems = [
                        URLQueryItem(name: "url", value: localURL.absoluteString)
                    ]

                    guard let trollStoreURL = components.url else {
                        DispatchQueue.main.async {
                            completion(.failure(DuplicateAppError.cannotOpenTrollStore))
                        }
                        self.stop()
                        return
                    }

                    DispatchQueue.main.async {
                        self.beginBackgroundTask()

                        UIApplication.shared.open(
                            trollStoreURL,
                            options: [:]
                        ) { opened in
                            if opened {
                                completion(.success(()))
                            } else {
                                completion(.failure(DuplicateAppError.cannotOpenTrollStore))
                                self.stop()
                            }
                        }
                    }

                case .failed(let error):
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    self.stop()

                default:
                    break
                }
            }

            listener.start(queue: queue)
        } catch {
            completion(.failure(error))
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        servedFileURL = nil
        requestPath = ""
        endBackgroundTask()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16 * 1024
        ) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                connection.cancel()
                DispatchQueue.main.async {
                    self.stop()
                }
                _ = error
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let firstLine = request.components(separatedBy: "\r\n").first else {
                self.sendNotFound(on: connection)
                return
            }

            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2,
                  parts[0] == "GET",
                  String(parts[1]) == self.requestPath,
                  let fileURL = self.servedFileURL else {
                self.sendNotFound(on: connection)
                return
            }

            self.sendFile(fileURL, on: connection)
        }
    }

    private func sendFile(_ fileURL: URL, on connection: NWConnection) {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL.path
        ),
              let sizeNumber = attributes[.size] as? NSNumber,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            sendNotFound(on: connection)
            return
        }

        let header = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/octet-stream",
            "Content-Length: \(sizeNumber.int64Value)",
            "Content-Disposition: attachment; filename=\"\(fileURL.lastPathComponent)\"",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        connection.send(
            content: Data(header.utf8),
            completion: .contentProcessed { [weak self] error in
                guard error == nil else {
                    try? handle.close()
                    connection.cancel()
                    DispatchQueue.main.async {
                        self?.stop()
                    }
                    return
                }

                self?.sendNextChunk(
                    handle: handle,
                    connection: connection
                )
            }
        )
    }

    private func sendNextChunk(
        handle: FileHandle,
        connection: NWConnection
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            do {
                let chunk = try handle.read(upToCount: 256 * 1024) ?? Data()

                if chunk.isEmpty {
                    try? handle.close()

                    connection.send(
                        content: nil,
                        contentContext: .defaultMessage,
                        isComplete: true,
                        completion: .contentProcessed { [weak self] _ in
                            connection.cancel()

                            self?.queue.asyncAfter(deadline: .now() + 1.0) {
                                DispatchQueue.main.async {
                                    self?.stop()
                                }
                            }
                        }
                    )
                    return
                }

                connection.send(
                    content: chunk,
                    completion: .contentProcessed { [weak self] error in
                        if error != nil {
                            try? handle.close()
                            connection.cancel()
                            DispatchQueue.main.async {
                                self?.stop()
                            }
                            return
                        }

                        self?.sendNextChunk(
                            handle: handle,
                            connection: connection
                        )
                    }
                )
            } catch {
                try? handle.close()
                connection.cancel()
                DispatchQueue.main.async {
                    self.stop()
                }
            }
        }
    }

    private func sendNotFound(on connection: NWConnection) {
        let body = Data("Not Found".utf8)
        let header = [
            "HTTP/1.1 404 Not Found",
            "Content-Type: text/plain",
            "Content-Length: \(body.count)",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(header.utf8)
        response.append(body)

        connection.send(
            content: response,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }

        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "NextApp Duplicate Install"
        ) { [weak self] in
            self?.stop()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }

        let task = backgroundTask
        backgroundTask = .invalid

        DispatchQueue.main.async {
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}
