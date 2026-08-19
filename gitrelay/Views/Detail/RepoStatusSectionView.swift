import SwiftUI

struct RepoStatusSectionView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let isSyncing: Bool
    let isVerifying: Bool
    let records: [SyncRecord]
    let nextFireDate: Date?
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void
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
                    lastSuccessfulSyncedAt: repo.lastSuccessfulSyncedAt,
                    consecutiveFailureCount: repo.consecutiveFailureCount,
                    onRetry: onSyncNow
                )
            } else if case .diverged(let detail) = status {
                RepoDivergedRowView(
                    detail: detail,
                    lastVerifiedAt: repo.lastVerifiedAt,
                    isVerifying: isVerifying,
                    onVerifyNow: onVerifyNow,
                    onSyncNow: onSyncNow
                )
            } else {
                RepoIdleRowView(
                    status: status,
                    lastSyncedAt: repo.lastSyncedAt,
                    lastVerifiedAt: repo.lastVerifiedAt,
                    nextFireDate: nextFireDate,
                    isVerifying: isVerifying,
                    onSyncNow: onSyncNow,
                    onVerifyNow: onVerifyNow
                )
            }
        }
    }
}
