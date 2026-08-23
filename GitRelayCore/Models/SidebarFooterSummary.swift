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
        guard hasScheduledSync else { return false }
        switch pauseReason {
        case nil, .manual: return true
        default: return false
        }
    }

    var stateText: String {
        pauseReason?.displayMessage ?? String(localized: "Running")
    }

    var countsText: String {
        String(localized: "\(repoCount) mirrors · \(failedCount) failed")
    }

    static func make(
        repos: [MirrorSnapshot],
        statuses: [UUID: SyncStatus],
        pauseReason: SyncPauseReason?
    ) -> SidebarFooterSummary {
        let failed = repos.reduce(into: 0) { total, repo in
            if MirrorSummaryProjection.statusKind(for: repo, status: statuses[repo.id] ?? .unknown) == .failed {
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
