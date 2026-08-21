import SwiftUI

struct RepoFailureRowView: View {
    let message: String
    let lastSyncedAt: Date?
    let lastSuccessfulSyncedAt: Date?
    let consecutiveFailureCount: Int
    let nextStep: RepoFailureNextStep
    let onRetry: () -> Void
    let onReenterCredentials: () -> Void
    let onOpenLog: () -> Void
    var onCopyFailure: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.failed)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String(localized: "Last Sync Failed"))
                    .font(.callout)
                    .fontWeight(.medium)
                if consecutiveFailureCount > 0 {
                    Text(String(localized: "\(consecutiveFailureCount) consecutive failures"))
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
                    Text(String(localized: "Last success: \(lastSuccessfulSyncedAt.formatted(.relative(presentation: .named)))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastSyncedAt {
                    Text(lastSyncedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                RepoFailureNextStepActionsView(
                    nextStep: nextStep,
                    compact: false,
                    onReenterCredentials: onReenterCredentials,
                    onOpenLog: onOpenLog,
                    onCopyFailure: onCopyFailure
                )
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            Button(String(localized: "Retry"), action: onRetry)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
