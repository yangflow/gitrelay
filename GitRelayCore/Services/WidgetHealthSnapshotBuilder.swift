import Foundation

enum WidgetHealthSnapshotBuilder {
    static let defaultAttentionLimit = 3

    static func make(
        repos: [RepoConfig],
        statuses: [UUID: SyncStatus],
        inProgressSyncIDs: Set<UUID>,
        now: Date = .now,
        calendar: Calendar = .current,
        attentionLimit: Int = defaultAttentionLimit
    ) -> WidgetHealthSnapshot {
        let summary = SyncHealthSummary.make(
            repos: repos,
            statuses: statuses,
            now: now,
            calendar: calendar
        )
        let attentionRepos = attentionRepos(
            repos: repos,
            statuses: statuses,
            inProgressSyncIDs: inProgressSyncIDs,
            now: now,
            limit: attentionLimit
        )

        return WidgetHealthSnapshot(
            updatedAt: now,
            summary: WidgetHealthSummaryPayload(summary: summary),
            attentionRepos: attentionRepos
        )
    }

    static func attentionRepos(
        repos: [RepoConfig],
        statuses: [UUID: SyncStatus],
        inProgressSyncIDs: Set<UUID>,
        now: Date = .now,
        limit: Int = defaultAttentionLimit
    ) -> [WidgetAttentionRepo] {
        guard limit > 0 else { return [] }

        return repos
            .map { repo in
                let snapshot = RepoIntentSupport.makeSnapshot(
                    repo: repo,
                    runtimeStatus: statuses[repo.id],
                    isSyncInProgress: inProgressSyncIDs.contains(repo.id)
                )
                let rank = attentionRank(for: repo, snapshot: snapshot, now: now)
                return (repo: repo, snapshot: snapshot, rank: rank)
            }
            .sorted { $0.rank < $1.rank }
            .prefix(limit)
            .map { entry in
                WidgetAttentionRepo(
                    id: entry.repo.id,
                    name: entry.snapshot.repoName,
                    status: entry.snapshot.status,
                    lastSyncedAt: entry.snapshot.lastSyncedAt,
                    message: entry.snapshot.message
                )
            }
    }

    private struct AttentionRank: Comparable {
        let tier: Int
        let tiebreaker: TimeInterval

        static func < (lhs: AttentionRank, rhs: AttentionRank) -> Bool {
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            return lhs.tiebreaker < rhs.tiebreaker
        }
    }

    private static func attentionRank(
        for repo: RepoConfig,
        snapshot: RepoSyncStatusSnapshot,
        now: Date
    ) -> AttentionRank {
        switch snapshot.status {
        case .failure:
            return AttentionRank(
                tier: 0,
                tiebreaker: -(snapshot.lastSyncedAt ?? repo.createdAt).timeIntervalSince1970
            )
        case .diverged:
            return AttentionRank(
                tier: 1,
                tiebreaker: -(snapshot.lastSyncedAt ?? repo.createdAt).timeIntervalSince1970
            )
        case .syncing:
            return AttentionRank(
                tier: 2,
                tiebreaker: -(snapshot.lastSyncedAt ?? now).timeIntervalSince1970
            )
        case .queued:
            return AttentionRank(
                tier: 2,
                tiebreaker: -(snapshot.lastSyncedAt ?? now).timeIntervalSince1970 - 0.5
            )
        case .unknown:
            let reference = repo.lastSuccessfulSyncedAt ?? repo.lastSyncedAt ?? repo.createdAt
            return AttentionRank(
                tier: 3,
                tiebreaker: reference.timeIntervalSince1970
            )
        case .success:
            if RepoRowHealthPresentation.isStale(for: repo, now: now) {
                let reference = repo.lastSuccessfulSyncedAt ?? repo.createdAt
                return AttentionRank(
                    tier: 4,
                    tiebreaker: reference.timeIntervalSince1970
                )
            }
            return AttentionRank(
                tier: 5,
                tiebreaker: -(repo.lastSuccessfulSyncedAt ?? now).timeIntervalSince1970
            )
        }
    }
}
