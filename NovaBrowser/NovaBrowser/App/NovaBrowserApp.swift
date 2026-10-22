import SwiftUI

@main
struct NovaBrowserApp: App {
    @StateObject private var model: BrowserViewModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchDiagnostics.record("Application entry point reached")
        _model = StateObject(wrappedValue: BrowserViewModel())
    }

    var body: some Scene {
        WindowGroup {
            BrowserHomeView(model: model, settings: model.settings)
                .tint(.cyan)
                .onAppear { LaunchDiagnostics.record("Main browser screen appeared") }
        }
        .onChange(of: scenePhase) { phase in
            LaunchDiagnostics.record("Scene phase: \(phase)")
        }
    }
}
