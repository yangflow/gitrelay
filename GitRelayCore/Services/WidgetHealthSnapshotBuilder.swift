import Foundation

enum WidgetHealthSnapshotBuilder {
    static let defaultAttentionLimit = 3

    static func make(
        plans: [MirrorPlan],
        health: [UUID: MirrorHealthSnapshot],
        activities: [UUID: MirrorActivityState] = [:],
        schedules: [UUID: MirrorScheduleState] = [:],
        now: Date = .now,
        calendar: Calendar = .current,
        attentionLimit: Int = defaultAttentionLimit
    ) -> WidgetHealthSnapshot {
        let dayKey = SyncHistorySparkline.dayKey(for: now, calendar: calendar)
        var succeededToday = 0
        var failedToday = 0
        var notRunToday = 0

        for plan in plans {
            let mirrorHealth = health[plan.id]
            let outcome = mirrorHealth?.dailyOutcomes[dayKey]
            if (outcome?.failures ?? 0) > 0 {
                failedToday += 1
            } else if (outcome?.successes ?? 0) > 0 {
                succeededToday += 1
            } else if let failure = mirrorHealth?.lastFailure,
                      calendar.isDate(failure.failedAt, inSameDayAs: now),
                      mirrorHealth?.lastSuccessfulAt.map({ failure.failedAt >= $0 }) ?? true {
                failedToday += 1
            } else if let success = mirrorHealth?.lastSuccessfulAt,
                      calendar.isDate(success, inSameDayAs: now) {
                succeededToday += 1
            } else {
                notRunToday += 1
            }
        }

        return WidgetHealthSnapshot(
            updatedAt: now,
            summary: WidgetHealthSummaryPayload(
                succeededToday: succeededToday,
                failedToday: failedToday,
                notRunToday: notRunToday
            ),
            attentionMirrors: attentionMirrors(
                plans: plans,
                health: health,
                activities: activities,
                schedules: schedules,
                now: now,
                limit: attentionLimit
            )
        )
    }

    static func attentionMirrors(
        plans: [MirrorPlan],
        health: [UUID: MirrorHealthSnapshot],
        activities: [UUID: MirrorActivityState] = [:],
        schedules: [UUID: MirrorScheduleState] = [:],
        now: Date = .now,
        limit: Int = defaultAttentionLimit
    ) -> [WidgetAttentionMirror] {
        guard limit > 0 else { return [] }
        let staleAfter = now.addingTimeInterval(-24 * 60 * 60)

        return plans
            .map { plan -> (MirrorSurfaceSnapshot, AttentionRank) in
                let mirrorHealth = health[plan.id]
                let snapshot = MirrorSurfaceSupport.snapshot(
                    plan: plan,
                    health: mirrorHealth,
                    activity: activities[plan.id] ?? .idle,
                    schedule: schedules[plan.id] ?? .active(nextRunAt: nil),
                    staleAfter: staleAfter
                )
                return (
                    snapshot,
                    attentionRank(
                        snapshot,
                        health: mirrorHealth,
                        createdAt: plan.createdAt,
                        now: now
                    )
                )
            }
            .filter { MirrorSurfaceSupport.isAttention($0.0) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { entry in
                WidgetAttentionMirror(
                    id: entry.0.mirrorID,
                    name: entry.0.mirrorName,
                    status: widgetStatus(entry.0.status),
                    lastSyncedAt: health[entry.0.mirrorID]?.lastAttemptAt ?? entry.0.lastSuccessfulAt,
                    message: entry.0.message
                )
            }
    }

    private struct AttentionRank: Comparable {
        let tier: Int
        let tiebreaker: TimeInterval

        static func < (lhs: AttentionRank, rhs: AttentionRank) -> Bool {
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            return lhs.tiebreaker < rhs.tiebreaker
        }
    }

    private static func attentionRank(
        _ snapshot: MirrorSurfaceSnapshot,
        health: MirrorHealthSnapshot?,
        createdAt: Date,
        now: Date
    ) -> AttentionRank {
        let reference = snapshot.lastSuccessfulAt ?? createdAt
        switch snapshot.status {
        case .failed:
            let failureAt = health?.lastFailure?.failedAt ?? health?.lastAttemptAt ?? reference
            return AttentionRank(tier: 0, tiebreaker: -failureAt.timeIntervalSince1970)
        case .diverged:
            let verificationAt = health?.lastVerifiedAt ?? reference
            return AttentionRank(tier: 1, tiebreaker: -verificationAt.timeIntervalSince1970)
        case .needsSetup:
            return AttentionRank(tier: 2, tiebreaker: reference.timeIntervalSince1970)
        case .notRun:
            return AttentionRank(tier: 3, tiebreaker: reference.timeIntervalSince1970)
        case .stale:
            return AttentionRank(tier: 4, tiebreaker: reference.timeIntervalSince1970)
        case .healthy, .queued, .syncing, .verifying, .paused:
            return AttentionRank(tier: 5, tiebreaker: now.timeIntervalSince1970)
        }
    }

    private static func widgetStatus(_ status: MirrorSurfaceStatus) -> MirrorWidgetStatus {
        switch status {
        case .healthy: .success
        case .failed: .failure
        case .diverged: .diverged
        case .queued: .queued
        case .syncing, .verifying: .syncing
        case .stale: .success
        case .needsSetup, .notRun, .paused: .unknown
        }
    }

}
