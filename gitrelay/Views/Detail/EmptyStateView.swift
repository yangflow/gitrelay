import SwiftUI

struct EmptyStateView: View {
    let onAdd: () -> Void
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    @State private var didAppear = false

    private var example: RepoSourceDropPrefill { .emptyStateExample }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(
                    width: DesignTokens.Size.emptyStateIconTile,
                    height: DesignTokens.Size.emptyStateIconTile
                )
                .background(Color.accentColor.opacity(0.10))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.CornerRadius.panel,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            Text(String.loc("No Mirrors"))
                .font(.title3.weight(.semibold))

            Text(String.loc("Add a Mirror, or drop a Git URL to get started."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: DesignTokens.Spacing.sm) {
                Button(String.loc("Add Mirror"), action: onAdd)
                    .buttonStyle(.borderedProminent)

                if let onExamplePrefill {
                    Button {
                        onExamplePrefill(example)
                    } label: {
                        Text(String.loc("Try an example Mirror"))
                            .font(.callout)
                    }
                    .buttonStyle(QuietPressButtonStyle())
                    .foregroundStyle(.secondary)
                    .help(examplePairCaption)
                    .accessibilityHint(String.loc("Opens the add sheet with example URLs. Nothing is saved until you confirm."))
                }
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
