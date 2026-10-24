import SwiftUI

/// Exactly five root tabs are registered with iOS, avoiding the system-generated
/// sixth-tab "More" controller. Secondary tools live inside this explicit tab.
struct MoreView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Picker("More features", selection: $state.moreSection) {
                Label("My Apps", systemImage: "square.stack.3d.up")
                    .tag(ForgeMoreSection.myApps)
                Label("Downloads", systemImage: "arrow.down.circle")
                    .tag(ForgeMoreSection.downloads)
                Label("AI Support", systemImage: "bubble.left.and.wrench.bubble.right")
                    .tag(ForgeMoreSection.support)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 4)

            switch state.moreSection {
            case .myApps:
                MyAppsView()
                    .id(ForgeMoreSection.myApps)
            case .downloads:
                DownloadsView()
                    .id(ForgeMoreSection.downloads)
            case .support:
                SupportView()
                    .id(ForgeMoreSection.support)
            }
        }
    }
}
