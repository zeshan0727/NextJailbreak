import SwiftUI

@main
struct AspireMaintenanceApp: App {
    @StateObject private var store = AspireStore()
    @StateObject private var deviceSync = AspireDeviceSyncController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .environmentObject(deviceSync)
                .onAppear { deviceSync.attach(store) }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await store.refreshOverdueNotifications() }
                store.performAutomaticCloudBackup(reason: "App opened")
                deviceSync.start()
            } else if phase == .background {
                store.performAutomaticCloudBackup(reason: "App backgrounded")
                deviceSync.enterBackground()
            }
        }
    }
}
