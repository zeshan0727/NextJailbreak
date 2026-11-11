import Foundation
import UserNotifications

final class BudgetNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BudgetNotificationService()

    static func configure() {
        UNUserNotificationCenter.current().delegate = shared
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    static func notifyEightyPercent(
        budget: ExpenseBudget,
        spent: Decimal
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(budget.displayName) reached 80%"
        content.body = "You have spent \(DisplayFormat.currency(spent, code: budget.currencyCode)) of \(DisplayFormat.currency(budget.monthlyAmount, code: budget.currencyCode)) in the current budget cycle."
        content.sound = .default

        let month = Calendar.current.dateComponents([.year, .month], from: Date())
        let identifier = [
            "nextledger-budget",
            budget.id.uuidString,
            String(month.year ?? 0),
            String(month.month ?? 0)
        ].joined(separator: "-")
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
