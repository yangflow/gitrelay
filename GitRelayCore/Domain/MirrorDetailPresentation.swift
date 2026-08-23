import Foundation

nonisolated enum MirrorPrimaryAction: Equatable, Sendable {
    case completeSetup
    case startFirstSync
    case cancelQueuedRun
    case cancelSync
    case cancelVerification
    case reconnectCredential(destinationID: UUID?)
    case reviewChanges
    case reviewDivergence
    case retry
    case syncNow
    case resumeSchedule
}

/// Pure state-to-action contract shared by the detail header and decision card.
/// Runtime activity wins over persisted health because it describes what the
/// user can act on at this moment.
nonisolated struct MirrorDetailPresentation: Equatable, Sendable {
    var health: MirrorHealthState
    var activity: MirrorActivityState
    var primaryAction: MirrorPrimaryAction

    static func make(
        mirror: MirrorSnapshot,
        activity: MirrorActivityState,
        staleAfter: Date? = nil
    ) -> MirrorDetailPresentation {
        let health = MirrorHealth.derive(
            plan: mirror.plan,
            snapshot: mirror.health,
            staleAfter: staleAfter
        )

        let resolvedAction: MirrorPrimaryAction
        switch activity {
        case .queued:
            resolvedAction = .cancelQueuedRun
        case .synchronizing:
            resolvedAction = .cancelSync
        case .verifying:
            resolvedAction = .cancelVerification
        case .idle:
            if mirror.needsCredentials {
                resolvedAction = .reconnectCredential(destinationID: mirror.health.lastFailure?.destinationID)
            } else if mirror.plan.isSchedulePaused {
                resolvedAction = .resumeSchedule
            } else {
                resolvedAction = primaryAction(for: health)
            }
        }

        return MirrorDetailPresentation(
            health: health,
            activity: activity,
            primaryAction: resolvedAction
        )
    }

    private static func primaryAction(for health: MirrorHealthState) -> MirrorPrimaryAction {
        switch health {
        case .needsSetup:
            return .completeSetup
        case .neverRun:
            return .startFirstSync
        case .healthy, .stale:
            return .syncNow
        case .diverged:
            return .reviewDivergence
        case .failed(let failure):
            switch failure.kind {
            case .sourceAuthentication, .destinationAuthentication:
                return .reconnectCredential(destinationID: failure.destinationID)
            case .destructiveChangeBlocked:
                return .reviewChanges
            case .sourceUnavailable, .destinationRejected, .network,
                 .localStorage, .cancelled, .unknown:
                return .retry
            }
        }
    }
}
