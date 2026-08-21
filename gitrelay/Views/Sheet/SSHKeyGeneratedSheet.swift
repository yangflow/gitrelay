import SwiftUI

struct SSHKeyGeneratedSheet: View {
    @Environment(\.dismiss) private var dismiss

    let result: SSHKeyGenerationResult
    let remoteURL: String?

    @State private var didCopy = false

    private var provider: GitProvider {
        if let remoteURL, let inferred = GitRemoteHost.inferredProvider(fromRemoteURL: remoteURL) {
            return inferred
        }
        return .github
    }

    private var settingsURL: URL {
        if let remoteURL, let url = GitRemoteHost.sshKeysSettingsURL(forRemoteURL: remoteURL) {
            return url
        }
        return GitRemoteHost.sshKeysSettingsURL(for: .github, host: "github.com")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.StatusColor.success)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                    Text("SSH Key Generated")
                        .font(.headline)
                    Text("Add the public key to \(GitRemoteHost.sshKeysSettingsLabel(for: provider)) to use SSH authentication.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if didCopy {
                        Label("Copied to Clipboard", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.success)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DesignTokens.Spacing.sheetContent)

            Divider()

            ScrollView {
                Text(result.publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.sheetContent)
            }
            .frame(maxHeight: 120)

            Divider()

            HStack {
                Button("Copy Public Key") {
                    ClipboardService.copy(result.publicKey)
                    didCopy = true
                }
                Button("Open \(GitRemoteHost.sshKeysSettingsLabel(for: provider)) SSH Settings") {
                    if !didCopy {
                        ClipboardService.copy(result.publicKey)
                        didCopy = true
                    }
                    NSWorkspace.shared.open(settingsURL)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: 520)
        .gitRelayChrome(.sheet)
        .onAppear {
            ClipboardService.copy(result.publicKey)
            didCopy = true
        }
    }
}
