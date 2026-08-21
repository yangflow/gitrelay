import SwiftUI

struct RepoSyncingRowView: View {
    let statusTitle: String
    let latestLogLine: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .scaleEffect(0.8)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(statusTitle)
                    .font(.callout)
                if let latestLogLine {
                    Text(latestLogLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Surface.panelFill)
        .clipShape(
            RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.banner,
                style: .continuous
            )
        )
    }
}
