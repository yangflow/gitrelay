import SwiftUI

struct RepoIdleRowView: View {
    let status: SyncStatus
    let lastSyncedAt: Date?
    let lastVerifiedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            if status == .unknown, lastSyncedAt == nil {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: DesignTokens.Size.statusDot, height: DesignTokens.Size.statusDot)
                    Text(String.loc("Not Synced"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                RepoStatusLabel(status: status)
            }
            if let lastSyncedAt {
                Text(String(format: String.loc("Last synced: %@"), lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let lastVerifiedAt {
                Text(String(format: String.loc("Last verified: %@"), lastVerifiedAt.formatted(.relative(presentation: .named))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
