import Foundation

enum ShortcutRouter {
    private static let pendingTypeKey = "shortcut.pendingTransactionType"

    static func requestAdd(_ type: TransactionType) {
        UserDefaults.standard.set(type.rawValue, forKey: pendingTypeKey)
    }

    static func consumePendingType() -> TransactionType? {
        guard let rawValue = UserDefaults.standard.string(forKey: pendingTypeKey) else {
            return nil
        }
        UserDefaults.standard.removeObject(forKey: pendingTypeKey)
        return TransactionType(rawValue: rawValue)
    }
}

