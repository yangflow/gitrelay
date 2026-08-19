import SwiftUI

struct GenerateSSHKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var keyPath: String
    @State private var passphrase = ""
    @State private var usePassphrase = false
    @State private var errorMessage: String?
    @State private var isGenerating = false

    let onGenerated: (SSHKeyGenerationResult) -> Void

    init(
        initialKeyPath: String = SSHKeyGenerator.defaultDisplayPath,
        onGenerated: @escaping (SSHKeyGenerationResult) -> Void
    ) {
        _keyPath = State(initialValue: initialKeyPath)
        self.onGenerated = onGenerated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("生成 SSH 密钥")
                .font(.headline)
                .padding([.horizontal, .top], 20)
                .padding(.bottom, 12)

            Divider()

            Form {
                Section {
                    TextField("私钥路径", text: $keyPath)
                        .font(.system(.body, design: .monospaced))
                    Text("默认保存为 \(SSHKeyGenerator.defaultDisplayPath)。公钥将写入同路径的 .pub 文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("使用 passphrase 加密私钥", isOn: $usePassphrase)
                    if usePassphrase {
                        SecureField("Passphrase", text: $passphrase)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape)
                    .disabled(isGenerating)
                Button("生成", action: generate)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(isGenerating)
            }
            .padding(16)
        }
        .frame(width: 460)
    }

    private func generate() {
        errorMessage = nil
        isGenerating = true
        defer { isGenerating = false }

        do {
            let result = try SSHKeyGenerator.generate(
                privateKeyPath: keyPath,
                passphrase: usePassphrase ? passphrase : nil
            )
            onGenerated(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
