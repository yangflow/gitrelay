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
            Text("src is \(n) commits ahead")
                .foregroundStyle(DesignTokens.StatusColor.ahead)
        case .idle:
            Text("Synced")
                .foregroundStyle(DesignTokens.StatusColor.idle)
        case .diverged:
            Text("Content divergence")
                .foregroundStyle(DesignTokens.StatusColor.diverged)
        case .syncing:
            Text("Syncing...")
                .foregroundStyle(DesignTokens.StatusColor.syncing)
        case .failed:
            Text("Last Sync Failed")
                .foregroundStyle(DesignTokens.StatusColor.failed)
        case .unknown:
            Text("Unknown Status")
                .foregroundStyle(DesignTokens.StatusColor.unknown)
        }
    }
}
