import Foundation

enum ProviderTokenStore {
    static func tag(for provider: GitProvider) -> String {
        "provider-api-\(provider.rawValue)"
    }

    static func save(token: String, provider: GitProvider) throws {
        try KeychainService.saveToken(token, tag: tag(for: provider))
    }

    static func load(provider: GitProvider) -> String? {
        try? KeychainService.loadToken(tag: tag(for: provider))
    }

    static func delete(provider: GitProvider) {
        try? KeychainService.deleteToken(tag: tag(for: provider))
    }
}
