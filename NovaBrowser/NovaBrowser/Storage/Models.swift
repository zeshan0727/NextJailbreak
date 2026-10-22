import Foundation

enum SearchEngine: String, Codable, CaseIterable, Identifiable {
    case duckDuckGo = "DuckDuckGo"
    case google = "Google"
    case bing = "Bing"
    case brave = "Brave"
    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .duckDuckGo: return "https://duckduckgo.com/?q="
        case .google: return "https://www.google.com/search?q="
        case .bing: return "https://www.bing.com/search?q="
        case .brave: return "https://search.brave.com/search?q="
        }
    }
}

enum UserAgentPreset: String, Codable, CaseIterable, Identifiable {
    case system, iPhoneSafari, iPadDesktop, windowsChrome, androidChrome, linuxFirefox
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System WebKit"
        case .iPhoneSafari: return "iPhone Safari"
        case .iPadDesktop: return "iPad / Desktop"
        case .windowsChrome: return "Chrome (Windows)"
        case .androidChrome: return "Chrome (Android)"
        case .linuxFirefox: return "Firefox (Linux)"
        }
    }
}

enum PopupMode: String, Codable, CaseIterable, Identifiable {
    case useGlobal, block, allow
    var id: String { rawValue }
}

struct GlobalSiteSettings: Codable, Equatable {
    var userAgentPreset: UserAgentPreset = .system
    var desktopMode: Bool = false
    var javaScriptEnabled: Bool = true
    var popupMode: PopupMode = .allow
}

struct SiteSettings: Codable, Equatable, Identifiable {
    var host: String
    var userAgentPreset: UserAgentPreset?
    var desktopMode: Bool?
    var javaScriptEnabled: Bool?
    var popupMode: PopupMode = .useGlobal
    var id: String { host.lowercased() }
}

struct ResolvedSiteSettings: Equatable {
    var userAgentPreset: UserAgentPreset
    var desktopMode: Bool
    var javaScriptEnabled: Bool
    var popupMode: PopupMode
}

enum SiteSettingsResolver {
    static func resolve(host: String, global: GlobalSiteSettings, sites: [SiteSettings]) -> ResolvedSiteSettings {
        let key = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let site = sites.first { $0.host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == key }
        let globalPopup: PopupMode = global.popupMode == .useGlobal ? .allow : global.popupMode
        return ResolvedSiteSettings(
            userAgentPreset: site?.userAgentPreset ?? global.userAgentPreset,
            desktopMode: site?.desktopMode ?? global.desktopMode,
            javaScriptEnabled: site?.javaScriptEnabled ?? global.javaScriptEnabled,
            popupMode: site?.popupMode == nil || site?.popupMode == .useGlobal ? globalPopup : site!.popupMode
        )
    }
}

struct SavedTab: Codable, Identifiable {
    var id: UUID
    var address: String
    var title: String
}

struct Bookmark: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var address: String
    var created: Date = Date()
}

struct HistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var address: String
    var visited: Date = Date()
}

struct DownloadEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var filename: String
    var savedPath: String
    var downloaded: Date = Date()
}

struct BrowserSnapshot: Codable {
    var tabs: [SavedTab] = []
    var currentID: UUID?
    var bookmarks: [Bookmark] = []
    var history: [HistoryEntry] = []
    var downloads: [DownloadEntry] = []
    var siteSettings: [SiteSettings] = []
}
