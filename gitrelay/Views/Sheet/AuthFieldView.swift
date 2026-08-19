import SwiftUI
import UniformTypeIdentifiers

struct AuthFieldView: View {
    let label: String
    var remoteURL: String? = nil
    @Binding var mode: AuthMode
    @Binding var keyPath: String
    @Binding var token: String

    @State private var isPickingKey = false
    @State private var showGenerateKeySheet = false
    @State private var generatedKeyResult: SSHKeyGenerationResult?
    @State private var showPublicKeyPreview = false
    @State private var previewPublicKey: String?
    @State private var previewPublicKeyPath: String?
    @State private var previewError: String?

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
                    Button("生成新密钥") { showGenerateKeySheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
                        previewError = nil
                    }
                }
                HStack(spacing: 8) {
                    Button("查看密钥") { loadPublicKeyPreview() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(keyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let previewError {
                        Text(previewError)
                            .font(.caption)
                            .foregroundStyle(.red)
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
        .sheet(isPresented: $showGenerateKeySheet) {
            GenerateSSHKeySheet { result in
                keyPath = result.privateKeyPath
                previewError = nil
                generatedKeyResult = result
            }
        }
        .sheet(item: $generatedKeyResult) { result in
            SSHKeyGeneratedSheet(result: result, remoteURL: remoteURL)
        }
        .sheet(isPresented: $showPublicKeyPreview) {
            if let previewPublicKey, let previewPublicKeyPath {
                SSHPublicKeyPreviewSheet(
                    publicKey: previewPublicKey,
                    publicKeyPath: previewPublicKeyPath
                )
            }
        }
    }

    private func loadPublicKeyPreview() {
        previewError = nil
        do {
            let trimmedPath = keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let expandedPath = SSHKeyGenerator.expandPath(trimmedPath)
            let publicKey = try SSHKeyGenerator.readPublicKey(privateKeyPath: trimmedPath)
            previewPublicKey = publicKey
            previewPublicKeyPath = SSHKeyGenerator.publicKeyPath(forPrivateKeyPath: expandedPath)
            showPublicKeyPreview = true
        } catch {
            previewError = error.localizedDescription
        }
    }
}

extension SSHKeyGenerationResult: Identifiable {
    var id: String { privateKeyPath }
}
