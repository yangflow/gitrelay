import Foundation

/// Sidebar footer state: run indicator, repo / failure counts, and whether a
/// pause control belongs there at all.
nonisolated struct SidebarFooterSummary: Equatable, Sendable {
    let repoCount: Int
    let failedCount: Int
    /// True when at least one repository syncs on a frequency, so pausing the
    /// schedule is a meaningful action.
    let hasScheduledSync: Bool
    let pauseReason: SyncPauseReason?

    var isPaused: Bool { pauseReason != nil }

    /// Only a manual pause is reversible from the footer; environment pauses
    /// (quiet hours, Low Power Mode, expensive network) clear on their own.
    var showsPauseControl: Bool {
        hasScheduledSync && (pauseReason == nil || pauseReason == .manual)
    }

    var stateText: String {
        pauseReason?.displayMessage ?? String.loc("Running")
    }

    var countsText: String {
        String.loc("\(repoCount) repos · \(failedCount) failed")
    }

    static func make(
        repos: [RepoConfig],
        statuses: [UUID: SyncStatus],
        pauseReason: SyncPauseReason?
    ) -> SidebarFooterSummary {
        let failed = repos.reduce(into: 0) { total, repo in
            if RepoPairTable.statusKind(for: repo, status: statuses[repo.id] ?? .unknown) == .failed {
                total += 1
            }
        }
        return SidebarFooterSummary(
            repoCount: repos.count,
            failedCount: failed,
            hasScheduledSync: repos.contains { $0.frequency != .manual },
            pauseReason: pauseReason
        )
    }
}
