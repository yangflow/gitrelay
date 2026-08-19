import Foundation

/// Keychain account tags for per-repo webhook HMAC secrets.
nonisolated enum WebhookSecretStore {
    static func keychainTag(repoID: UUID) -> String {
        "\(repoID.uuidString.lowercased())-webhook-hmac"
    }

    static func loadSecret(repoID: UUID) -> String? {
        try? KeychainService.loadToken(tag: keychainTag(repoID: repoID))
    }

    static func saveSecret(_ secret: String, repoID: UUID) throws {
        try KeychainService.saveToken(secret, tag: keychainTag(repoID: repoID))
    }

    static func deleteSecret(repoID: UUID) {
        try? KeychainService.deleteToken(tag: keychainTag(repoID: repoID))
    }

    /// Ensures a secret exists when webhook is enabled; returns the secret (existing or newly generated).
    @discardableResult
    static func ensureSecret(repoID: UUID) throws -> String {
        if let existing = loadSecret(repoID: repoID), !existing.isEmpty {
            return existing
        }
        let generated = WebhookHMACVerifier.generateSecret()
        try saveSecret(generated, repoID: repoID)
        return generated
    }
}
