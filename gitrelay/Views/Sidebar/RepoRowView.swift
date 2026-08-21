import SwiftUI

struct RepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    var syncPhase: SyncPhase? = nil
    var recentRecords: [SyncRecord] = []
    let onSyncNow: () -> Void
    let onCancelSync: () -> Void
    let onVerifyNow: () -> Void
    let onEdit: () -> Void
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void
    let onFreeSpace: () -> Void
    let onDelete: () -> Void

    private var presentation: RepoRowHealthPresentation.Caption {
        RepoRowHealthPresentation.caption(for: repo, status: status, syncPhase: syncPhase)
    }

    private var nextStep: RepoFailureNextStep {
        RepoFailureNextStep.make(repo: repo, status: status, recentRecords: recentRecords)
    }

    private var backupCompleteness: BackupCompleteness {
        BackupCompleteness.evaluate(repo: repo, recentRecords: recentRecords)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.statusDotGap) {
            StatusDotView(status: status)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                HStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(repo.name)
                        .foregroundStyle(
                            isEscalatedFailure
                                ? DesignTokens.StatusColor.escalatedFailure
                                : .primary
                        )
                        .lineLimit(1)
                    if backupCompleteness.showsIncompleteMark, let help = backupCompleteness.helpText {
                        IncompleteBackupMarkView(helpText: help)
                    }
                }

                RepoRowCaptionView(caption: presentation)

                RepoFailureNextStepActionsView(
                    nextStep: nextStep,
                    compact: true,
                    onReenterCredentials: onReenterCredentials,
                    onOpenLog: onOpenLog
                )
            }
            Spacer(minLength: DesignTokens.Spacing.xxs)
            if isEscalatedFailure, let count = RepoRowHealthPresentation.failureBadgeCount(for: repo) {
                FailureCountBadge(count: count)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.rowVertical)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu {
            if status == .queued || status == .syncing {
                Button(String(localized: "Cancel"), action: onCancelSync)
            } else {
                Button("Sync Now", action: onSyncNow)
            }
            Button("Verify Now", action: onVerifyNow)
                .disabled(status == .syncing || status == .queued)
            Button(String(localized: "Free Space"), action: onFreeSpace)
                .disabled(status == .syncing || status == .queued)
            if nextStep.showsReenterCredentials {
                Button(String(localized: "Re-enter credentials"), action: onReenterCredentials)
            }
            if nextStep.showsOpenLog {
                Button(String(localized: "Open Log"), action: onOpenLog)
            }
            Divider()
            Button("Edit...", action: onEdit)
            Button("Delete...", role: .destructive, action: onDelete)
        }
    }

    private var isEscalatedFailure: Bool {
        RepoRowHealthPresentation.showsFailureBadge(for: repo)
    }

    private var accessibilityLabel: String {
        let statusText: String
        switch status {
        case .unknown:
            statusText = String(localized: "Unknown Status")
        case .idle:
            statusText = String(localized: "Synced")
        case .ahead(let count):
            statusText = String(localized: "src is \(count) commits ahead")
        case .syncing:
            statusText = syncPhase?.displayCaption ?? String(localized: "Syncing...")
        case .queued:
            statusText = String(localized: "Queued")
        case .diverged:
            statusText = String(localized: "Content divergence")
        case .failed:
            statusText = String(localized: "Last Sync Failed")
        }
        if let help = backupCompleteness.helpText {
            return "\(repo.name), \(statusText), \(help)"
        }
        return "\(repo.name), \(statusText)"
    }
}
