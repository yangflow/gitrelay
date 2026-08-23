import SwiftUI

struct RepoFailureRowView: View {
    let message: String
    let lastSyncedAt: Date?
    let lastSuccessfulSyncedAt: Date?
    let consecutiveFailureCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.failed)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String.loc("Last Sync Failed"))
                    .font(.callout)
                    .fontWeight(.medium)
                if consecutiveFailureCount > 0 {
                    Text(String(format: String.loc("%lld consecutive failures"), consecutiveFailureCount))
                        .font(.caption)
                        .foregroundStyle(
                            consecutiveFailureCount >= 3
                                ? DesignTokens.StatusColor.escalatedFailure
                                : .secondary
                        )
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let lastSuccessfulSyncedAt {
                    Text(String(format: String.loc("Last success: %@"), lastSuccessfulSyncedAt.formatted(.relative(presentation: .named))))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastSyncedAt {
                    Text(lastSyncedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
