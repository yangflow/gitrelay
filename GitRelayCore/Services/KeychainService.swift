import Foundation
import Security

nonisolated enum KeychainError: LocalizedError {
    case saveFailure(OSStatus)
    case loadFailure(OSStatus)
    case deleteFailure(OSStatus)
    case dataConversionFailure

    var errorDescription: String? {
        switch self {
        case .saveFailure(let s):   return "Keychain save failed (OSStatus \(s))"
        case .loadFailure(let s):   return "Keychain load failed (OSStatus \(s))"
        case .deleteFailure(let s): return "Keychain delete failed (OSStatus \(s))"
        case .dataConversionFailure: return "Token data encoding failed"
        }
    }
}

nonisolated struct KeychainService {
    private static let service = Constants.bundleID

    static func saveToken(_ token: String, tag: String) throws {
        guard let data = token.data(using: .utf8) else { throw KeychainError.dataConversionFailure }
        try? deleteToken(tag: tag)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tag,
            kSecValueData:   data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailure(status) }
    }

    static func loadToken(tag: String) throws -> String {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tag,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { throw KeychainError.loadFailure(status) }
        guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.dataConversionFailure
        }
        return token
    }

    static func deleteToken(tag: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: tag
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailure(status)
        }
    }
}
