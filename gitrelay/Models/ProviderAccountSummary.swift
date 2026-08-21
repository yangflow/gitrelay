import Foundation

/// Read-only view of one labelled provider account for the 账号 panes.
///
/// `hasToken` only records whether a Keychain entry exists; the token itself
/// never leaves `ProviderTokenStore`.
nonisolated struct ProviderAccountSummary: Identifiable, Equatable, Sendable {
    let provider: GitProvider
    let label: String
    let host: String?
    let hasToken: Bool

    var id: String { ProviderAccount.id(provider: provider, label: label) }

    var hostText: String {
        let trimmed = host?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return Self.defaultHost(for: provider)
    }

    var credentialText: String {
        hasToken
            ? String(localized: "Token saved in Keychain")
            : String(localized: "No token saved")
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
        records
            .map {
                ProviderAccountSummary(
                    provider: provider,
                    label: $0.label,
                    host: $0.host,
                    hasToken: hasToken($0.label)
                )
            }
            .sorted { $0.label < $1.label }
    }
}
