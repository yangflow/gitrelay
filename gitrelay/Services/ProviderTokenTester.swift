import Foundation

/// Runs one live check against a provider using a saved account's token.
///
/// The token is read from the Keychain, handed to a client, and dropped. It is
/// never returned, logged, or copied, so 测试 can only ever report what the
/// provider said about it.
enum ProviderTokenTester {
    static func run(
        provider: GitProvider,
        accountLabel: String,
        host: String?
    ) async -> ProviderTokenTestOutcome {
        let result = await probe(provider: provider, accountLabel: accountLabel, host: host)
        let outcome = ProviderTokenTest.outcome(probe: result, provider: provider)
        if outcome.marksAccountUsed {
            ProviderAccountStore.markUsed(for: provider, label: accountLabel)
        }
        return outcome
    }

    static func probe(
        provider: GitProvider,
        accountLabel: String,
        host: String?
    ) async -> ProviderTokenProbe {
        guard let stored = ProviderTokenStore.load(provider: provider, accountLabel: accountLabel) else {
            return .noToken
        }
        let token = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return .noToken }

        let baseURL = ProviderAPIBaseURL.resolveOrDefault(provider: provider, host: host)
        do {
            let scopes = try await fetchScopes(provider: provider, token: token, baseURL: baseURL)
            // 测试 asks the provider rather than the scope cache, and leaves the
            // fresh answer behind for the flows that do read the cache.
            ProviderTokenScopeCache.save(
                key: ProviderTokenScopeCache.cacheKey(provider: provider, token: token, baseURL: baseURL),
                scopes: scopes
            )
            return .scopes(scopes)
        } catch {
            return .refused(rejection(for: error))
        }
    }

    static func rejection(for error: Error) -> ProviderTokenRejection {
        if let error = error as? ProviderAPIError {
            switch error {
            case .unauthorized:
                return .unauthorized
            case .forbidden:
                return .forbidden
            case .notFound:
                return .notFound
            case .network:
                return .network
            case .decoding:
                return .unreadableResponse
            case .http:
                return .httpError
            }
        }
        if let error = error as? TargetProviderAPIError {
            switch error {
            case .unauthorized:
                return .unauthorized
            case .forbidden:
                return .forbidden
            case .network:
                return .network
            case .decoding:
                return .unreadableResponse
            case .validation, .http:
                return .httpError
            }
        }
        if error is URLError {
            return .network
        }
        return .unknown
    }

    private static func fetchScopes(
        provider: GitProvider,
        token: String,
        baseURL: URL
    ) async throws -> Set<String> {
        switch provider {
        case .github:
            return try await GitHubAPIClient(token: token).fetchTokenScopes()
        case .gitlab:
            return try await GitLabAPIClient(token: token, baseURL: baseURL).fetchTokenScopes()
        case .gitea:
            // Gitea only ever acts as a target here, so its token is checked the
            // same way the browse-remote target step checks one.
            return try await GiteaTargetAPIClient(baseURL: baseURL, token: token).fetchTokenScopes()
        }
    }
}
