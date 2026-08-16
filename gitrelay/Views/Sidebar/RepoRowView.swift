import SwiftUI

struct RepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .foregroundStyle(isEscalatedFailure ? .red : .primary)
                    .lineLimit(1)

                lastSuccessLabel
                    .font(.caption2)
                    .foregroundStyle(isStale ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isEscalatedFailure {
                FailureCountBadge(count: repo.consecutiveFailureCount)
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

    private var lastSuccessLabel: some View {
        Group {
            if case .diverged = status {
                Text("内容分歧")
            } else if let lastSuccessfulSyncedAt = repo.lastSuccessfulSyncedAt {
                Text("最近成功 \(lastSuccessfulSyncedAt, format: .relative(presentation: .named))")
            } else if repo.lastSyncedAt != nil {
                Text("尚无成功同步")
            } else {
                Text("未同步")
            }
        }
    }

    private var isEscalatedFailure: Bool {
        repo.consecutiveFailureCount >= 3
    }

    private var isStale: Bool {
        guard let lastSuccessfulSyncedAt = repo.lastSuccessfulSyncedAt else {
            return true
        }
        return Date.now.timeIntervalSince(lastSuccessfulSyncedAt) > 86_400
    }
}
