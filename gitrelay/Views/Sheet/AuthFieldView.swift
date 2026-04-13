import SwiftUI
import UniformTypeIdentifiers

struct AuthFieldView: View {
    let label: String
    @Binding var mode: AuthMode
    @Binding var keyPath: String
    @Binding var token: String

    @State private var isPickingKey = false

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
                Text("使用系统 SSH Agent(~/.ssh/config)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .sshKey:
                HStack {
                    TextField("私钥路径", text: $keyPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Button("选择...") { isPickingKey = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .fileImporter(
                    isPresented: $isPickingKey,
                    allowedContentTypes: [.data]
                ) { result in
                    if case .success(let url) = result {
                        keyPath = url.path
                    }
                }
            case .httpsToken:
                SecureField("Personal Access Token", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Text("Token 将加密存储在系统 Keychain 中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
