import Foundation
import Security

/// The user's Gemini key in the Keychain. The item sits in the App Group's access group, so the keyboard
/// extension reads the same item the app writes. It is readable after the first unlock, because the keyboard
/// runs while the phone is in use, and it never leaves this device (no backup, no iCloud).
enum KeyStore {
    private static let service = "com.ibrokhim.dmtranslator.gemini"
    private static let account = "geminiAPIKey"

    private static var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.id,
        ]
    }

    /// The key the user saved in the app, if any.
    static var userKey: String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8).flatMap(APIKey.normalized)
    }

    /// The key every Gemini request uses.
    static var effectiveKey: String { APIKey.resolve(user: userKey, build: Secrets.geminiAPIKey) }

    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let updated = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw KeyStoreError(status: updated) }
        var add = item
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeyStoreError(status: added) }
    }

    static func delete() {
        SecItemDelete(item as CFDictionary)
    }
}

struct KeyStoreError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Kalitni saqlab bo'lmadi (Keychain \(status))" }
}
