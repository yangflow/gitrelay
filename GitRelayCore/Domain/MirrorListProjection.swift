import Foundation

nonisolated enum MirrorListFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case gitDestinations
    case archiveDestinations
    case multipleDestinations

    var id: String { rawValue }
}

nonisolated enum MirrorListSortOrder: String, CaseIterable, Identifiable, Sendable {
    case priority
    case name
    case lastSuccess
    case nextRun

    var id: String { rawValue }
}

nonisolated enum MirrorListHealthKind: Int, Equatable, Sendable {
    case needsCredentials
    case needsSetup
    case failed
    case diverged
    case stale
    case neverRun
    case healthy

    var priority: Int { rawValue }
}

nonisolated enum MirrorListActivity: Equatable, Sendable {
    case queued(position: Int)
    case synchronizing(SyncPhase)
    case verifying
    case paused(MirrorGlobalPauseReason?)
    case lastSuccess(Date)
    case nextRun(Date)
    case manual
}

/// A stable, presentation-ready projection for the persistent list column.
/// Health, live activity, and schedule remain separate so an in-flight run does
/// not erase the last known health result.
nonisolated struct MirrorListRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let sourceLabel: String
    let sourceURL: String
    let sourceProvider: GitProvider?
    let destinationLabel: String
    let destinationURL: String
    let destinationProvider: GitProvider?
    let destinationCount: Int
    let destinationSearchValues: [String]
    let labels: [String]
    let hasGitDestination: Bool
    let hasArchiveDestination: Bool
    let health: MirrorListHealthKind
    let healthDetail: String?
    let activity: MirrorListActivity
    let lastSuccessfulAt: Date?
    let nextRunAt: Date?
}

