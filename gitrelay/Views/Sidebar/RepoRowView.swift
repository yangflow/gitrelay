import SwiftUI

struct RepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void
    let onEdit: () -> Void
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
            Button("立即同步", action: onSyncNow)
                .disabled(status == .syncing)
            Button("立即校验", action: onVerifyNow)
                .disabled(status == .syncing)
            Divider()
            Button("编辑...", action: onEdit)
            Button("删除...", role: .destructive, action: onDelete)
        }
    }

    private var isEscalatedFailure: Bool {
        RepoRowHealthPresentation.showsFailureBadge(for: repo)
    }
}
