import Foundation

nonisolated enum MirrorScheduledOperation: String, Equatable, Sendable {
    case sync
    case verification
}

nonisolated struct MirrorSchedulingEnvironment: Equatable, Sendable {
    var globalPauseReason: MirrorGlobalPauseReason?
    var pauseOnLowPower: Bool
    var isLowPowerMode: Bool
    var pauseOnExpensiveNetwork: Bool
    var isExpensiveNetwork: Bool
    var quietHours: QuietHoursSettings

    init(
        globalPauseReason: MirrorGlobalPauseReason? = nil,
        pauseOnLowPower: Bool = false,
        isLowPowerMode: Bool = false,
        pauseOnExpensiveNetwork: Bool = false,
        isExpensiveNetwork: Bool = false,
        quietHours: QuietHoursSettings = .default
    ) {
        self.globalPauseReason = globalPauseReason
        self.pauseOnLowPower = pauseOnLowPower
        self.isLowPowerMode = isLowPowerMode
        self.pauseOnExpensiveNetwork = pauseOnExpensiveNetwork
        self.isExpensiveNetwork = isExpensiveNetwork
        self.quietHours = quietHours
    }
}

nonisolated enum MirrorScheduleEvaluation: Equatable, Sendable {
    case manual
    case mirrorPaused(nextRunAt: Date)
    case globallyPaused(MirrorGlobalPauseReason, nextRunAt: Date)
    case deferred(MirrorGlobalPauseReason, nextRunAt: Date)
    case due(scheduledAt: Date, missedRunCount: Int)
    case scheduled(nextRunAt: Date)

    var runtimeState: MirrorScheduleState {
        switch self {
        case .manual:
            .active(nextRunAt: nil)
        case .mirrorPaused:
            .mirrorPaused
        case .globallyPaused(let reason, _):
            .globallyPaused(reason)
        case .deferred(let reason, _):
            .deferred(reason)
        case .due(let scheduledAt, _):
            .active(nextRunAt: scheduledAt)
        case .scheduled(let nextRunAt):
            .active(nextRunAt: nextRunAt)
        }
    }

    var shouldStartNow: Bool {
        if case .due = self { return true }
        return false
    }
}

nonisolated struct MirrorScheduleSet: Equatable, Sendable {
    var sync: MirrorScheduleEvaluation
    var verification: MirrorScheduleEvaluation
}

/// Pure schedule boundary. It consumes plans and persisted health only;
/// timers and queue admission belong to the Phase 2 scheduling controller.
nonisolated enum MirrorSchedulePlanner {
    static let maximumMissedRuns = 99

    static func evaluate(
        plan: MirrorPlan,
        snapshot: MirrorHealthSnapshot?,
        environment: MirrorSchedulingEnvironment,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MirrorScheduleSet {
        MirrorScheduleSet(
            sync: evaluate(
                operation: .sync,
                plan: plan,
                snapshot: snapshot,
                environment: environment,
                now: now,
                calendar: calendar
            ),
            verification: evaluate(
                operation: .verification,
                plan: plan,
                snapshot: snapshot,
                environment: environment,
                now: now,
                calendar: calendar
            )
        )
    }

    static func evaluate(
        operation: MirrorScheduledOperation,
        plan: MirrorPlan,
        snapshot: MirrorHealthSnapshot?,
        environment: MirrorSchedulingEnvironment,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> MirrorScheduleEvaluation {
        guard let interval = interval(for: operation, plan: plan) else {
            return .manual
        }

        let anchor = anchorDate(for: operation, plan: plan, snapshot: snapshot)
        let nextRunAt = anchor.addingTimeInterval(interval)
        if plan.isSchedulePaused {
            return .mirrorPaused(nextRunAt: nextRunAt)
        }
        if let reason = environment.globalPauseReason {
            return .globallyPaused(reason, nextRunAt: nextRunAt)
        }
        if let reason = deferredReason(
            environment: environment,
            now: now,
            calendar: calendar
        ) {
            return .deferred(reason, nextRunAt: nextRunAt)
        }
        guard nextRunAt <= now else {
            return .scheduled(nextRunAt: nextRunAt)
        }

        let overdue = max(0, now.timeIntervalSince(nextRunAt))
        let missed = min(
            1 + Int(overdue / interval),
            maximumMissedRuns
        )
        return .due(scheduledAt: nextRunAt, missedRunCount: missed)
    }

    private static func interval(
        for operation: MirrorScheduledOperation,
        plan: MirrorPlan
    ) -> TimeInterval? {
        switch operation {
        case .sync:
            plan.policy.frequency.interval
        case .verification:
            plan.policy.verification.frequency.interval
        }
    }

    private static func anchorDate(
        for operation: MirrorScheduledOperation,
        plan: MirrorPlan,
        snapshot: MirrorHealthSnapshot?
    ) -> Date {
        switch operation {
        case .sync:
            snapshot?.lastAttemptAt ?? plan.createdAt
        case .verification:
            snapshot?.lastVerifiedAt ?? plan.createdAt
        }
    }

    private static func deferredReason(
        environment: MirrorSchedulingEnvironment,
        now: Date,
        calendar: Calendar
    ) -> MirrorGlobalPauseReason? {
        if environment.quietHours.contains(now, calendar: calendar) {
            return .quietHours
        }
        let lowPower = environment.pauseOnLowPower && environment.isLowPowerMode
        let expensive = environment.pauseOnExpensiveNetwork && environment.isExpensiveNetwork
        switch (lowPower, expensive) {
        case (true, true):
            return .lowPowerAndExpensiveNetwork
        case (true, false):
            return .lowPower
        case (false, true):
            return .expensiveNetwork
        case (false, false):
            return nil
        }
    }
}
