import SwiftUI

struct RepoStatusSectionView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let isSyncing: Bool
    let isVerifying: Bool
    let records: [SyncRecord]
    let syncPhase: SyncPhase?
    let nextFireDate: Date?
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void
    let onCancel: () -> Void
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void
    var onCopyFailure: (() -> Void)?

    private var nextStep: RepoFailureNextStep {
        RepoFailureNextStep.make(repo: repo, status: status, recentRecords: records)
    }

    private var scheduleState: RepoScheduleState {
        RepoScheduleState.make(repo: repo, nextFireDate: nextFireDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if isSyncing {
                RepoSyncingRowView(
                    statusTitle: syncPhase?.statusTitle ?? String(localized: "Syncing..."),
                    latestLogLine: syncPhase?.progressDetail,
                    onCancel: onCancel
                )
            } else if case .queued = status {
                RepoQueuedRowView(onCancel: onCancel)
            } else if case .failed(let message) = status {
                RepoFailureRowView(
                    message: message,
                    lastSyncedAt: repo.lastSyncedAt,
                    lastSuccessfulSyncedAt: repo.lastSuccessfulSyncedAt,
                    consecutiveFailureCount: repo.consecutiveFailureCount,
                    nextStep: nextStep,
                    onRetry: onSyncNow,
                    onReenterCredentials: onReenterCredentials,
                    onOpenLog: onOpenLog,
                    onCopyFailure: onCopyFailure
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
                    isVerifying: isVerifying,
                    onSyncNow: onSyncNow,
                    onVerifyNow: onVerifyNow
                )
            }

            scheduleLine
        }
    }

    /// When the schedule fires next, on the face of the detail rather than in a
    /// tooltip — and 已暂停 when this pair's schedule is paused.
    @ViewBuilder
    private var scheduleLine: some View {
        let state = scheduleState
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: state.isPaused ? "pause.circle" : "clock")
            Text(state.nextRun.text())
        }
        .font(.caption)
        .foregroundStyle(state.isPaused ? DesignTokens.StatusColor.pause : Color.secondary)
        .help(String(localized: "Scheduled sync runs only while GitRelay stays open. Manual sync is unaffected."))
    }
}
