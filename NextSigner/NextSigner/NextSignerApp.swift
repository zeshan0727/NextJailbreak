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
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: publishLog.isVisible)
                .preferredColorScheme(.dark)
        }
    }
}
