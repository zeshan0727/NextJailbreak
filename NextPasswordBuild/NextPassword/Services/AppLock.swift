import Foundation
import LocalAuthentication

@MainActor
final class AppLock: ObservableObject {
    @Published var isUnlocked = false

    func unlock() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return
        }
        do {
            isUnlocked = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Next Password"
            )
        } catch {
            isUnlocked = false
        }
    }
}
