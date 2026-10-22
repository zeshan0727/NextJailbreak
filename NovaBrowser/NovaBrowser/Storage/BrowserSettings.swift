import Foundation
import Combine

struct BrowserSettings: Codable, Equatable {
    var searchEngine: SearchEngine = .duckDuckGo
    var httpsFirst = true
    var restoreSession = true
    var appearance: Appearance = .system
    enum Appearance: String, Codable, CaseIterable { case system, light, dark }
}

final class SettingsStore: ObservableObject {
    @Published var value: BrowserSettings { didSet { persist() } }
    private let defaults: UserDefaults
    private let key = "NovaBrowser.Settings.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(BrowserSettings.self, from: $0) } ?? BrowserSettings()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
