import Combine
import Foundation

final class BrowserSettings: ObservableObject {
    @Published var searchEngine: SearchEngine {
        didSet { UserDefaults.standard.set(searchEngine.rawValue, forKey: "searchEngine") }
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
        if let data = UserDefaults.standard.data(forKey: "globalSiteSettings"),
           let decoded = try? JSONDecoder().decode(GlobalSiteSettings.self, from: data) {
            globalSiteSettings = decoded
        } else {
            globalSiteSettings = GlobalSiteSettings()
        }
    }
}
