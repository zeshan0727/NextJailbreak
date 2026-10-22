import SwiftUI

@main
struct NovaBrowserApp: App {
    @StateObject private var model = BrowserModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            BrowserView(model: model, settings: model.settings)
                .onChange(of: phase) { state in
                    if state != .active { model.save() }
                }
                .onOpenURL { url in
                    guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return }
                    let tab = model.addTab()
                    model.submit(url.absoluteString, in: tab)
                }
        }
    }
}
