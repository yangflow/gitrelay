import Foundation

/// One scheduled repository's next expected fire, recorded when its timer is armed.
/// `Timer` does not fire while the machine sleeps, so comparing this against the
/// wall clock after wake is the only way to know a run was missed.
nonisolated struct ScheduledRunExpectation: Equatable, Sendable {
    let repoID: UUID
    let interval: TimeInterval
    let expectedFireDate: Date

    init(repoID: UUID, interval: TimeInterval, expectedFireDate: Date) {
        self.repoID = repoID
        self.interval = interval
        self.expectedFireDate = expectedFireDate
    }
}

nonisolated enum MissedScheduledRuns {
    /// A single sleep never counts more than this per repository, so a laptop
    /// left closed for a week still reports a number a human can read.
    static let maxMissedRunsPerRepo = 99

    struct Outcome: Equatable, Sendable {
        /// Repos whose next fire is already in the past, in the order given.
        var dueRepoIDs: [UUID] = []
        /// Fires the schedule slept through across those repos.
        var missedRunCount: Int = 0

        var hasMissedRuns: Bool { missedRunCount > 0 }
    }

    static func evaluate(
        expectations: [ScheduledRunExpectation],
        now: Date
    ) -> Outcome {
        var outcome = Outcome()
        for expectation in expectations {
            guard expectation.interval > 0 else { continue }
            let overdue = now.timeIntervalSince(expectation.expectedFireDate)
            guard overdue >= 0 else { continue }
            outcome.dueRepoIDs.append(expectation.repoID)
            outcome.missedRunCount += missedRuns(overdue: overdue, interval: expectation.interval)
        }
        return outcome
    }

    /// The due fire itself counts as one, plus every whole interval since.
    private static func missedRuns(overdue: TimeInterval, interval: TimeInterval) -> Int {
        let elapsedIntervals = overdue / interval
        guard elapsedIntervals < Double(maxMissedRunsPerRepo) else {
            return maxMissedRunsPerRepo
        }
        return min(1 + Int(elapsedIntervals), maxMissedRunsPerRepo)
    }
}

/// The one-shot catch-up started after wake, so the menu bar can show a line
/// while it drains and drop it once the last repo settles (#107).
nonisolated struct MissedRunCatchUpProgress: Equatable, Sendable {
    private(set) var missedRunCount = 0
    private(set) var pendingRepoIDs: Set<UUID> = []

    var isCatchingUp: Bool { missedRunCount > 0 && !pendingRepoIDs.isEmpty }

    mutating func begin(missedRunCount: Int, repoIDs: [UUID]) {
        let ids = Set(repoIDs)
        guard missedRunCount > 0, !ids.isEmpty else {
            reset()
            return
        }
        self.missedRunCount = missedRunCount
        pendingRepoIDs = ids
    }

    mutating func noteFinished(repoID: UUID) {
        pendingRepoIDs.remove(repoID)
        if pendingRepoIDs.isEmpty {
            missedRunCount = 0
        }
    }

    mutating func reset() {
        missedRunCount = 0
        pendingRepoIDs.removeAll()
    }
}
