import Foundation
import Security

/// Minimal Keychain wrapper for the one secret we hold: the session token.
enum Keychain {
    private static let service = "com.bravim.TODO-AI"
    private static let account = "session_token"

    static var sessionToken: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let base: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(base as CFDictionary)
            guard let token = newValue else { return }
            var add = base
            add[kSecValueData as String] = Data(token.utf8)
            SecItemAdd(add as CFDictionary, nil)
        }
    }
}
