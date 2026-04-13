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
                Text(repo.name)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    if let lastSyncedAt = repo.lastSyncedAt {
                        Text(lastSyncedAt, format: .relative(presentation: .named))
                    } else {
                        Text("未同步")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
}
