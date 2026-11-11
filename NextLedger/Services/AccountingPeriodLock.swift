import Foundation

enum AccountingPeriodLock {
    static let enabledKey = "AccountingPeriodLockEnabled"
    static let timestampKey = "AccountingPeriodLockThroughTimestamp"

    static var lockedThroughDate: Date? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: enabledKey) else { return nil }
        let timestamp = defaults.double(forKey: timestampKey)
        guard timestamp > 0 else { return nil }
        return Calendar.current.startOfDay(for: Date(timeIntervalSince1970: timestamp))
    }

    static func isLocked(_ date: Date) -> Bool {
        guard let lockedThroughDate,
              let firstOpenDay = Calendar.current.date(
                byAdding: .day,
                value: 1,
                to: lockedThroughDate
              ) else { return false }
        return date < firstOpenDay
    }

    static func blockedMessage(action: String, date: Date) -> String {
        guard let lockedThroughDate else {
            return "The accounting period is locked."
        }
        return "Cannot \(action) the transaction dated \(date.formatted(date: .abbreviated, time: .omitted)). The accounting period is locked through \(lockedThroughDate.formatted(date: .abbreviated, time: .omitted))."
    }
}
