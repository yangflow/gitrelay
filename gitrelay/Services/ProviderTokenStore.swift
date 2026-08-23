import Foundation

nonisolated enum ProviderTokenStore {
    static let defaultAccountLabel = ProviderAccount.defaultLabel

    static func tag(for provider: GitProvider, accountLabel: String = defaultAccountLabel) -> String {
        "gitrelay-provider-\(provider.rawValue)-\(accountLabel)"
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

    static func loadDefault(provider: GitProvider) -> String? {
        return load(provider: provider, accountLabel: defaultAccountLabel)
    }
}
