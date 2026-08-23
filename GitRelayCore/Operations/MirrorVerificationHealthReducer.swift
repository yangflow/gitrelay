import Foundation

nonisolated enum MirrorVerificationHealthReducer {
    static func applying(
        _ record: MirrorRunRecord,
        to current: MirrorHealthSnapshot?,
        plan: MirrorPlan
    ) -> MirrorHealthSnapshot {
        var snapshot = current ?? MirrorHealthSnapshot(mirrorID: plan.id)
        guard record.kind == .verification, record.outcome != .cancelled else {
            return snapshot
        }

        let completedAt = record.finishedAt ?? record.startedAt
        snapshot.lastVerifiedAt = completedAt

        let diverged = record.verificationResults.compactMap { result -> String? in
            guard case .diverged(let message) = result.integrity else { return nil }
            return message
        }
        let inconclusive = record.verificationResults.compactMap { result -> String? in
            guard case .inconclusive(let message) = result.integrity else { return nil }
            return message
        }

        if !diverged.isEmpty {
            snapshot.integrity = .diverged(Self.summary(diverged))
        } else if !inconclusive.isEmpty {
            snapshot.integrity = .inconclusive(Self.summary(inconclusive))
        } else if !record.verificationResults.isEmpty,
                  record.verificationResults.allSatisfy({ $0.integrity == .verified }) {
            snapshot.integrity = .verified
        } else if let failure = record.failure {
            snapshot.integrity = .inconclusive(failure.message)
        } else {
            snapshot.integrity = .inconclusive("Verification produced no destination result.")
        }

        var destinationStates: [UUID: MirrorDestinationHealthSnapshot] = [:]
        for destination in snapshot.destinations {
            destinationStates[destination.destinationID] = destination
        }
        for result in record.verificationResults {
            var destination = destinationStates[result.destinationID]
                ?? MirrorDestinationHealthSnapshot(destinationID: result.destinationID)
            destination.lastVerifiedAt = result.completedAt
            destination.integrity = result.integrity
            destinationStates[result.destinationID] = destination
        }
        snapshot.destinations = plan.destinations.compactMap { destinationStates[$0.id] }
        return snapshot
    }

    private static func summary(_ messages: [String]) -> String {
        let unique = Array(Set(messages)).sorted()
        guard unique.count > 1 else { return unique[0] }
        return unique.joined(separator: "; ")
    }
}
