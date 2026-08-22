import Foundation

/// The destination host's API, resolved from a plain Git URL: which provider it
/// is, which repository path it names, and which saved account token can act
/// there. Used by the add sheet's preflight to tell a missing destination from a
/// refused credential, and to create the empty repository when asked.
nonisolated struct DestinationRepoPlan: Sendable {
    let provider: GitProvider
    let host: String
    let path: GitRemoteRepoPath
    let apiBaseURL: URL
    let token: String

    var hasToken: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// nil when the URL names no host or repository path. A plan without a token
    /// is still returned so the caller can explain what is missing.
    @MainActor
    static func make(destinationURL: String, defaults: UserDefaults = .standard) -> DestinationRepoPlan? {
        let trimmed = destinationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let host = GitRemoteHost.host(from: trimmed),
              !host.isEmpty,
              let path = GitRemoteRepoPath.parse(from: trimmed),
              !path.name.isEmpty
        else { return nil }

        let provider = GitRemoteHost.inferredProvider(from: host)
        guard let apiBaseURL = ProviderAPIBaseURL.resolve(provider: provider, host: host) else { return nil }

        return DestinationRepoPlan(
            provider: provider,
            host: host,
            path: path,
            apiBaseURL: apiBaseURL,
            token: ProviderHostToken.resolve(provider: provider, host: host, defaults: defaults) ?? ""
        )
    }

    /// Existence check through the provider API, which separates 404 from 401
    /// far more reliably than `ls-remote` can. `.skipped` when no token is
    /// available, so the caller can fall back to git.
    func probeExistence() async -> AddPreflightProbeResult {
        guard hasToken else { return .skipped }
        do {
            switch try await client().fetchRepo(path: path) {
            case .found:
                return .reachable
            case .missing:
                return .missing
            }
        } catch let error as TargetProviderAPIError {
            switch error {
            case .unauthorized, .forbidden:
                return .authenticationFailed
            case .network:
                return .unreachable
            case .validation, .decoding, .http:
                return .skipped
            }
        } catch {
            return .skipped
        }
    }

    /// Creates the empty destination repository, or reports the one already there.
    func createEmptyRepo(isPrivate: Bool = true) async throws -> TargetCreateOutcome {
        try await client().createRepo(
            name: path.name,
            namespace: path.namespace.isEmpty ? .currentUser : .organization(path.namespace),
            isPrivate: isPrivate,
            description: nil
        )
    }

    private func client() -> any TargetProviderAPIClient {
        switch provider {
        case .github:
            return GitHubTargetAPIClient(baseURL: apiBaseURL, token: token)
        case .gitlab:
            return GitLabTargetAPIClient(baseURL: apiBaseURL, token: token)
        case .gitea:
            return GiteaTargetAPIClient(baseURL: apiBaseURL, token: token)
        }
    }

}

/// Picks the saved account token that fits a host: the account pinned to that
/// host first, then the account currently selected for the provider, then the
/// default one. Tokens stay in the Keychain; only the value travels.
enum ProviderHostToken {
    static func resolve(
        provider: GitProvider,
        host: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        guard let label = resolveLabel(provider: provider, host: host, defaults: defaults) else {
            return nil
        }
        return nonEmptyToken(provider: provider, label: label)
    }

    /// The account whose token ``resolve`` would use, by label. Nil when no
    /// account for this provider holds a token, which is what lets the 账号 line
    /// on repo detail stay quiet instead of naming a credential that is absent.
    static func resolveLabel(
        provider: GitProvider,
        host: String,
        defaults: UserDefaults = .standard
    ) -> String? {
        let wanted = normalizedHost(host)
        let accounts = ProviderAccountStore.accounts(for: provider, defaults: defaults)

        if let pinned = accounts.first(where: { normalizedHost($0.host ?? "") == wanted }),
           nonEmptyToken(provider: provider, label: pinned.label) != nil {
            return pinned.label
        }
        let selected = ProviderAccountStore.selectedLabel(for: provider, defaults: defaults)
        if nonEmptyToken(provider: provider, label: selected) != nil {
            return selected
        }
        guard nonEmptyToken(provider: provider, label: ProviderAccount.defaultLabel) != nil else {
            return nil
        }
        return ProviderAccount.defaultLabel
    }

    /// Strips scheme, trailing slashes, and an API suffix so `https://gitlab.example.com/`
    /// and `gitlab.example.com` compare equal.
    static func normalizedHost(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "" }
        for prefix in ["https://", "http://"] where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        return value
    }

    private static func nonEmptyToken(provider: GitProvider, label: String) -> String? {
        guard let token = ProviderTokenStore.load(provider: provider, accountLabel: label),
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return token
    }
}
