import Combine
import Foundation
import SwiftUI
import UIKit

enum BrowserAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self { case .system: return .unspecified; case .light: return .light; case .dark: return .dark }
    }
}

final class BrowserSettings: ObservableObject {
    @Published var searchEngine: SearchEngine {
        didSet { UserDefaults.standard.set(searchEngine.rawValue, forKey: "searchEngine") }
    }
    @Published var appearance: BrowserAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var legacyPolyfillsEnabled: Bool {
        didSet { UserDefaults.standard.set(legacyPolyfillsEnabled, forKey: "legacyPolyfillsEnabled") }
    }
    @Published var globalSiteSettings: GlobalSiteSettings {
        didSet {
            if let encoded = try? JSONEncoder().encode(globalSiteSettings) {
                UserDefaults.standard.set(encoded, forKey: "globalSiteSettings")
            }
        }
    }

    init() {
        searchEngine = SearchEngine(rawValue: UserDefaults.standard.string(forKey: "searchEngine") ?? "") ?? .duckDuckGo
        appearance = BrowserAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .system
        legacyPolyfillsEnabled = UserDefaults.standard.object(forKey: "legacyPolyfillsEnabled") as? Bool ?? false
        if let data = UserDefaults.standard.data(forKey: "globalSiteSettings"),
           let decoded = try? JSONDecoder().decode(GlobalSiteSettings.self, from: data) {
            globalSiteSettings = decoded
        } else {
            globalSiteSettings = GlobalSiteSettings()
        }
    }
}