nonisolated enum MirrorListProjection {
    static let staleInterval: TimeInterval = 24 * 60 * 60

    static func row(
        for mirror: MirrorSnapshot,
        activity: MirrorActivityState,
        schedule: MirrorScheduleState,
        now: Date = .now
    ) -> MirrorListRow {
        let enabled = mirror.plan.enabledDestinations
        let primary = enabled.first ?? mirror.plan.destinations.first
        let health = MirrorHealth.derive(
            plan: mirror.plan,
            snapshot: mirror.health,
            staleAfter: now.addingTimeInterval(-staleInterval)
        )

        return MirrorListRow(
            id: mirror.id,
            name: mirror.name,
            sourceLabel: endpointLabel(mirror.plan.source.url, includeHost: false),
            sourceURL: mirror.plan.source.url,
            sourceProvider: GitRemoteHost.inferredProvider(fromRemoteURL: mirror.plan.source.url),
            destinationLabel: primary.map(destinationLabel) ?? "",
            destinationURL: primary.map(destinationURL) ?? "",
            destinationProvider: primary.flatMap(destinationProvider),
            destinationCount: enabled.count,
            destinationSearchValues: enabled.flatMap {
                [destinationLabel($0), destinationURL($0)]
            },
            labels: mirror.plan.labels,
            hasGitDestination: enabled.contains { destination in
                if case .git = destination.location { return true }
                return false
            },
            hasArchiveDestination: enabled.contains { destination in
                if case .archive = destination.location { return true }
                return false
            },
            health: mirror.needsCredentials ? .needsCredentials : healthKind(health),
            healthDetail: healthDetail(health),
            activity: activityPresentation(
                activity: activity,
                schedule: schedule,
                lastSuccessfulAt: mirror.health.lastSuccessfulAt
            ),
            lastSuccessfulAt: mirror.health.lastSuccessfulAt,
            nextRunAt: nextRunAt(schedule)
        )
    }

    static func filter(
        _ rows: [MirrorListRow],
        searchText: String,
        filter: MirrorListFilter
    ) -> [MirrorListRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return rows.filter { row in
            matchesSearch(row, query: query) && matchesFilter(row, filter: filter)
        }
    }

    static func sort(
        _ rows: [MirrorListRow],
        order: MirrorListSortOrder
    ) -> [MirrorListRow] {
        rows.enumerated().sorted { lhs, rhs in
            switch order {
            case .priority:
                if lhs.element.health.priority != rhs.element.health.priority {
                    return lhs.element.health.priority < rhs.element.health.priority
                }
                return lhs.offset < rhs.offset
            case .name:
                let comparison = lhs.element.name.localizedStandardCompare(rhs.element.name)
                return comparison == .orderedSame
                    ? lhs.offset < rhs.offset
                    : comparison == .orderedAscending
            case .lastSuccess:
                let left = lhs.element.lastSuccessfulAt ?? .distantPast
                let right = rhs.element.lastSuccessfulAt ?? .distantPast
                return left == right ? lhs.offset < rhs.offset : left > right
            case .nextRun:
                let left = lhs.element.nextRunAt ?? .distantFuture
                let right = rhs.element.nextRunAt ?? .distantFuture
                return left == right ? lhs.offset < rhs.offset : left < right
            }
        }.map(\.element)
    }

    private static func matchesSearch(_ row: MirrorListRow, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return row.name.localizedCaseInsensitiveContains(query)
            || row.sourceLabel.localizedCaseInsensitiveContains(query)
            || row.sourceURL.localizedCaseInsensitiveContains(query)
            || row.destinationLabel.localizedCaseInsensitiveContains(query)
            || row.destinationURL.localizedCaseInsensitiveContains(query)
            || row.destinationSearchValues.contains {
                $0.localizedCaseInsensitiveContains(query)
            }
            || row.labels.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func matchesFilter(
        _ row: MirrorListRow,
        filter: MirrorListFilter
    ) -> Bool {
        switch filter {
        case .all:
            true
        case .gitDestinations:
            row.hasGitDestination
        case .archiveDestinations:
            row.hasArchiveDestination
        case .multipleDestinations:
            row.destinationCount > 1
        }
    }

    private static func healthKind(_ health: MirrorHealthState) -> MirrorListHealthKind {
        switch health {
        case .needsSetup: .needsSetup
        case .neverRun: .neverRun
        case .healthy: .healthy
        case .stale: .stale
        case .failed: .failed
        case .diverged: .diverged
        }
    }

    private static func healthDetail(_ health: MirrorHealthState) -> String? {
        switch health {
        case .failed(let failure): failure.message
        case .diverged(let detail): detail
        case .needsSetup, .neverRun, .healthy, .stale: nil
        }
    }

    private static func activityPresentation(
        activity: MirrorActivityState,
        schedule: MirrorScheduleState,
        lastSuccessfulAt: Date?
    ) -> MirrorListActivity {
        switch activity {
        case .queued(let position):
            .queued(position: position)
        case .synchronizing(let phase, _):
            .synchronizing(phase)
        case .verifying:
            .verifying
        case .idle:
            switch schedule {
            case .mirrorPaused:
                .paused(nil)
            case .globallyPaused(let reason), .deferred(let reason):
                .paused(reason)
            case .active(let nextRunAt):
                if let lastSuccessfulAt {
                    .lastSuccess(lastSuccessfulAt)
                } else if let nextRunAt {
                    .nextRun(nextRunAt)
                } else {
                    .manual
                }
            }
        }
    }

    private static func nextRunAt(_ schedule: MirrorScheduleState) -> Date? {
        guard case .active(let nextRunAt) = schedule else { return nil }
        return nextRunAt
    }

    private static func endpointLabel(_ remoteURL: String, includeHost: Bool) -> String {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path = GitRemoteRepoPath.parse(from: trimmed) else { return trimmed }
        guard includeHost, let host = GitRemoteHost.host(from: trimmed) else {
            return path.pathWithNamespace
        }
        return "\(host)/\(path.pathWithNamespace)"
    }

    private static func destinationLabel(_ destination: MirrorDestination) -> String {
        switch destination.location {
        case .git(let endpoint): endpointLabel(endpoint.url, includeHost: true)
        case .archive(let archive): archive.directoryPath
        }
    }

    private static func destinationURL(_ destination: MirrorDestination) -> String {
        switch destination.location {
        case .git(let endpoint): endpoint.url
        case .archive(let archive): archive.directoryPath
        }
    }

    private static func destinationProvider(_ destination: MirrorDestination) -> GitProvider? {
        guard case .git(let endpoint) = destination.location else { return nil }
        return endpoint.provider ?? GitRemoteHost.inferredProvider(fromRemoteURL: endpoint.url)
    }
}
