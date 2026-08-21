import SwiftUI

/// GitHub / GitLab account list built from the existing account registry and
/// Keychain token tags. Adding or replacing a token still happens in the
/// browse-remote flow; this pane only reports what is configured.
struct ProviderAccountsView: View {
    let provider: GitProvider
    let onBrowse: () -> Void

    @State private var summaries: [ProviderAccountSummary] = []

    private var hasAnyToken: Bool { summaries.contains(where: \.hasToken) }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeaderView(
                title: provider.displayName,
                subtitle: hasAnyToken ? nil : String(localized: "No account is connected yet.")
            ) {
                Button(String(localized: "Browse Remote"), action: onBrowse)
            }

            if hasAnyToken {
                accountList
            } else {
                PaneEmptyStateView(
                    systemImage: provider.symbolName,
                    message: String(localized: "Connect a \(provider.displayName) account by browsing remote repositories. The token is stored in the Keychain."),
                    actionTitle: String(localized: "Browse Remote"),
                    action: onBrowse
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: provider) { reload() }
    }

    private var accountList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(summaries) { summary in
                    row(summary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.paneHeaderHorizontal)
            .padding(.bottom, DesignTokens.Spacing.paneHeaderHorizontal)
        }
    }

    private func row(_ summary: ProviderAccountSummary) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: provider.symbolName)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(summary.label)
                Text(summary.hostText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            Label {
                Text(summary.credentialText)
                    .font(.caption)
            } icon: {
                Image(systemName: summary.hasToken ? "checkmark.circle.fill" : "minus.circle")
                    .font(.caption)
                    .foregroundStyle(
                        summary.hasToken
                            ? DesignTokens.StatusColor.success
                            : Color.secondary
                    )
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gitRelayPanelSurface(cornerRadius: DesignTokens.CornerRadius.panel)
    }

    private func reload() {
        summaries = ProviderAccountSummary.summaries(
            provider: provider,
            records: ProviderAccountStore.accounts(for: provider),
            hasToken: { label in
                ProviderTokenStore.load(provider: provider, accountLabel: label) != nil
            }
        )
    }
}
