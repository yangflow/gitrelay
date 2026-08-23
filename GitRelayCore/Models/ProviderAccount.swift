import Foundation

/// A labeled credential context for a Git provider (personal, work, etc.).
nonisolated struct ProviderAccount: Hashable, Codable, Identifiable, Sendable {
    let provider: GitProvider
    let label: String

    var id: String { Self.id(provider: provider, label: label) }

    static let defaultLabel = "default"

    static func id(provider: GitProvider, label: String) -> String {
        "\(provider.rawValue)-\(label)"
    }

    /// Normalizes user input into a stable account label suitable for Keychain tags.
    static func normalizeLabel(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 32 else { return nil }

        let slug = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        guard !slug.isEmpty,
              slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        else { return nil }

        return slug
    }
}

/// One saved account as it is persisted: its label, the host it talks to, and
/// when its token last reached that host.
///
/// The token itself lives in the Keychain under ``ProviderTokenStore``; nothing
/// here ever carries it.
nonisolated struct ProviderAccountRecord: Codable, Hashable, Sendable {
    var label: String
    var host: String?
    /// Absent for an account whose token has never been exercised.
    var lastUsedAt: Date?

    init(label: String, host: String? = nil, lastUsedAt: Date? = nil) {
        self.label = label
        self.host = host
        self.lastUsedAt = lastUsedAt
    }
}

nonisolated enum ConnectionAccountSelection {
    /// Returns a normalized label when `raw` is valid and not already used.
    static func validatedNewLabel(_ raw: String, existing: [String]) -> String? {
        guard let label = ProviderAccount.normalizeLabel(raw) else { return nil }
        guard !existing.contains(label) else { return nil }
        return label
    }

    static func canDeleteAccount(accountCount: Int) -> Bool {
        accountCount > 1
    }

    static func selectedLabelAfterDelete(
        deleted: String,
        current: String,
        remaining: [String]
    ) -> String {
        guard !remaining.isEmpty else { return ProviderAccount.defaultLabel }
        if current == deleted {
            return remaining.contains(ProviderAccount.defaultLabel)
                ? ProviderAccount.defaultLabel
                : remaining[0]
        }
        return current
    }
}
