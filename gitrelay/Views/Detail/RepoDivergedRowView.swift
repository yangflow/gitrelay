import SwiftUI

struct RepoDivergedRowView: View {
    let detail: String
    let lastVerifiedAt: Date?
    let isVerifying: Bool
    let onVerifyNow: () -> Void
    let onSyncNow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.diverged)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String.loc("Backup content may have diverged from the source repository"))
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
                    .controlSize(.small)
                    .disabled(isVerifying)
                Button(String.loc("Sync Now"), action: onSyncNow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}
