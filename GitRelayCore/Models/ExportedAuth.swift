import Foundation

/// Auth metadata safe to write into a portable config export (no secrets).
struct ExportedAuth: Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case sshAgent
        case sshKey
        case httpsToken
    }

    var kind: Kind
    /// Included only when the path is not an absolute / home-relative machine-local path.
    var privateKeyPath: String?

    init(kind: Kind, privateKeyPath: String? = nil) {
        self.kind = kind
        self.privateKeyPath = privateKeyPath
    }

    static func from(_ auth: AuthConfig) -> ExportedAuth {
        switch auth {
        case .sshAgent:
            return ExportedAuth(kind: .sshAgent)
        case .sshKey(let path):
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || Self.isMachineLocalPath(trimmed) {
                return ExportedAuth(kind: .sshKey)
            }
            return ExportedAuth(kind: .sshKey, privateKeyPath: trimmed)
        case .httpsToken:
            // Keychain tags and token values are never exported.
            return ExportedAuth(kind: .httpsToken)
        }
    }

    /// Rebuilds runtime auth. HTTPS tags use the standard repo/target conventions.
    func toAuthConfig(keychainTag: String) -> AuthConfig {
        switch kind {
        case .sshAgent:
            return .sshAgent
        case .sshKey:
            if let privateKeyPath, !privateKeyPath.isEmpty {
                return .sshKey(privateKeyPath: privateKeyPath)
            }
            return .sshKey(privateKeyPath: "")
        case .httpsToken:
            return .httpsToken(keychainTag: keychainTag)
        }
    }

    static func isMachineLocalPath(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~")
    }
}
