import SwiftUI

struct RepoSyncingRowView: View {
    let statusTitle: String
    let latestLogLine: String?

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
        }
    }
}
