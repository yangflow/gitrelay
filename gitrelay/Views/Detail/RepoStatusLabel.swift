import SwiftUI

struct RepoStatusLabel: View {
    let status: SyncStatus

    var body: some View {
        switch status {
        case .ahead(let n):
            Label("src 领先 \(n) 个 commit", systemImage: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .font(.callout)
        case .idle:
            Label("已同步", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .diverged:
            Label("内容分歧", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.callout)
        default:
            Label("未知状态", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
