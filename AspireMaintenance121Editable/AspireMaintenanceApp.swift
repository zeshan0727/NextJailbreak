import SwiftUI

@main
struct AspireMaintenanceApp: App {
    @StateObject private var store = AspireStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.refreshOverdueNotifications() }
                store.performAutomaticCloudBackup(reason: "App opened")
            } else if phase == .background {
                store.performAutomaticCloudBackup(reason: "App backgrounded")
            }
        }
    }
}
