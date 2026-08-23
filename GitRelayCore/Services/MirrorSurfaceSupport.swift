import Foundation

nonisolated enum MirrorSurfaceStatus: String, Codable, Equatable, Sendable {
    case needsSetup
    case notRun
    case healthy
    case stale
    case failed
    case diverged
    case queued
    case syncing
    case verifying
    case paused

}

nonisolated struct MirrorSurfaceSnapshot: Codable, Equatable, Sendable, Identifiable {
    var mirrorID: UUID
    var mirrorName: String
    var status: MirrorSurfaceStatus
    var lastSuccessfulAt: Date?
    var message: String?

    var id: UUID { mirrorID }
}

nonisolated enum MirrorSurfaceLookupError: Error, Equatable, LocalizedError, Sendable {
    case emptyQuery
    case notFound(String)
    case ambiguousName(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            "A mirror name or identifier is required."
        case .notFound(let query):
            "No mirror matching \"\(query)\" was found."
        case .ambiguousName(let name):
            "More than one mirror is named \"\(name)\". Use its identifier instead."
        }
    }
}

/// Shared, read-only projection used by CLI, App Intents, widgets, and webhook routing.
/// These surfaces consume plans and health snapshots without recreating product state rules.
nonisolated enum MirrorSurfaceSupport {
    static func mirror(matching query: String, in plans: [MirrorPlan]) throws -> MirrorPlan {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MirrorSurfaceLookupError.emptyQuery }

        if let identifier = UUID(uuidString: trimmed),
           let exact = plans.first(where: { $0.id == identifier }) {
            return exact
        }

        let matches = plans.filter {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard !matches.isEmpty else { throw MirrorSurfaceLookupError.notFound(trimmed) }
        guard matches.count == 1 else { throw MirrorSurfaceLookupError.ambiguousName(trimmed) }
        return matches[0]
    }

    static func snapshot(
        plan: MirrorPlan,
        health: MirrorHealthSnapshot?,
        activity: MirrorActivityState = .idle,
        schedule: MirrorScheduleState = .active(nextRunAt: nil),
        staleAfter: Date? = nil
    ) -> MirrorSurfaceSnapshot {
        let projection: (MirrorSurfaceStatus, String?)

        switch activity {
        case .queued:
            projection = (.queued, nil)
        case .synchronizing:
            projection = (.syncing, nil)
        case .verifying:
            projection = (.verifying, nil)
        case .idle:
            switch schedule {
            case .mirrorPaused, .globallyPaused:
                projection = (.paused, nil)
            case .active, .deferred:
                projection = healthProjection(
                    MirrorHealth.derive(plan: plan, snapshot: health, staleAfter: staleAfter)
                )
            }
        }

        return MirrorSurfaceSnapshot(
            mirrorID: plan.id,
            mirrorName: plan.name,
            status: projection.0,
            lastSuccessfulAt: health?.lastSuccessfulAt,
            message: projection.1.map(SyncEngine.redactCredentials)
        )
    }

    static func isAttention(_ snapshot: MirrorSurfaceSnapshot) -> Bool {
        switch snapshot.status {
        case .needsSetup, .notRun, .stale, .failed, .diverged:
            true
        case .healthy, .queued, .syncing, .verifying, .paused:
            false
        }
    }

    private static func healthProjection(
        _ health: MirrorHealthState
    ) -> (MirrorSurfaceStatus, String?) {
        switch health {
        case .needsSetup:
            (.needsSetup, nil)
        case .neverRun:
            (.notRun, nil)
        case .healthy:
            (.healthy, nil)
        case .stale:
            (.stale, nil)
        case .failed(let failure):
            (.failed, failure.message)
        case .diverged(let detail):
            (.diverged, detail)
        }
    }
}
