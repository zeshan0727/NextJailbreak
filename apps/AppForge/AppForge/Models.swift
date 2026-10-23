import Foundation

enum ForgeTab: Int, CaseIterable, Identifiable {
    case requirement, code, github, status, downloads, support
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .requirement: return "Prompt"
        case .code: return "Code"
        case .github: return "GitHub"
        case .status: return "Build"
        case .downloads: return "Downloads"
        case .support: return "AI Support"
        }
    }
    var symbol: String {
        switch self {
        case .requirement: return "text.bubble"
        case .code: return "curlybraces"
        case .github: return "arrow.up.doc"
        case .status: return "hammer"
        case .downloads: return "square.and.arrow.down"
        case .support: return "bubble.left.and.wrench.bubble.right"
        }
    }
}

enum ForgeError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return "Unexpected error"
    }
}

struct ForgeFile: Codable, Hashable, Identifiable {
    var path: String
    var content: String
    var id: String { path }
}

struct ForgeProject: Codable {
    var appName: String
    var bundleId: String
    var files: [ForgeFile]
}

struct HistoryItem: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date = Date()
    var requirement: String
    var prompt: String
}

struct ForgePreferences: Codable {
    var aiBaseURL = "https://api.groq.com/openai/v1"
    var aiModel = ""
    var githubUsername = ""
    var defaultRepo = ""
    var appearance = "system"
    var minimumIOS = "16.0"
}

struct GitHubRepo: Decodable, Identifiable {
    let name: String
    let full_name: String
    let default_branch: String
    let privateRepo: Bool
    var id: String { full_name }
    enum CodingKeys: String, CodingKey {
        case name, full_name, default_branch
        case privateRepo = "private"
    }
}

struct GitHubBranch: Decodable, Identifiable {
    let name: String
    var id: String { name }
}

struct GitHubRun: Decodable, Identifiable {
    let id: Int
    let status: String
    let conclusion: String?
    let head_sha: String
    let created_at: String
    let updated_at: String
    let html_url: String
    let path: String?
    let run_number: Int?
    let run_attempt: Int?
}

struct GitHubJob: Decodable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let steps: [GitHubStep]?
}

struct GitHubStep: Decodable, Identifiable {
    let name: String
    let status: String
    let conclusion: String?
    let number: Int
    var id: Int { number }
}

struct GitHubRelease: Decodable, Identifiable {
    let id: Int
    let tag_name: String
    let published_at: String?
    let created_at: String?
    let target_commitish: String?
    let html_url: String?
    let assets: [GitHubAsset]

    var ipaAssets: [GitHubAsset] {
        assets.filter { $0.name.lowercased().hasSuffix(".ipa") }
    }

    var sortDate: String { published_at ?? created_at ?? "" }
}

struct GitHubAsset: Decodable, Identifiable {
    let id: Int
    let name: String
    let size: Int64
    let browser_download_url: String
}

struct StoredDownload: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
    var name: String { url.lastPathComponent }
    var size: Int64 {
        let info = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (info?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

extension Int64 {
    var forgeSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}


/// In-memory support chat messages. Never stores user text, source or logs in UserDefaults.
struct SupportMessage: Identifiable {
    let id = UUID()
    let role: String
    let content: String
}
