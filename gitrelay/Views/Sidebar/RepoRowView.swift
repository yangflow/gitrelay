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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .foregroundStyle(isEscalatedFailure ? .red : .primary)
                    .lineLimit(1)

                RepoRowCaptionView(caption: presentation)
            }
            Spacer()
            if isEscalatedFailure, let count = RepoRowHealthPresentation.failureBadgeCount(for: repo) {
                FailureCountBadge(count: count)
            }
            StatusIconView(status: status)
        }
        .padding(.vertical, 3)
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
}
