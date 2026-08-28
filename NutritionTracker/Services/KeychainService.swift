import Foundation
import Security

// Stores session tokens in the Keychain (not UserDefaults). Access + refresh.
enum KeychainService {
    private static let service = "com.nutrition.tracker.auth"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        // Delete the old value, then add the new one.
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // ThisDeviceOnly: session tokens must NOT ride an encrypted iCloud/iTunes backup
            // onto another device — a restored device would inherit a live session.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Convenience keys
    static let accessKey = "accessToken"
    static let refreshKey = "refreshToken"

    static func clearAll() {
        delete(accessKey)
        delete(refreshKey)
    }
}
