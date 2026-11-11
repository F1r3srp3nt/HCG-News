#if canImport(Security)
import Foundation
import Security
import HCGTransport

/// Stores the HCG Connect session as one generic-password Keychain item.
///
/// - Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not in
///   backups, never synchronised to iCloud Keychain, never migrates to another device).
/// - Service is specific to HCG News so it never collides with HCG ONE or CardX items.
public struct KeychainSessionStore: ConnectSessionStoring {
    public enum KeychainError: Error, Equatable { case status(Int32) }

    private let service: String
    private let account: String

    public init(service: String = "com.hakmicapitalgroup.hcgnews.connect", account: String = "session") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    public func load() throws -> ConnectSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return try HCGJSON.makeDecoder().decode(ConnectSession.self, from: data)
    }

    public func save(_ session: ConnectSession) throws {
        let data = try HCGJSON.makeEncoder().encode(session)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}
#endif
