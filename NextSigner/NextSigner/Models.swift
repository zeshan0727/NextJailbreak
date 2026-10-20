import Foundation

struct SignRequest: Equatable {
    var ipaURL: URL?
    var appName: String = ""
    var bundleID: String = ""
    var customIconURL: URL?
    // Optional per-request profile and explicit entitlements. Never store P12 here.
    var customProvisioningURL: URL?
    var customEntitlementsURL: URL?
    var enableICloudDocuments = false
    var iCloudContainerIdentifier = ""
    var tweakURLs: [URL] = []
    var duplicateSigning = false
    var injectTweaksIntoExtensions = false
    var weakTweakInjection = false
    var signingEnabled = false

    var isReady: Bool {
        guard ipaURL != nil else { return false }
        if signingEnabled {
            return !appName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isValidBundleID
        }
        return true
    }

    var isValidBundleID: Bool {
        let value = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 3, value.contains("."), !value.hasPrefix("."), !value.hasSuffix(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

struct GitHubConfiguration: Equatable {
    var owner: String = "zeshan0727"
    var repository: String = "NextJailbreak"
    var branch: String = "main"
    var workflowFile: String = "nextsigner-sign-publish.yml"

    var isValid: Bool {
        !owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !workflowFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct SigningJob: Identifiable, Equatable {
    let id = UUID()
    let sourceName: String
    let requestedBundleID: String
    let requestedAppName: String
    var stage: Stage
    var detail: String

    enum Stage: String {
        case preparing = "Preparing"
        case uploading = "Uploading"
        case queued = "Queued"
        case failed = "Failed"
    }
}

struct PublishedCatalog: Decodable {
    let apps: [PublishedApp]
}

struct PublishedApp: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let version: String
    let build: String
    let platform: String
    let minimumOS: String
    let bundleId: String
    let icon: String?
    let manifest: String?
    let available: Bool?
    let status: String?
    let downloadURL: String?
    let sha256: String?
    let sizeBytes: Int64?
    let storage: String?

    var isR2Backed: Bool {
        guard let downloadURL else { return false }
        return downloadURL.hasPrefix("https://files.nextjailbreak.com/apps/ipa/")
    }
}

enum LibraryAction: String {
    case cleanOldVersions = "cleanup"
    case deleteApp = "delete"
}

enum NextSignerError: LocalizedError {
    case missingToken
    case invalidConfiguration
    case invalidResponse
    case http(Int, String)
    case uploadFailed
    case malformedURL
    case invalidAttachment(String)
    case libraryUnavailable

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "GitHub access token is not configured."
        case .invalidConfiguration:
            return "GitHub repository settings are incomplete."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .http(code, message):
            return "GitHub error \(code): \(message)"
        case .uploadFailed:
            return "A signing file could not be uploaded."
        case .malformedURL:
            return "A required URL could not be created."
        case let .invalidAttachment(message):
            return message
        case .libraryUnavailable:
            return "The published app library could not be loaded."
        }
    }
}
