import Foundation

/// A subscribed GitHub organization or GitLab group whose repo list is polled for newcomers.
nonisolated struct OrgSubscription: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var provider: GitProvider
    var accountLabel: String
    var organizationName: String
    /// When true, newly discovered repos are ingested using `template` without prompting.
    var autoAddEnabled: Bool
    var template: OrgSubscriptionTemplate
    var lastCheckedAt: Date?

    init(
        id: UUID = UUID(),
        provider: GitProvider,
        accountLabel: String = "default",
        organizationName: String,
        autoAddEnabled: Bool = false,
        template: OrgSubscriptionTemplate = .default,
        lastCheckedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.accountLabel = accountLabel
        self.organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.autoAddEnabled = autoAddEnabled
        self.template = template
        self.lastCheckedAt = lastCheckedAt
    }

    var scope: RemoteRepoScope {
        .organization(organizationName)
    }
}

/// Global preferences for org/group subscription polling.
nonisolated struct OrgSubscriptionPreferences: Equatable, Codable, Sendable {
    var pollFrequency: OrgSubscriptionPollFrequency
    var notificationsEnabled: Bool

    static let `default` = OrgSubscriptionPreferences(
        pollFrequency: .day1,
        notificationsEnabled: true
    )
}
