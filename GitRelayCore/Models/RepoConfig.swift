import Foundation

struct RepoConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var srcURL: String
    var targets: [MirrorTarget]
    var srcAuth: AuthConfig
    var frequency: SyncFrequency
    var destructivePushPolicy: DestructivePushPolicy
    /// Branch used for integrity verification (`refs/heads/<name>`).
    var defaultBranch: String
    var createdAt: Date
    var lastSyncedAt: Date?
    var lastSuccessfulSyncedAt: Date?
    var lastSyncError: String?
    var consecutiveFailureCount: Int
    /// Rolling daily sync outcomes keyed by `yyyy-MM-dd` (kept ≤ 35 days).
    var dailySyncOutcomes: [String: SyncDayOutcome]
    var lastVerifiedAt: Date?
    /// Non-nil when the last integrity check found divergent tree content.
    var divergedDetail: String?
    /// Loose grouping labels; a repo may belong to multiple tags.
    var tags: [String]
    /// When enabled, mirror GitHub/GitLab release metadata and binary assets to each target.
    var mirrorReleases: Bool
    /// Shallow clone depth; nil means full history.
    var depth: Int?
    /// Fetch refspecs; defaults to all heads and tags.
    var refSpecs: [String]
    /// When enabled, push webhooks at `/hook/<id>` can trigger an immediate sync.
    var webhookEnabled: Bool

    static let defaultRefSpecs: [String] = [
        "+refs/heads/*:refs/heads/*",
        "+refs/tags/*:refs/tags/*"
    ]

    var enabledTargets: [MirrorTarget] {
        targets.filter(\.enabled)
    }

    var resolvedRefSpecs: [String] {
        let normalized = Self.normalizedRefSpecs(refSpecs)
        return normalized.isEmpty ? Self.defaultRefSpecs : normalized
    }

    var isShallowClone: Bool {
        guard let depth else { return false }
        return depth > 0
    }

    /// True when sync cannot use full `git push --mirror` (shallow history or ref subset).
    var usesSelectiveRefSync: Bool {
        isShallowClone || !Self.refSpecsEqual(resolvedRefSpecs, Self.defaultRefSpecs)
    }

    var partialSyncWarning: String? {
        guard usesSelectiveRefSync else { return nil }
        if isShallowClone {
            return "A shallow clone cannot perform a complete push --mirror. Only the selected refs will sync, so this is not a complete backup."
        }
        return "Custom ref filters are set. Only the selected refs will sync, so this is not a complete backup."
    }

    static func normalizedRefSpecs(_ raw: [String]) -> [String] {
        raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func refSpecsEqual(_ lhs: [String], _ rhs: [String]) -> Bool {
        normalizedRefSpecs(lhs) == normalizedRefSpecs(rhs)
    }

    init(
        id: UUID = UUID(),
        name: String,
        srcURL: String,
        targets: [MirrorTarget],
        srcAuth: AuthConfig = .sshAgent,
        frequency: SyncFrequency = .manual,
        destructivePushPolicy: DestructivePushPolicy = .strict,
        defaultBranch: String = "main",
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        lastSuccessfulSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        consecutiveFailureCount: Int = 0,
        dailySyncOutcomes: [String: SyncDayOutcome] = [:],
        lastVerifiedAt: Date? = nil,
        divergedDetail: String? = nil,
        tags: [String] = [],
        mirrorReleases: Bool = false,
        depth: Int? = nil,
        refSpecs: [String] = RepoConfig.defaultRefSpecs,
        webhookEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.srcURL = srcURL
        self.targets = targets
        self.srcAuth = srcAuth
        self.frequency = frequency
        self.destructivePushPolicy = destructivePushPolicy
        self.defaultBranch = Self.normalizedBranch(defaultBranch)
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
        self.lastSuccessfulSyncedAt = lastSuccessfulSyncedAt
        self.lastSyncError = lastSyncError
        self.consecutiveFailureCount = max(0, consecutiveFailureCount)
        self.dailySyncOutcomes = dailySyncOutcomes
        self.lastVerifiedAt = lastVerifiedAt
        self.divergedDetail = divergedDetail
        self.tags = RepoTagGrouping.normalizedTags(tags)
        self.mirrorReleases = mirrorReleases
        self.depth = depth.map { max(0, $0) }.flatMap { $0 > 0 ? $0 : nil }
        self.refSpecs = Self.normalizedRefSpecs(refSpecs).isEmpty
            ? Self.defaultRefSpecs
            : Self.normalizedRefSpecs(refSpecs)
        self.webhookEnabled = webhookEnabled
    }

    /// Convenience for tests and single-target call sites.
    init(
        id: UUID = UUID(),
        name: String,
        srcURL: String,
        dstURL: String,
        srcAuth: AuthConfig = .sshAgent,
        dstAuth: AuthConfig = .sshAgent,
        frequency: SyncFrequency = .manual,
        destructivePushPolicy: DestructivePushPolicy = .strict,
        defaultBranch: String = "main",
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        lastSuccessfulSyncedAt: Date? = nil,
        lastSyncError: String? = nil,
        consecutiveFailureCount: Int = 0,
        dailySyncOutcomes: [String: SyncDayOutcome] = [:],
        lastVerifiedAt: Date? = nil,
        divergedDetail: String? = nil,
        tags: [String] = [],
        mirrorReleases: Bool = false,
        depth: Int? = nil,
        refSpecs: [String] = RepoConfig.defaultRefSpecs,
        webhookEnabled: Bool = false
    ) {
        self.init(
            id: id,
            name: name,
            srcURL: srcURL,
            targets: [MirrorTarget(url: dstURL, auth: dstAuth)],
            srcAuth: srcAuth,
            frequency: frequency,
            destructivePushPolicy: destructivePushPolicy,
            defaultBranch: defaultBranch,
            createdAt: createdAt,
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: lastSuccessfulSyncedAt,
            lastSyncError: lastSyncError,
            consecutiveFailureCount: consecutiveFailureCount,
            dailySyncOutcomes: dailySyncOutcomes,
            lastVerifiedAt: lastVerifiedAt,
            divergedDetail: divergedDetail,
            tags: tags,
            mirrorReleases: mirrorReleases,
            depth: depth,
            refSpecs: refSpecs,
            webhookEnabled: webhookEnabled
        )
    }

    /// Path segment used by `POST /hook/<webhookPathID>`.
    var webhookPathID: String {
        WebhookPushMapper.pathID(for: id)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case srcURL
        case targets
        case dstURL
        case srcAuth
        case dstAuth
        case frequency
        case destructivePushPolicy
        case defaultBranch
        case createdAt
        case lastSyncedAt
        case lastSuccessfulSyncedAt
        case lastSyncError
        case consecutiveFailureCount
        case dailySyncOutcomes
        case lastVerifiedAt
        case divergedDetail
        case tags
        case mirrorReleases
        case depth
        case refSpecs
        case webhookEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        srcURL = try container.decode(String.self, forKey: .srcURL)
        srcAuth = try container.decode(AuthConfig.self, forKey: .srcAuth)
        frequency = try container.decode(SyncFrequency.self, forKey: .frequency)
        destructivePushPolicy = try container.decodeIfPresent(
            DestructivePushPolicy.self,
            forKey: .destructivePushPolicy
        ) ?? .auto
        defaultBranch = Self.normalizedBranch(
            try container.decodeIfPresent(String.self, forKey: .defaultBranch) ?? "main"
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        let decodedLastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
        let decodedLastSyncError = try container.decodeIfPresent(String.self, forKey: .lastSyncError)
        lastSyncedAt = decodedLastSyncedAt
        lastSyncError = decodedLastSyncError
        lastSuccessfulSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSyncedAt)
            ?? (decodedLastSyncError == nil ? decodedLastSyncedAt : nil)
        consecutiveFailureCount = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .consecutiveFailureCount)
                ?? (decodedLastSyncError == nil ? 0 : 1)
        )
        dailySyncOutcomes = try container.decodeIfPresent(
            [String: SyncDayOutcome].self,
            forKey: .dailySyncOutcomes
        ) ?? [:]
        lastVerifiedAt = try container.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
        divergedDetail = try container.decodeIfPresent(String.self, forKey: .divergedDetail)
        tags = RepoTagGrouping.normalizedTags(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
        mirrorReleases = try container.decodeIfPresent(Bool.self, forKey: .mirrorReleases) ?? false
        depth = try container.decodeIfPresent(Int.self, forKey: .depth).flatMap { $0 > 0 ? $0 : nil }
        let decodedRefSpecs = try container.decodeIfPresent([String].self, forKey: .refSpecs) ?? []
        refSpecs = Self.normalizedRefSpecs(decodedRefSpecs).isEmpty
            ? Self.defaultRefSpecs
            : Self.normalizedRefSpecs(decodedRefSpecs)
        webhookEnabled = try container.decodeIfPresent(Bool.self, forKey: .webhookEnabled) ?? false

        if let decodedTargets = try container.decodeIfPresent([MirrorTarget].self, forKey: .targets),
           !decodedTargets.isEmpty {
            targets = decodedTargets
        } else {
            let legacyURL = try container.decode(String.self, forKey: .dstURL)
            let legacyAuth = try container.decode(AuthConfig.self, forKey: .dstAuth)
            targets = [MirrorTarget(url: legacyURL, auth: legacyAuth)]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(srcURL, forKey: .srcURL)
        try container.encode(targets, forKey: .targets)
        try container.encode(srcAuth, forKey: .srcAuth)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(destructivePushPolicy, forKey: .destructivePushPolicy)
        try container.encode(defaultBranch, forKey: .defaultBranch)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastSyncedAt, forKey: .lastSyncedAt)
        try container.encodeIfPresent(lastSuccessfulSyncedAt, forKey: .lastSuccessfulSyncedAt)
        try container.encodeIfPresent(lastSyncError, forKey: .lastSyncError)
        try container.encode(consecutiveFailureCount, forKey: .consecutiveFailureCount)
        if !dailySyncOutcomes.isEmpty {
            try container.encode(dailySyncOutcomes, forKey: .dailySyncOutcomes)
        }
        try container.encodeIfPresent(lastVerifiedAt, forKey: .lastVerifiedAt)
        try container.encodeIfPresent(divergedDetail, forKey: .divergedDetail)
        try container.encode(tags, forKey: .tags)
        if mirrorReleases {
            try container.encode(mirrorReleases, forKey: .mirrorReleases)
        }
        try container.encodeIfPresent(depth, forKey: .depth)
        if !Self.refSpecsEqual(refSpecs, Self.defaultRefSpecs) {
            try container.encode(refSpecs, forKey: .refSpecs)
        }
        if webhookEnabled {
            try container.encode(webhookEnabled, forKey: .webhookEnabled)
        }
    }

    mutating func recordSyncResult(at date: Date = .now, error: String?, calendar: Calendar = .current) {
        lastSyncedAt = date
        lastSyncError = error

        if error == nil {
            lastSuccessfulSyncedAt = date
            consecutiveFailureCount = 0
            // Successful mirror push should realign dst with src.
            divergedDetail = nil
        } else {
            consecutiveFailureCount = max(0, consecutiveFailureCount) + 1
        }

        let dayKey = SyncHistorySparkline.dayKey(for: date, calendar: calendar)
        var outcome = dailySyncOutcomes[dayKey] ?? SyncDayOutcome()
        outcome.recordSync(error: error)
        dailySyncOutcomes[dayKey] = outcome
        dailySyncOutcomes = SyncHistorySparkline.pruneDailyOutcomes(
            dailySyncOutcomes,
            keepingDays: 35,
            referenceDate: date,
            calendar: calendar
        )
    }

    mutating func recordVerificationResult(at date: Date = .now, divergedDetail: String?) {
        lastVerifiedAt = date
        self.divergedDetail = divergedDetail
    }

    var isDiverged: Bool { divergedDetail != nil }

    static func normalizedBranch(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "main" }
        if trimmed.hasPrefix("refs/heads/") {
            return String(trimmed.dropFirst("refs/heads/".count))
        }
        return trimmed
    }
}
