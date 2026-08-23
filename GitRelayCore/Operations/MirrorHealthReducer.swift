import Foundation

nonisolated enum MirrorHealthReducer {
    static func applying(
        _ record: MirrorRunRecord,
        to current: MirrorHealthSnapshot?,
        plan: MirrorPlan,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> MirrorHealthSnapshot {
        guard record.kind == .sync else {
            return current ?? MirrorHealthSnapshot(mirrorID: plan.id)
        }
        let completedAt = record.finishedAt ?? record.startedAt
        var snapshot = current ?? MirrorHealthSnapshot(mirrorID: plan.id)
        snapshot.lastAttemptAt = completedAt

        let succeeded = record.outcome == .succeeded
        if succeeded {
            snapshot.lastSuccessfulAt = completedAt
            snapshot.lastFailure = nil
            snapshot.consecutiveFailures = 0
            if case .diverged = snapshot.integrity {
                snapshot.integrity = .unknown
            }
        } else {
            snapshot.lastFailure = record.failure ?? record.destinationResults
                .compactMap(\.failure)
                .first
            snapshot.consecutiveFailures = max(0, snapshot.consecutiveFailures) + 1
        }

        let dayKey = SyncHistorySparkline.dayKey(for: completedAt, calendar: calendar)
        var outcome = snapshot.dailyOutcomes[dayKey] ?? SyncDayOutcome()
        if succeeded {
            outcome.successes += 1
        } else {
            outcome.failures += 1
        }
        snapshot.dailyOutcomes[dayKey] = outcome
        snapshot.dailyOutcomes = SyncHistorySparkline.pruneDailyOutcomes(
            snapshot.dailyOutcomes,
            keepingDays: 35,
            referenceDate: completedAt,
            calendar: calendar
        )

        var destinationStates: [UUID: MirrorDestinationHealthSnapshot] = [:]
        for destination in snapshot.destinations {
            destinationStates[destination.destinationID] = destination
        }
        for result in record.destinationResults {
            var destination = destinationStates[result.destinationID]
                ?? MirrorDestinationHealthSnapshot(destinationID: result.destinationID)
            destination.lastAttemptAt = result.completedAt ?? completedAt
            if result.succeeded {
                destination.lastSuccessfulAt = result.completedAt ?? completedAt
                destination.lastFailure = nil
            } else {
                destination.lastFailure = result.failure
            }
            destinationStates[result.destinationID] = destination
        }
        snapshot.destinations = plan.destinations.compactMap { destinationStates[$0.id] }
        return snapshot
    }
}
