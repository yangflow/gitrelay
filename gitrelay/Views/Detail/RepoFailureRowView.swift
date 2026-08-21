import SwiftUI

struct RepoFailureRowView: View {
    let message: String
    let lastSyncedAt: Date?
    let lastSuccessfulSyncedAt: Date?
    let consecutiveFailureCount: Int
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.popoverChromeVertical) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.diverged)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Last Sync Failed")
                    .font(.callout)
                    .fontWeight(.medium)
                if consecutiveFailureCount > 0 {
                    Text("\(consecutiveFailureCount) consecutive failures")
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
                    Text("Last success: \(lastSuccessfulSyncedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastSyncedAt {
                    Text(lastSyncedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Surface.statusCalloutFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.banner,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.banner,
                style: .continuous
            )
            .stroke(DesignTokens.Surface.statusCalloutStroke, lineWidth: 1)
        }
    }
}
