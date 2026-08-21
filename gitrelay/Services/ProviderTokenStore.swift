import Foundation

nonisolated enum ProviderTokenStore {
    static let defaultAccountLabel = ProviderAccount.defaultLabel

    static func legacyTag(for provider: GitProvider) -> String {
        "provider-api-\(provider.rawValue)"
    }

    static func tag(for provider: GitProvider, accountLabel: String = defaultAccountLabel) -> String {
        "provider-api-\(provider.rawValue)-\(accountLabel)"
    }

    static func migrateLegacyTokenIfNeeded(for provider: GitProvider) {
        let legacy = legacyTag(for: provider)
        let migrated = tag(for: provider, accountLabel: defaultAccountLabel)
        guard let token = try? KeychainService.loadToken(tag: legacy) else { return }

        if (try? KeychainService.loadToken(tag: migrated)) == nil {
            try? KeychainService.saveToken(token, tag: migrated)
        }
        try? KeychainService.deleteToken(tag: legacy)
    }

    static func save(token: String, provider: GitProvider, accountLabel: String = defaultAccountLabel) throws {
        try KeychainService.saveToken(token, tag: tag(for: provider, accountLabel: accountLabel))
    }

    static func load(provider: GitProvider, accountLabel: String = defaultAccountLabel) -> String? {
        try? KeychainService.loadToken(tag: tag(for: provider, accountLabel: accountLabel))
    }

    static func delete(provider: GitProvider, accountLabel: String = defaultAccountLabel) {
        try? KeychainService.deleteToken(tag: tag(for: provider, accountLabel: accountLabel))
    }

    /// Loads the default account token, migrating legacy single-account Keychain tags first.
    static func loadDefault(provider: GitProvider) -> String? {
        migrateLegacyTokenIfNeeded(for: provider)
        return load(provider: provider, accountLabel: defaultAccountLabel)
    }
}
