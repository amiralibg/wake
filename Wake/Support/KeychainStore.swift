import Foundation
import Security

/// Minimal generic-password Keychain wrapper for secrets like API keys.
enum KeychainStore {
    private static let service = "app.wake.Wake"

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }
}

/// The Brave Search key, read from the Keychain once and then kept in memory: the
/// palette asks for it on every keystroke, and a Keychain query costs a round trip
/// to securityd.
@MainActor
enum SearchKeyStore {
    private static let account = "search.brave"
    private static var cached: String??

    static var braveAPIKey: String? {
        get {
            if let cached { return cached }
            let key = KeychainStore.string(for: account)
            cached = .some(key)
            return key
        }
        set {
            KeychainStore.set(newValue, for: account)
            cached = .some(newValue?.isEmpty == false ? newValue : nil)
        }
    }

    static var hasBraveAPIKey: Bool { braveAPIKey != nil }
}
