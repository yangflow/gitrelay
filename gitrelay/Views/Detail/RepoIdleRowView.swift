import SwiftUI

struct RepoIdleRowView: View {
    let status: SyncStatus
    let lastSyncedAt: Date?
    let lastVerifiedAt: Date?
    let nextFireDate: Date?
    let isVerifying: Bool
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                RepoStatusLabel(status: status)
                if let lastSyncedAt {
                    Text("上次同步：\(lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastVerifiedAt {
                    Text("上次校验：\(lastVerifiedAt.formatted(.relative(presentation: .named)))")
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
            VStack(spacing: 6) {
                Button("立即校验", action: onVerifyNow)
                    .buttonStyle(.bordered)
                    .disabled(isVerifying || status == .syncing)
                Button("立即同步", action: onSyncNow)
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying || status == .syncing)
            }
        }
    }
}
