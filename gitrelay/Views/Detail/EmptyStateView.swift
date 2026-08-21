import SwiftUI

struct EmptyStateView: View {
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    @State private var didAppear = false

    private var example: RepoSourceDropPrefill { .emptyStateExample }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(String(localized: "Select a repository, or drop a git URL to add one."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let onExamplePrefill {
                Button {
                    onExamplePrefill(example)
                } label: {
                    Text(String(localized: "Try an example pair"))
                        .font(.callout)
                }
                .buttonStyle(QuietPressButtonStyle())
                .foregroundStyle(.secondary)
                .help(examplePairCaption)
                .accessibilityHint(String(localized: "Opens the add sheet with example URLs. Nothing is saved until you confirm."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.xxl)
        .opacity(didAppear ? 1 : 0)
        .animation(.easeOut(duration: 0.22), value: didAppear)
        .onAppear { didAppear = true }
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
