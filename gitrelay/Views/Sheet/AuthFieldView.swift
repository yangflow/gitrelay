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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Picker("\(label) Authentication", selection: $mode) {
                ForEach(AuthMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .sshAgent:
                Text("Use System SSH Agent (~/.ssh/config)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .sshKey:
                HStack {
                    TextField("Private Key Path", text: $keyPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Button("Generate New Key") { showGenerateKeySheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Choose...") { isPickingKey = true }
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
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Button("View Key") { loadPublicKeyPreview() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(keyPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let previewError {
                        Text(previewError)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.error)
                    }
                }
            case .httpsToken:
                GatedSecureTokenField(
                    placeholder: "Personal Access Token",
                    text: $token
                )
                Text("The token will be encrypted in the system Keychain")
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
