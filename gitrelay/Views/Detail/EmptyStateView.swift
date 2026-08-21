import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void
    var isDropTargeted: Bool = false

    var body: some View {
        ContentUnavailableView {
            Label("GitRelay", systemImage: "arrow.left.arrow.right.circle")
        } description: {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Text("Mirror any Git repository to another repository\nGitLab → GitHub · Gitea · Gitee")
                Text("Drop a git URL or local .git folder to start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Add Your First Repository", action: onAdd)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxl)
        .background {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.control, style: .continuous)
                    .strokeBorder(DesignTokens.StatusColor.info.opacity(0.85), lineWidth: 2)
                    .padding(DesignTokens.Spacing.md)
            }
        }
    }
}
