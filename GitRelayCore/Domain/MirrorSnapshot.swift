import Foundation

/// Non-persisted application query model for one mirror.
///
/// Configuration and operational state remain separate on disk. Views and
/// feature helpers receive this value when they need both at the same time.
nonisolated struct MirrorSnapshot: Identifiable, Equatable, Sendable {
    var plan: MirrorPlan
    var health: MirrorHealthSnapshot
    var needsCredentials: Bool

    init(
        plan: MirrorPlan,
        health: MirrorHealthSnapshot? = nil,
        needsCredentials: Bool = false
    ) {
        self.plan = plan
        self.health = health ?? MirrorHealthSnapshot(mirrorID: plan.id)
        self.health.mirrorID = plan.id
        self.needsCredentials = needsCredentials
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
        lfsMirrorMode: LFSMirrorMode = .auto,
        depth: Int? = nil,
        refSpecs: [String] = MirrorContentPolicy.completeRefSpecs,
        webhookEnabled: Bool = false,
        verificationFrequency: VerificationFrequency = .manual,
        needsCredentials: Bool = false,
        scheduledSyncPaused: Bool = false
    ) {
        let failure = lastSyncError.map {
            MirrorFailureSummary(kind: .unknown, message: $0, failedAt: lastSyncedAt ?? createdAt)
        }
        self.init(
            plan: MirrorPlan(
                id: id,
                name: name,
                source: GitEndpoint(url: srcURL, auth: srcAuth),
                destinations: targets.map { Self.destination(from: $0) },
                policy: MirrorPolicy(
                    frequency: frequency,
                    destructivePush: destructivePushPolicy,
                    content: MirrorContentPolicy(
                        lfsMode: lfsMirrorMode,
                        mirrorsReleases: mirrorReleases,
                        depth: depth,
                        refSpecs: refSpecs
                    ),
                    triggers: MirrorTriggerPolicy(webhookEnabled: webhookEnabled),
                    verification: MirrorVerificationPolicy(
                        frequency: verificationFrequency,
                        branch: defaultBranch
                    )
                ),
                labels: tags,
                createdAt: createdAt,
                isSchedulePaused: scheduledSyncPaused
            ),
            health: MirrorHealthSnapshot(
                mirrorID: id,
                lastAttemptAt: lastSyncedAt,
                lastSuccessfulAt: lastSuccessfulSyncedAt,
                lastFailure: failure,
                consecutiveFailures: consecutiveFailureCount,
                lastVerifiedAt: lastVerifiedAt,
                integrity: divergedDetail.map(MirrorIntegrityState.diverged) ?? .unknown,
                dailyOutcomes: dailySyncOutcomes
            ),
            needsCredentials: needsCredentials
        )
    }

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
        lfsMirrorMode: LFSMirrorMode = .auto,
        depth: Int? = nil,
        refSpecs: [String] = MirrorContentPolicy.completeRefSpecs,
        webhookEnabled: Bool = false,
        verificationFrequency: VerificationFrequency = .manual,
        needsCredentials: Bool = false,
        scheduledSyncPaused: Bool = false
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
            lfsMirrorMode: lfsMirrorMode,
            depth: depth,
            refSpecs: refSpecs,
            webhookEnabled: webhookEnabled,
            verificationFrequency: verificationFrequency,
            needsCredentials: needsCredentials,
            scheduledSyncPaused: scheduledSyncPaused
        )
    }

    var id: UUID {
        get { plan.id }
        set {
            plan.id = newValue
            health.mirrorID = newValue
        }
    }

    var name: String {
        get { plan.name }
        set { plan.name = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var srcURL: String {
        get { plan.source.url }
        set { plan.source.url = newValue.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    var srcAuth: AuthConfig {
        get { plan.source.auth }
        set { plan.source.auth = newValue }
    }

    var targets: [MirrorTarget] {
        get { plan.destinations.map(Self.target(from:)) }
        set {
            let current = Dictionary(uniqueKeysWithValues: plan.destinations.map { ($0.id, $0) })
            plan.destinations = newValue.map { target in
                Self.destination(from: target, preserving: current[target.id])
            }
        }
    }

    var enabledTargets: [MirrorTarget] { targets.filter(\.enabled) }

    var frequency: SyncFrequency {
        get { plan.policy.frequency }
        set { plan.policy.frequency = newValue }
    }

    var destructivePushPolicy: DestructivePushPolicy {
        get { plan.policy.destructivePush }
        set { plan.policy.destructivePush = newValue }
    }

    var defaultBranch: String {
        get { plan.policy.verification.branch }
        set { plan.policy.verification.branch = newValue }
    }

    var createdAt: Date {
        get { plan.createdAt }
        set { plan.createdAt = newValue }
    }

    var tags: [String] {
        get { plan.labels }
        set { plan.labels = MirrorPlan.normalizedLabels(newValue) }
    }

    var mirrorReleases: Bool {
        get { plan.policy.content.mirrorsReleases }
        set { plan.policy.content.mirrorsReleases = newValue }
    }

    var lfsMirrorMode: LFSMirrorMode {
        get { plan.policy.content.lfsMode }
        set { plan.policy.content.lfsMode = newValue }
    }

    var depth: Int? {
        get { plan.policy.content.depth }
        set { plan.policy.content.depth = newValue.flatMap { $0 > 0 ? $0 : nil } }
    }

    var refSpecs: [String] {
        get { plan.policy.content.refSpecs }
        set {
            let normalized = Self.normalizedRefSpecs(newValue)
            plan.policy.content.refSpecs = normalized.isEmpty ? Self.defaultRefSpecs : normalized
        }
    }

    var webhookEnabled: Bool {
        get { plan.policy.triggers.webhookEnabled }
        set { plan.policy.triggers.webhookEnabled = newValue }
    }

    var scheduledSyncPaused: Bool {
        get { plan.isSchedulePaused }
        set { plan.isSchedulePaused = newValue }
    }

    var lastSyncedAt: Date? {
        get { health.lastAttemptAt }
        set { health.lastAttemptAt = newValue }
    }

    var lastSuccessfulSyncedAt: Date? {
        get { health.lastSuccessfulAt }
        set { health.lastSuccessfulAt = newValue }
    }

    var lastSyncError: String? {
        get { health.lastFailure?.message }
        set {
            health.lastFailure = newValue.map {
                MirrorFailureSummary(kind: .unknown, message: $0, failedAt: health.lastAttemptAt ?? .now)
            }
        }
    }

    var consecutiveFailureCount: Int {
        get { health.consecutiveFailures }
        set { health.consecutiveFailures = max(0, newValue) }
    }

    var dailySyncOutcomes: [String: SyncDayOutcome] {
        get { health.dailyOutcomes }
        set { health.dailyOutcomes = newValue }
    }

    var lastVerifiedAt: Date? {
        get { health.lastVerifiedAt }
        set { health.lastVerifiedAt = newValue }
    }

    var divergedDetail: String? {
        get {
            guard case .diverged(let detail) = health.integrity else { return nil }
            return detail
        }
        set {
            if let newValue {
                health.integrity = .diverged(newValue)
            } else if case .diverged = health.integrity {
                health.integrity = health.lastVerifiedAt == nil ? .unknown : .verified
            }
        }
    }

    var isDiverged: Bool { divergedDetail != nil }

    static let defaultRefSpecs = MirrorContentPolicy.completeRefSpecs

    var resolvedRefSpecs: [String] {
        let normalized = Self.normalizedRefSpecs(refSpecs)
        return normalized.isEmpty ? Self.defaultRefSpecs : normalized
    }

    var isShallowClone: Bool { depth.map { $0 > 0 } ?? false }

    var usesSelectiveRefSync: Bool {
        isShallowClone || !Self.refSpecsEqual(resolvedRefSpecs, Self.defaultRefSpecs)
    }

    var partialSyncWarning: String? {
        guard usesSelectiveRefSync else { return nil }
        if isShallowClone {
            return String(localized: "A shallow clone cannot perform a complete push --mirror. Only the selected refs will sync, so this is not a complete backup.")
        }
        return String(localized: "Custom ref filters are set. Only the selected refs will sync, so this is not a complete backup.")
    }

    var webhookPathID: String { WebhookPushMapper.pathID(for: id) }

    mutating func recordSyncResult(
        at date: Date = .now,
        error: String?,
        calendar: Calendar = .current
    ) {
        health.lastAttemptAt = date
        if let error {
            health.lastFailure = MirrorFailureSummary(kind: .unknown, message: error, failedAt: date)
            health.consecutiveFailures += 1
        } else {
            health.lastSuccessfulAt = date
            health.lastFailure = nil
            health.consecutiveFailures = 0
            if case .diverged = health.integrity { health.integrity = .unknown }
        }

        let dayKey = SyncHistorySparkline.dayKey(for: date, calendar: calendar)
        var outcome = health.dailyOutcomes[dayKey] ?? SyncDayOutcome()
        outcome.recordSync(error: error)
        health.dailyOutcomes[dayKey] = outcome
        health.dailyOutcomes = SyncHistorySparkline.pruneDailyOutcomes(
            health.dailyOutcomes,
            keepingDays: 35,
            referenceDate: date,
            calendar: calendar
        )
    }

    mutating func recordVerificationResult(at date: Date = .now, divergedDetail: String?) {
        health.lastVerifiedAt = date
        health.integrity = divergedDetail.map(MirrorIntegrityState.diverged) ?? .verified
    }

    static func normalizedRefSpecs(_ raw: [String]) -> [String] {
        MirrorContentPolicy.normalizedRefSpecs(raw)
    }

    static func refSpecsEqual(_ lhs: [String], _ rhs: [String]) -> Bool {
        normalizedRefSpecs(lhs) == normalizedRefSpecs(rhs)
    }

    static func normalizedBranch(_ raw: String) -> String {
        MirrorVerificationPolicy(branch: raw).branch
    }

    private static func destination(
        from target: MirrorTarget,
        preserving current: MirrorDestination? = nil
    ) -> MirrorDestination {
        switch target.kind {
        case .gitRemote:
            let currentEndpoint: GitEndpoint?
            if case .git(let endpoint) = current?.location {
                currentEndpoint = endpoint
            } else {
                currentEndpoint = nil
            }
            return .git(
                id: target.id,
                url: target.url,
                auth: target.auth,
                provider: currentEndpoint?.provider,
                accountLabel: currentEndpoint?.accountLabel,
                isEnabled: target.enabled
            )
        case .filesystem:
            return .archive(
                id: target.id,
                directoryPath: target.filesystemPath ?? target.url,
                format: target.resolvedArchiveFormat,
                filenameTemplate: target.resolvedFilenameTemplate(),
                retentionCount: target.retentionCount,
                isEnabled: target.enabled
            )
        }
    }

    private static func target(from destination: MirrorDestination) -> MirrorTarget {
        switch destination.location {
        case .git(let endpoint):
            return MirrorTarget(
                id: destination.id,
                url: endpoint.url,
                auth: endpoint.auth,
                enabled: destination.isEnabled
            )
        case .archive(let archive):
            return MirrorTarget(
                id: destination.id,
                kind: .filesystem,
                enabled: destination.isEnabled,
                filesystemPath: archive.directoryPath,
                archiveFormat: archive.format,
                filenameTemplate: archive.filenameTemplate,
                retentionCount: archive.retentionCount
            )
        }
    }
}
