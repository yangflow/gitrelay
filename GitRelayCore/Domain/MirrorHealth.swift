import Foundation

nonisolated enum MirrorHealth {
    static func derive(
        plan: MirrorPlan,
        snapshot: MirrorHealthSnapshot?,
        staleAfter: Date? = nil
    ) -> MirrorHealthState {
        guard !plan.destinations.isEmpty,
              !plan.enabledDestinations.isEmpty,
              (try? plan.source.validate(role: .source)) != nil
        else {
            return .needsSetup
        }

        guard let snapshot else {
            return .neverRun
        }

        if case .diverged(let detail) = snapshot.integrity {
            return .diverged(detail)
        }
        if let failure = snapshot.lastFailure {
            if let lastSuccessfulAt = snapshot.lastSuccessfulAt {
                if failure.failedAt >= lastSuccessfulAt {
                    return .failed(failure)
                }
            } else {
                return .failed(failure)
            }
        }
        guard let lastSuccessfulAt = snapshot.lastSuccessfulAt else {
            return .neverRun
        }
        if let staleAfter, lastSuccessfulAt < staleAfter {
            return .stale(since: lastSuccessfulAt)
        }
        return .healthy
    }
}
