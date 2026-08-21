import SwiftUI

struct RepoStatusSectionView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let isSyncing: Bool
    let isVerifying: Bool
    let records: [SyncRecord]
    let syncPhase: SyncPhase?
    let liveSyncLogLine: String?
    let nextFireDate: Date?
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void
    let onCancel: () -> Void
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void

    private var nextStep: RepoFailureNextStep {
        RepoFailureNextStep.make(repo: repo, status: status, recentRecords: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if isSyncing {
                RepoSyncingRowView(
                    statusTitle: syncPhase?.statusTitle ?? "Syncing...",
                    latestLogLine: liveSyncLogLine ?? records.last?.logLines.last,
                    onCancel: onCancel
                )
            } else if case .failed(let message) = status {
                RepoFailureRowView(
                    message: message,
                    lastSyncedAt: repo.lastSyncedAt,
                    lastSuccessfulSyncedAt: repo.lastSuccessfulSyncedAt,
                    consecutiveFailureCount: repo.consecutiveFailureCount,
                    nextStep: nextStep,
                    onRetry: onSyncNow,
                    onReenterCredentials: onReenterCredentials,
                    onOpenLog: onOpenLog
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
