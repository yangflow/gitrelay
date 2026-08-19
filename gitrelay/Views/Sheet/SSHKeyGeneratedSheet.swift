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
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 6) {
                    Text("SSH 密钥已生成")
                        .font(.headline)
                    Text("将公钥添加到 \(GitRemoteHost.sshKeysSettingsLabel(for: provider)) 后即可使用 SSH 认证。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if didCopy {
                        Label("已复制到剪贴板", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(result.publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxHeight: 120)

            Divider()

            HStack {
                Button("复制公钥") {
                    ClipboardService.copy(result.publicKey)
                    didCopy = true
                }
                Button("打开 \(GitRemoteHost.sshKeysSettingsLabel(for: provider)) SSH 设置") {
                    if !didCopy {
                        ClipboardService.copy(result.publicKey)
                        didCopy = true
                    }
                    NSWorkspace.shared.open(settingsURL)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear {
            ClipboardService.copy(result.publicKey)
            didCopy = true
        }
    }
}
