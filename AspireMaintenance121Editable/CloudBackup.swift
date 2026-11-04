import Foundation

// MARK: - Automatic iCloud backup

struct AspireBackupResult {
    enum Location: String {
        case iCloud = "iCloud Drive"
        case localFallback = "Local Safety Backup"
    }

    let url: URL
    let location: Location
    let date: Date
    let cloudIssue: String?
}

enum AspireCloudBackupError: LocalizedError {
    case noBackupFound
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .noBackupFound: return "No automatic backup is available yet."
        case .invalidBackup: return "The latest automatic backup could not be read."
        }
    }
}

final class AspireCloudBackupService {
    static let shared = AspireCloudBackupService()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.aspiregroup.maintenance.cloudbackup", qos: .utility)
    private let containerIdentifier = "iCloud.com.aspiregroup.maintenance"
    private let maximumBackups = 10
    private let formatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return value
    }()

    private init() {}

    func checkICloudAccess(completion: @escaping (String) -> Void) {
        queue.async { [self] in
            let message: String
            if fileManager.ubiquityIdentityToken == nil {
                message = "iCloud documents are unavailable for this device/account. Check Settings → Apple Account → iCloud → Drive and enable Sync this iPhone."
            } else if fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) == nil {
                message = "iCloud account detected, but this app cannot open \(containerIdentifier). Check the signed app's CloudDocuments entitlement, container assignment and provisioning profile."
            } else {
                message = "iCloud account and Aspire container are accessible on this device. Tap Back Up Now to verify a backup write."
            }
            DispatchQueue.main.async { completion(message) }
        }
    }

    func createBackup(data: Data, completion: @escaping (Result<AspireBackupResult, Error>) -> Void) {
        queue.async { [self] in
            do {
                let result = try writeBackup(data: data)
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func loadLatestBackup(completion: @escaping (Result<(Data, AspireBackupResult), Error>) -> Void) {
        queue.async { [self] in
            do {
                if let cloudDirectory = cloudBackupDirectory(create: false),
                   let latest = latestBackup(in: cloudDirectory) {
                    let data = try Data(contentsOf: latest)
                    guard !data.isEmpty else { throw AspireCloudBackupError.invalidBackup }
                    let result = AspireBackupResult(url: latest, location: .iCloud, date: modificationDate(for: latest), cloudIssue: nil)
                    DispatchQueue.main.async { completion(.success((data, result))) }
                    return
                }

                let localDirectory = try localBackupDirectory()
                if let latest = latestBackup(in: localDirectory) {
                    let data = try Data(contentsOf: latest)
                    guard !data.isEmpty else { throw AspireCloudBackupError.invalidBackup }
                    let result = AspireBackupResult(url: latest, location: .localFallback, date: modificationDate(for: latest), cloudIssue: nil)
                    DispatchQueue.main.async { completion(.success((data, result))) }
                    return
                }

                throw AspireCloudBackupError.noBackupFound
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func writeBackup(data: Data) throws -> AspireBackupResult {
        let date = Date()
        let fileName = "Aspire-Maintenance-\(formatter.string(from: date)).json"
        var cloudFailure: String? = nil

        if fileManager.ubiquityIdentityToken == nil {
            cloudFailure = "iCloud Drive unavailable on this device; check iCloud Drive in Settings."
        } else if let root = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) {
            let cloudDirectory = root
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Aspire Maintenance", isDirectory: true)
                .appendingPathComponent("Backups", isDirectory: true)
            do {
                try fileManager.createDirectory(at: cloudDirectory, withIntermediateDirectories: true)
                let url = cloudDirectory.appendingPathComponent(fileName)
                try data.write(to: url, options: [.atomic])
                guard try Data(contentsOf: url) == data else {
                    throw AspireCloudBackupError.invalidBackup
                }
                try rotateBackups(in: cloudDirectory)
                return AspireBackupResult(url: url, location: .iCloud, date: date, cloudIssue: nil)
            } catch {
                cloudFailure = "Cannot write to Aspire iCloud container: \(error.localizedDescription)"
            }
        } else {
            cloudFailure = "iCloud account detected, but signed Aspire cannot access \(containerIdentifier). Verify its CloudDocuments entitlement and provisioning profile."
        }

        let localDirectory = try localBackupDirectory()
        let url = localDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try rotateBackups(in: localDirectory)
        return AspireBackupResult(url: url, location: .localFallback, date: date, cloudIssue: cloudFailure)
    }

    private func cloudBackupDirectory(create: Bool) -> URL? {
        guard fileManager.ubiquityIdentityToken != nil,
              let root = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else { return nil }
        let directory = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Aspire Maintenance", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        if create {
            do { try fileManager.createDirectory(at: directory, withIntermediateDirectories: true) }
            catch { return nil }
        }
        return directory
    }

    private func localBackupDirectory() throws -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = support
            .appendingPathComponent("AspireMaintenance", isDirectory: true)
            .appendingPathComponent("AutomaticBackups", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func latestBackup(in directory: URL) -> URL? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { modificationDate(for: $0) > modificationDate(for: $1) }
            .first
    }

    private func rotateBackups(in directory: URL) throws {
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        let backups = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { modificationDate(for: $0) > modificationDate(for: $1) }
        guard backups.count > maximumBackups else { return }
        for oldURL in backups.dropFirst(maximumBackups) {
            try? fileManager.removeItem(at: oldURL)
        }
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
