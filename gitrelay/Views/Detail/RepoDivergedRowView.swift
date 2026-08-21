import SwiftUI

struct RepoDivergedRowView: View {
    let detail: String
    let lastVerifiedAt: Date?
    let isVerifying: Bool
    let onVerifyNow: () -> Void
    let onSyncNow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.popoverChromeVertical) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.diverged)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Backup content may have diverged from the source repository")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let lastVerifiedAt {
                    Text("Last verified: \(lastVerifiedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: DesignTokens.Spacing.xs) {
                Button("Verify Now", action: onVerifyNow)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isVerifying)
                Button("Sync Now", action: onSyncNow)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
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
