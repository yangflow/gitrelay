import SwiftUI

struct RepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void
    let onEdit: () -> Void
    let onFreeSpace: () -> Void
    let onDelete: () -> Void

    private var presentation: RepoRowHealthPresentation.Caption {
        RepoRowHealthPresentation.caption(for: repo, status: status)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.statusDotGap) {
            StatusDotView(status: status)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(repo.name)
                    .foregroundStyle(
                        isEscalatedFailure
                            ? DesignTokens.StatusColor.escalatedFailure
                            : .primary
                    )
                    .lineLimit(1)

                RepoRowCaptionView(caption: presentation)
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
            Button("Sync Now", action: onSyncNow)
                .disabled(status == .syncing)
            Button("Verify Now", action: onVerifyNow)
                .disabled(status == .syncing)
            Button(String(localized: "Free Space"), action: onFreeSpace)
                .disabled(status == .syncing)
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
            statusText = String(localized: "Syncing...")
        case .diverged:
            statusText = String(localized: "Content divergence")
        case .failed:
            statusText = String(localized: "Last Sync Failed")
        }
        return "\(repo.name), \(statusText)"
    }
}
