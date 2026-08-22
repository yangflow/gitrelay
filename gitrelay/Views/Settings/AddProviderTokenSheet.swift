import SwiftUI

/// 添加令牌: pick a provider, name the account, paste the token.
///
/// The token goes straight from the field into the Keychain through
/// ``ProviderTokenStore``; nothing else keeps a copy of it.
struct AddProviderTokenSheet: View {
    let initialProvider: GitProvider?
    /// When true, the provider picker is hidden and ``initialProvider`` is fixed.
    var locksProviderSelection: Bool = false
    let onSaved: (GitProvider, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var provider: GitProvider = .github
    @State private var label = ProviderAccount.defaultLabel
    @State private var host = ""
    @State private var token = ""
    @State private var errorMessage: String?

    /// Only GitLab and Gitea talk to a host this app can point elsewhere; the
    /// GitHub client is fixed to github.com.
    private var acceptsHost: Bool { provider != .github }

    private var canSave: Bool {
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && ProviderAccount.normalizeLabel(label) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Add Token"))
                    .font(.headline)
                Spacer()
            }
            .gitRelaySheetHeaderPadding()

            Divider()

            Form {
                Section {
                    if !locksProviderSelection {
                        Picker(String(localized: "Provider"), selection: $provider) {
                            ForEach(GitProvider.allCases) { candidate in
                                Text(candidate.shortName).tag(candidate)
                            }
                        }
                    }

                    TextField(String(localized: "Account Name"), text: $label)

                    if acceptsHost {
                        TextField(String(localized: "Host"), text: $host)
                            .font(.system(.body, design: .monospaced))
                    }
                } header: {
                    Text(String(localized: "Account"))
                } footer: {
                    Text(String(localized: "Reusing an existing account name replaces that account's token."))
                }

                Section {
                    GatedSecureTokenField(placeholder: "", text: $token)

                    Text(provider.tokenHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.error)
                    }
                } header: {
                    Text(String(localized: "Personal Access Token"))
                } footer: {
                    Text(String(localized: "The token is stored in the Keychain. It is never written to a log or to exported configuration."))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(String(localized: "Save")) { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(!canSave)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: DesignTokens.Layout.addProviderTokenSheetWidth)
        .gitRelayChrome(.sheet)
        .onAppear {
            if let initialProvider {
                provider = initialProvider
            }
        }
    }

    private func save() {
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else { return }
        errorMessage = nil

        do {
            let record = try ProviderAccountStore.ensureAccount(label: label, for: provider)
            if acceptsHost {
                let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanHost.isEmpty {
                    ProviderAccountStore.setHost(cleanHost, for: provider, label: record.label)
                }
            }
            try ProviderTokenStore.save(token: cleanToken, provider: provider, accountLabel: record.label)
            token = ""
            onSaved(provider, record.label)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
