import Foundation
import Security

/// Tokens are never stored in UserDefaults or written to application logs.
enum Keychain {
    private static let service = "com.nextsolution.appforge.secrets"

    static func read(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func write(_ value: String, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if value.isEmpty {
            let result = SecItemDelete(query as CFDictionary)
            guard result == errSecSuccess || result == errSecItemNotFound else {
                throw ForgeError.message("Cannot delete Keychain entry: \(result)")
            }
            return
        }
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var record = query
            record.merge(attributes) { _, new in new }
            guard SecItemAdd(record as CFDictionary, nil) == errSecSuccess else {
                throw ForgeError.message("Could not save secret in Keychain")
            }
        } else if status != errSecSuccess {
            throw ForgeError.message("Could not update Keychain: \(status)")
        }
    }
}
