import Foundation

/// The 账号 line under a pair's URLs: which saved provider account the pair's
/// remotes authenticate with. There is no account id on ``RepoConfig``, so the
/// name is resolved the same way the token is — the account pinned to that host,
/// then the provider's selected account, then the default one. When none of them
/// holds a token the line stays away rather than naming a credential GitRelay
/// does not have.
nonisolated struct RepoAccountLine: Equatable, Sendable {
    /// Account names in reading order: source first, then each remote target.
    let names: [String]

    var text: String {
        String.loc("Account · \(names.joined(separator: " · "))")
    }

    /// Nil when nothing was resolved, which is the quiet case.
    static func make(names: [String]) -> RepoAccountLine? {
        var distinct: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !distinct.contains(trimmed) else { continue }
            distinct.append(trimmed)
        }
        guard !distinct.isEmpty else { return nil }
        return RepoAccountLine(names: distinct)
    }

    /// GitHub 工作 for a labelled account; the provider alone for the default
    /// one, where the label (default) would say nothing.
    static func displayName(provider: GitProvider, label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ProviderAccount.defaultLabel else {
            return provider.shortName
        }
        return "\(provider.shortName) \(trimmed)"
    }

    @MainActor
    static func resolve(for repo: RepoConfig, defaults: UserDefaults = .standard) -> RepoAccountLine? {
        var names: [String] = []
        if let name = accountName(forRemote: repo.srcURL, defaults: defaults) {
            names.append(name)
        }
        for target in repo.targets where target.kind == .gitRemote {
            if let name = accountName(forRemote: target.url, defaults: defaults) {
                names.append(name)
            }
        }
        return make(names: names)
    }

    @MainActor
    static func accountName(forRemote remoteURL: String, defaults: UserDefaults = .standard) -> String? {
        guard let host = GitRemoteHost.host(from: remoteURL), !host.isEmpty else { return nil }
        let provider = GitRemoteHost.inferredProvider(from: host)
        guard let label = ProviderHostToken.resolveLabel(
            provider: provider,
            host: host,
            defaults: defaults
        ) else { return nil }
        return displayName(provider: provider, label: label)
    }
}
