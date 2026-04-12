import SwiftUI

struct RepoRowView: View {
    let repo: RepoConfig
    let status: SyncStatus
    let onSyncNow: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Text(repo.name)
                .lineLimit(1)
            Spacer()
            StatusIconView(status: status)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("立即同步") { onSyncNow() }
                .disabled(status == .syncing)
            Divider()
            Button("编辑...") { onEdit() }
            Button("删除...", role: .destructive) { onDelete() }
        }
    }
}
