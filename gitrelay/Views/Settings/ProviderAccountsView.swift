import SwiftUI

/// Dedicated account page for one provider (GitHub / GitLab / Gitea).
///
/// Opened from the 账号 sidebar rows. Lists that provider's saved tokens with
/// last-used, Test, and add-token — not the six-tab Settings screen.
struct ProviderAccountsView: View {
    let provider: GitProvider

    @State private var accountSummaries: [ProviderAccountSummary] = []
    @State private var tokenTestOutcomes: [String: ProviderTokenTestOutcome] = [:]
    @State private var accountsUnderTest: Set<String> = []
    @State private var isPresentingAddToken = false

    private var visibleAccounts: [ProviderAccountSummary] {
        ProviderAccountSummary.filtered(accountSummaries, provider: provider)
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeaderView(title: provider.displayName)

            Form {
                accountsSection()
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { reloadAccounts() }
        .sheet(isPresented: $isPresentingAddToken) {
            AddProviderTokenSheet(
                initialProvider: provider,
                locksProviderSelection: true,
                onSaved: { savedProvider, label in
                    reloadAccounts()
                    testToken(provider: savedProvider, accountLabel: label)
                }
            )
        }
    }

    @ViewBuilder
    private func accountsSection() -> some View {
        Section {
            if visibleAccounts.isEmpty {
                Text(String(localized: "No account is connected yet."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleAccounts) { summary in
                    ProviderAccountRowView(
                        summary: summary,
                        outcome: tokenTestOutcomes[summary.id],
                        isTesting: accountsUnderTest.contains(summary.id),
                        onTest: {
                            testToken(provider: summary.provider, accountLabel: summary.label)
                        }
                    )
                }
            }

            Button {
                isPresentingAddToken = true
            } label: {
                Label(String(localized: "Add Token"), systemImage: "plus")
            }
        } footer: {
            Text(String(localized: "Tokens are stored in the Keychain and are never written to a log or to exported configuration. Test asks the provider whether a saved token still works."))
        }
    }

    private func reloadAccounts() {
        accountSummaries = ProviderAccountSummary.listed(
            ProviderAccountSummary.summaries(
                recordsByProvider: ProviderAccountStore.allAccounts(),
                hasToken: { provider, label in
                    ProviderTokenStore.load(provider: provider, accountLabel: label) != nil
                }
            )
        )
    }

    private func testToken(provider: GitProvider, accountLabel: String) {
        let id = ProviderAccount.id(provider: provider, label: accountLabel)
        guard !accountsUnderTest.contains(id) else { return }
        accountsUnderTest.insert(id)
        tokenTestOutcomes[id] = nil

        Task {
            let outcome = await ProviderTokenTester.run(
                provider: provider,
                accountLabel: accountLabel,
                host: ProviderAccountStore.host(for: provider, label: accountLabel)
            )
            accountsUnderTest.remove(id)
            tokenTestOutcomes[id] = outcome
            reloadAccounts()
        }
    }
}
