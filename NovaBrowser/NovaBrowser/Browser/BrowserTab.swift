import Foundation
import Combine
import UIKit

final class BrowserTab: ObservableObject, Identifiable {
    let id: UUID
    let isPrivate: Bool
    @Published var title: String
    @Published var url: URL?
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var errorMessage: String?
    @Published var needsResume: Bool
    @Published var thumbnail: UIImage?
    @Published var pageZoom = 1.0
    @Published var foundMatch: Bool?
    var isLocalTest = false
    init(id: UUID = UUID(), title: String = "New Tab", url: URL? = nil, isPrivate: Bool = false, needsResume: Bool = false) {
        self.id = id
        self.title = title
        self.url = url
        self.isPrivate = isPrivate
        self.needsResume = needsResume
    }
    var record: TabRecord { TabRecord(id: id, title: title, url: isLocalTest ? nil : url, isPrivate: isPrivate) }
}
