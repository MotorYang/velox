import Foundation
import LocalAuthentication
import Security

enum KeychainManager {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain operation failed with status \(status)."
            case .invalidData:
                return "The keychain item did not contain valid data."
            }
        }
    }

    static func savePassword(_ password: String, account: String, service: String = Bundle.main.bundleIdentifier ?? "Velox") throws {
        guard let data = password.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        try save(data, account: account, service: service)
    }

    static func readPassword(
        account: String,
        service: String = Bundle.main.bundleIdentifier ?? "Velox",
        reason: String = "Velox needs your permission to read this server secret."
    ) throws -> String? {
        guard let data = try readData(account: account, service: service, reason: reason) else {
            return nil
        }

        guard let password = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return password
    }

    static func save(_ data: Data, account: String, service: String = Bundle.main.bundleIdentifier ?? "Velox") throws {
        let query = baseQuery(account: account, service: service)
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessControl as String] = try accessControl()

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func readData(
        account: String,
        service: String = Bundle.main.bundleIdentifier ?? "Velox",
        reason: String = "Velox needs your permission to read this server secret."
    ) throws -> Data? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = authenticationContext(reason: reason)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidData
        }

        return data
    }

    static func delete(account: String, service: String = Bundle.main.bundleIdentifier ?? "Velox") throws {
        let status = SecItemDelete(baseQuery(account: account, service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service
        ]
    }

    private static func accessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &error
        ) else {
            throw error?.takeRetainedValue() ?? KeychainError.invalidData
        }

        return control
    }

    private static func authenticationContext(reason: String) -> LAContext {
        let context = LAContext()
        context.localizedReason = reason
        return context
    }
}
