import SwiftUI

struct RepoStatusLabel: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .ahead(let n):
            Label("src is \(n) commits ahead", systemImage: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .font(.callout)
        case .idle:
            Label("Synced", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .diverged:
            Label("Content divergence", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.callout)
        default:
            Label("Unknown Status", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
