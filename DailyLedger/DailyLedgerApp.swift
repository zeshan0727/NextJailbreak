import SwiftUI

@main
struct DailyLedgerApp: App {
    @StateObject private var store = LedgerStore()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("DailyLedgerAppearance") private var appearance = AppAppearance.system.rawValue

    init() {
        BackupSyncService.shared.registerBackgroundTask()
        BudgetNotificationService.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(store)
                .tint(AppTheme.purple)
                .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
                .onAppear {
                    BackupSyncService.shared.backupOnAppOpen()
                    DeviceSyncService.shared.start(store: store)
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        store.reload()
                        BackupSyncService.shared.backupOnAppOpen()
                        DeviceSyncService.shared.start(store: store)
                    } else if phase == .background {
                        BackupSyncService.shared.handleDidEnterBackground(
                            ledger: LedgerDiskStore.shared.load()
                        )
                    }
                }
        }
    }
}
