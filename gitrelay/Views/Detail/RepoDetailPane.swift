import SwiftUI

/// Repository detail reached from a pair-table row: a back link to 仓库, the
/// repository name, then the unchanged ``RepoDetailView`` body.
struct RepoDetailPane: View {
    let repo: RepoConfig
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Button(action: onBack) {
                    Label(
                        MainSidebarItem.repositories.title,
                        systemImage: "chevron.left"
                    )
                    .font(.callout)
                }
                .buttonStyle(QuietPressButtonStyle())
                .foregroundStyle(.secondary)
                .help(String(localized: "Back to Repositories"))

                Text(repo.name)
                    .font(.title2.weight(.semibold))
            }
            .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
            .padding(.top, DesignTokens.Spacing.md)
            .padding(.bottom, DesignTokens.Spacing.paneHeaderBottom)

            RepoDetailView(repo: repo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
