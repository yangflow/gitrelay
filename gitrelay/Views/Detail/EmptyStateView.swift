import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    private var example: RepoSourceDropPrefill { .emptyStateExample }

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
            VStack(spacing: DesignTokens.Spacing.md) {
                Button("Add Your First Repository", action: onAdd)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                if let onExamplePrefill {
                    Button {
                        onExamplePrefill(example)
                    } label: {
                        VStack(spacing: DesignTokens.Spacing.xxxs) {
                            Text(String(localized: "Try an example pair"))
                                .font(.callout.weight(.medium))
                            Text(examplePairCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: 360)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(String(localized: "Opens the add sheet with example URLs. Nothing is saved until you confirm."))
                }
            }
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

    private var examplePairCaption: String {
        "\(example.srcURL) → \(example.dstURL ?? "")"
    }
}
