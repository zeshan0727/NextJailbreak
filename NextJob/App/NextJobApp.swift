import SwiftUI

@main
struct NextJobApp: App {
    @StateObject private var store = JobStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
