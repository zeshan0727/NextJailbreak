import SwiftUI

@main
struct GeneratedAppApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("Next IPA Factory")
                    .font(.title.bold())
                Text("Generated application compilation smoke test")
                    .font(.subheadline)
            }.padding()
        }
    }
}
