import Foundation

/// One labelled provider account as the 设置 → 安全 list states it: name, host,
/// whether a credential exists, and when it was last used.
///
/// `hasToken` only records whether a Keychain entry exists; the token itself
/// never leaves `ProviderTokenStore`.
nonisolated struct ProviderAccountSummary: Identifiable, Equatable, Sendable {
    let provider: GitProvider
    let label: String
    let host: String?
    let hasToken: Bool
    let lastUsedAt: Date?

    init(
        provider: GitProvider,
        label: String,
        host: String?,
        hasToken: Bool,
        lastUsedAt: Date? = nil
    ) {
        self.provider = provider
        self.label = label
        self.host = host
        self.hasToken = hasToken
        self.lastUsedAt = lastUsedAt
    }

    var id: String { ProviderAccount.id(provider: provider, label: label) }

    var hostText: String {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return Self.defaultHost(for: provider)
    }

    /// Every provider gets a `default` record from migration whether or not
    /// anyone ever put a credential in it. An untouched one is a placeholder,
    /// not an account worth listing.
    var isUntouchedPlaceholder: Bool {
        !hasToken
            && label == ProviderAccount.defaultLabel
            && lastUsedAt == nil
            && (host?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var credentialText: String {
        hasToken
            ? String.loc("Token saved in Keychain")
            : String.loc("No token saved")
    }

    func lastUsed(now: Date = Date()) -> ProviderAccountLastUsed {
        ProviderAccountLastUsed.state(for: lastUsedAt, now: now)
    }

    func lastUsedText(now: Date = Date()) -> String {
        lastUsed(now: now).text
    }

    static func defaultHost(for provider: GitProvider) -> String {
        switch provider {
        case .github: "github.com"
        case .gitlab: "gitlab.com"
        case .gitea:  "gitea.com"
        }
    }

    static func summaries(
        provider: GitProvider,
        records: [ProviderAccountRecord],
        hasToken: (String) -> Bool
    ) -> [ProviderAccountSummary] {
        summaries(
            recordsByProvider: [provider: records],
            hasToken: { _, label in hasToken(label) }
        )
    }

    /// Every saved account across providers, in sidebar order (GitHub, GitLab,
    /// Gitea) and then by name, so the 安全 list has one stable shape whether or
    /// not a provider filter is on.
    static func summaries(
        recordsByProvider: [GitProvider: [ProviderAccountRecord]],
        hasToken: (GitProvider, String) -> Bool
    ) -> [ProviderAccountSummary] {
        recordsByProvider
            .flatMap { provider, records in
                records.map { record in
                    ProviderAccountSummary(
                        provider: provider,
                        label: record.label,
                        host: record.host,
                        hasToken: hasToken(provider, record.label),
                        lastUsedAt: record.lastUsedAt
                    )
                }
            }
            .sorted {
                let left = brandOrder(of: $0.provider)
                let right = brandOrder(of: $1.provider)
                if left != right { return left < right }
                return $0.label < $1.label
            }
    }

    /// Drops the placeholder records so a fresh install shows an empty list
    /// rather than three providers with nothing in them.
    static func listed(_ summaries: [ProviderAccountSummary]) -> [ProviderAccountSummary] {
        summaries.filter { !$0.isUntouchedPlaceholder }
    }

    /// A nil provider means the whole list; the 安全 tab clears its filter chip
    /// by passing nil rather than by rebuilding the list.
    static func filtered(
        _ summaries: [ProviderAccountSummary],
        provider: GitProvider?
    ) -> [ProviderAccountSummary] {
        guard let provider else { return summaries }
        return summaries.filter { $0.provider == provider }
    }

    private static func brandOrder(of provider: GitProvider) -> Int {
        GitProvider.allCases.firstIndex(of: provider) ?? GitProvider.allCases.count
    }
}
