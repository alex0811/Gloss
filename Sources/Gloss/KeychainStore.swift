import Foundation
import Security

/// API key 只进 Keychain（generic password），不落 UserDefaults / 明文文件。
/// 每个服务商档案一个 account（apiKey.<uuid>），互不覆盖。
enum KeychainStore {
    private static let service = "com.zfanchor.gloss"
    /// 多档案之前的单一账户名，只在迁移时还会用到。
    static let legacyAccount = "apiKey"

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else {
            return delete(account: account)
        }
        let data = Data(value.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, update)
        if status == errSecItemNotFound {
            var query = baseQuery(account: account)
            query[kSecValueData as String] = data
            return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
