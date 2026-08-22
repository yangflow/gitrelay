import Foundation

/// Turns a host as a person types it — bare, with a scheme, with a trailing
/// slash, or with the API suffix already on the end — into an API root.
nonisolated enum ProviderAPIBaseURL {
    /// The path each provider's API hangs off its host. GitHub Enterprise
    /// answers under `/api/v3`; github.com itself answers on `api.github.com`,
    /// which ``resolve`` special-cases.
    static func apiSuffix(for provider: GitProvider) -> String {
        switch provider {
        case .github: "/api/v3"
        case .gitlab: "/api/v4"
        case .gitea:  "/api/v1"
        }
    }

    /// Nil when there is no host to work from, so callers can decide between
    /// falling back to the provider default and reporting the gap.
    ///
    /// A scheme the caller typed is kept, so a self-hosted instance reachable
    /// only over plain HTTP stays reachable.
    static func resolve(provider: GitProvider, host: String?) -> URL? {
        guard var value = host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }

        if !value.hasPrefix("http://"), !value.hasPrefix("https://") {
            value = "https://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }

        let suffix = apiSuffix(for: provider)
        if value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
            while value.hasSuffix("/") { value.removeLast() }
        }

        if provider == .github, isGitHubDotCom(value) {
            return GitProvider.github.apiBaseURL
        }
        return URL(string: value + suffix)
    }

    static func resolveOrDefault(provider: GitProvider, host: String?) -> URL {
        resolve(provider: provider, host: host) ?? provider.apiBaseURL
    }

    private static func isGitHubDotCom(_ value: String) -> Bool {
        var bare = value.lowercased()
        for prefix in ["https://", "http://"] where bare.hasPrefix(prefix) {
            bare.removeFirst(prefix.count)
        }
        return bare == "github.com" || bare == "www.github.com" || bare == "api.github.com"
    }
}
