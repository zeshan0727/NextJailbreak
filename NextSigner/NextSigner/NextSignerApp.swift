import SwiftUI

@main
struct NextSignerApp: App {
    @StateObject private var publishLog = PublishLogCenter.shared

    var body: some Scene {
        WindowGroup {
            NextSignerRootView()
                .overlay(alignment: .bottom) {
                    if publishLog.isVisible {
                        PublishLogMiniView(center: publishLog)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 102)
                    }
                }
                .preferredColorScheme(.dark)
        }
    }
}
