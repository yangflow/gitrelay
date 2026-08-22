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
    /// Remote repo IDs the user dismissed with Ignore on the discovery sheet.
    var ignoredDiscoveredRepoIDs: [String]

    init(
        id: UUID = UUID(),
        provider: GitProvider,
        accountLabel: String = "default",
        organizationName: String,
        autoAddEnabled: Bool = false,
        template: OrgSubscriptionTemplate = .default,
        lastCheckedAt: Date? = nil,
        ignoredDiscoveredRepoIDs: [String] = []
    ) {
        self.id = id
        self.provider = provider
        self.accountLabel = accountLabel
        self.organizationName = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.autoAddEnabled = autoAddEnabled
        self.template = template
        self.lastCheckedAt = lastCheckedAt
        self.ignoredDiscoveredRepoIDs = ignoredDiscoveredRepoIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case provider
        case accountLabel
        case organizationName
        case autoAddEnabled
        case template
        case lastCheckedAt
        case ignoredDiscoveredRepoIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        provider = try container.decode(GitProvider.self, forKey: .provider)
        accountLabel = try container.decode(String.self, forKey: .accountLabel)
        organizationName = try container.decode(String.self, forKey: .organizationName)
        autoAddEnabled = try container.decode(Bool.self, forKey: .autoAddEnabled)
        template = try container.decode(OrgSubscriptionTemplate.self, forKey: .template)
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        ignoredDiscoveredRepoIDs = try container.decodeIfPresent(
            [String].self,
            forKey: .ignoredDiscoveredRepoIDs
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(provider, forKey: .provider)
        try container.encode(accountLabel, forKey: .accountLabel)
        try container.encode(organizationName, forKey: .organizationName)
        try container.encode(autoAddEnabled, forKey: .autoAddEnabled)
        try container.encode(template, forKey: .template)
        try container.encodeIfPresent(lastCheckedAt, forKey: .lastCheckedAt)
        try container.encode(ignoredDiscoveredRepoIDs, forKey: .ignoredDiscoveredRepoIDs)
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
