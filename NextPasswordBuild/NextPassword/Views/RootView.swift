import SwiftUI

struct RootView: View {
    @EnvironmentObject private var lock: AppLock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if lock.isUnlocked {
                VaultView()
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                    Text("Next Password")
                        .font(.largeTitle.bold())
                    Button("Unlock") {
                        Task { await lock.unlock() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { lock.isUnlocked = false }
        }
    }
}
