import SwiftUI

struct RepoStatusSectionView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let isSyncing: Bool
    let records: [SyncRecord]
    let nextFireDate: Date?
    let onSyncNow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSyncing {
                RepoSyncingRowView(
                    latestLogLine: records.last?.logLines.last,
                    onCancel: onCancel
                )
            } else if case .failed(let message) = status {
                RepoFailureRowView(
                    message: message,
                    lastSyncedAt: repo.lastSyncedAt,
                    onRetry: onSyncNow
                )
            } else {
                RepoIdleRowView(
                    status: status,
                    lastSyncedAt: repo.lastSyncedAt,
                    nextFireDate: nextFireDate,
                    onSyncNow: onSyncNow
                )
            }
        }
    }
}
