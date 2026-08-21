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
            HStack {
                Text(String(localized: "Generate SSH Key"))
                    .font(.headline)
                Spacer()
            }
            .gitRelaySheetHeaderPadding()

            Divider()

            Form {
                Section {
                    TextField(String(localized: "Private Key Path"), text: $keyPath)
                        .font(.system(.body, design: .monospaced))
                    Text(String(localized: "The default path is \(SSHKeyGenerator.defaultDisplayPath). The public key will be written to a .pub file at the same path."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Key Location"))
                }

                Section {
                    Toggle(String(localized: "Encrypt the private key with a passphrase"), isOn: $usePassphrase)
                    if usePassphrase {
                        SecureField(String(localized: "Passphrase"), text: $passphrase)
                            .textFieldStyle(.roundedBorder)
                    }
                } header: {
                    Text(String(localized: "Passphrase"))
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.error)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                    .disabled(isGenerating)
                Button(String(localized: "Generate"), action: generate)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
                    .disabled(isGenerating)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: 460)
        .gitRelayChrome(.sheet)
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
