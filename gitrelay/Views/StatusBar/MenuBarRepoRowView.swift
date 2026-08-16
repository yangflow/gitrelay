import SwiftUI

struct MenuBarRepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSync: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSync) {
            HStack(spacing: 8) {
                StatusIconView(status: status)
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .foregroundStyle(isEscalatedFailure ? .red : .primary)
                        .lineLimit(1)
                    lastSuccessLabel
                        .font(.caption2)
                        .foregroundStyle(isStale ? .tertiary : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isEscalatedFailure {
                    FailureCountBadge(count: repo.consecutiveFailureCount)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.12)
                    : Color.clear
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
