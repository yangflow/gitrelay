import SwiftUI

struct RepoIdleRowView: View {
    let status: SyncStatus
    let lastSyncedAt: Date?
    let lastVerifiedAt: Date?
    let isVerifying: Bool
    let onSyncNow: () -> Void
    let onVerifyNow: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                RepoStatusLabel(status: status)
                if let lastSyncedAt {
                    Text(String.loc("Last synced: \(lastSyncedAt.formatted(.dateTime.year().month().day().hour().minute()))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastVerifiedAt {
                    Text(String.loc("Last verified: \(lastVerifiedAt.formatted(.relative(presentation: .named)))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            VStack(spacing: DesignTokens.Spacing.xs) {
                Button(String.loc("Verify Now"), action: onVerifyNow)
                    .buttonStyle(.bordered)
                    .disabled(isVerifying || status == .syncing)
                Button(String.loc("Sync Now"), action: onSyncNow)
                    .buttonStyle(.borderedProminent)
                    .disabled(isVerifying || status == .syncing)
            }
        }
    }
}
