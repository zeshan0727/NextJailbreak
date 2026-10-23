import SwiftUI

/// Exactly five root tabs are registered with iOS, avoiding the system-generated
/// sixth-tab "More" controller. The two secondary tools live inside this explicit tab.
struct MoreView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Picker("More features", selection: $state.moreSection) {
                Label("Downloads", systemImage: "arrow.down.circle")
                    .tag(ForgeMoreSection.downloads)
                Label("AI Support", systemImage: "bubble.left.and.wrench.bubble.right")
                    .tag(ForgeMoreSection.support)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if state.moreSection == .downloads {
                DownloadsView()
                    .id(ForgeMoreSection.downloads)
            } else {
                SupportView()
                    .id(ForgeMoreSection.support)
            }
        }
    }
}
