import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("GitRelay", systemImage: "arrow.left.arrow.right.circle")
        } description: {
            Text("Mirror any Git repository to another repository\nGitLab → GitHub · Gitea · Gitee")
        } actions: {
            Button("Add Your First Repository", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxl)
    }
}
