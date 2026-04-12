import SwiftUI

struct AuthFieldView: View {
    let label: String
    @Binding var mode: AuthMode
    @Binding var keyPath: String
    @Binding var token: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("\(label) 认证", selection: $mode) {
                ForEach(AuthMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .sshAgent:
                Text("使用系统 SSH Agent（~/.ssh/config）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .sshKey:
                HStack {
                    TextField("私钥路径", text: $keyPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button("选择...") { pickFile() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            case .httpsToken:
                SecureField("Personal Access Token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Text("Token 将加密存储在系统 Keychain 中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "选择 SSH 私钥"
        if panel.runModal() == .OK {
            keyPath = panel.url?.path ?? ""
        }
    }
}
