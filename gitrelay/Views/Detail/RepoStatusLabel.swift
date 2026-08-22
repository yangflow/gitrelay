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
            Text(String(format: String.loc("src is %lld commits ahead"), n))
                .foregroundStyle(DesignTokens.StatusColor.ahead)
        case .idle:
            Text(String.loc("Synced"))
                .foregroundStyle(DesignTokens.StatusColor.idle)
        case .diverged:
            Text(String.loc("Content divergence"))
                .foregroundStyle(DesignTokens.StatusColor.diverged)
        case .syncing:
            Text(String.loc("Syncing..."))
                .foregroundStyle(DesignTokens.StatusColor.syncing)
        case .queued:
            Text(String.loc("Queued"))
                .foregroundStyle(DesignTokens.StatusColor.queued)
        case .failed:
            Text(String.loc("Last Sync Failed"))
                .foregroundStyle(DesignTokens.StatusColor.failed)
        case .unknown:
            Text(String.loc("Unknown Status"))
                .foregroundStyle(DesignTokens.StatusColor.unknown)
        }
    }
}
