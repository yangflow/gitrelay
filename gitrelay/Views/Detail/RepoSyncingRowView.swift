import SwiftUI

struct RepoSyncingRowView: View {
    let statusTitle: String
    let latestLogLine: String?
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ProgressView()
                .controlSize(.small)
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
            Spacer(minLength: DesignTokens.Spacing.md)
            Button(String(localized: "Cancel"), action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
