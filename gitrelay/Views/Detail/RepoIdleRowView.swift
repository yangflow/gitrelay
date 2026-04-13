import SwiftUI

struct RepoIdleRowView: View {
    let status: SyncStatus
    let lastSyncedAt: Date?
    let nextFireDate: Date?
    let onSyncNow: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                RepoStatusLabel(status: status)
                if let lastSyncedAt {
                    Text("上次同步：\(lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let nextFireDate {
                    Text("下次同步：\(nextFireDate.formatted(.relative(presentation: .named)))(需 App 保持运行)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("立即同步", action: onSyncNow)
                .buttonStyle(.borderedProminent)
        }
    }
}
