import SwiftUI

@main
struct NextPasswordApp: App {
    @StateObject private var vault = VaultStore()
    @StateObject private var lock = AppLock()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vault)
                .environmentObject(lock)
                .task { await lock.unlock() }
        }
    }
}
