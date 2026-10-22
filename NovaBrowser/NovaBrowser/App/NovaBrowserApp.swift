import SwiftUI

@main
struct NovaBrowserApp: App {
    @StateObject private var model = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            BrowserHomeView(model: model)
                .tint(.cyan)
                .preferredColorScheme(.dark)
        }
    }
}
