import SwiftUI

struct RepoStatusLabel: View {
    let status: SyncStatus

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            StatusDotView(status: status, showsAheadCount: false)
            statusText
                .font(.callout)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch status {
        case .ahead(let n):
            Text(String(localized: "src is \(n) commits ahead"))
                .foregroundStyle(DesignTokens.StatusColor.ahead)
        case .idle:
            Text(String(localized: "Synced"))
                .foregroundStyle(DesignTokens.StatusColor.idle)
        case .diverged:
            Text(String(localized: "Content divergence"))
                .foregroundStyle(DesignTokens.StatusColor.diverged)
        case .syncing:
            Text(String(localized: "Syncing..."))
                .foregroundStyle(DesignTokens.StatusColor.syncing)
        case .queued:
            Text(String(localized: "Queued"))
                .foregroundStyle(DesignTokens.StatusColor.queued)
        case .failed:
            Text(String(localized: "Last Sync Failed"))
                .foregroundStyle(DesignTokens.StatusColor.failed)
        case .unknown:
            Text(String(localized: "Unknown Status"))
                .foregroundStyle(DesignTokens.StatusColor.unknown)
        }
    }
}
