import SwiftUI

struct RepoQueuedRowView: View {
    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "clock")
                .foregroundStyle(DesignTokens.StatusColor.queued)
            Text(String.loc("Queued"))
                .font(.callout)
                .foregroundStyle(DesignTokens.StatusColor.queued)
        }
    }
}
