import SwiftUI

struct RepoQueuedRowView: View {
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "clock")
                .foregroundStyle(DesignTokens.StatusColor.queued)
            Text(String(localized: "Queued"))
                .font(.callout)
                .foregroundStyle(DesignTokens.StatusColor.queued)
            Spacer(minLength: DesignTokens.Spacing.md)
            Button(String(localized: "Cancel"), action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}
