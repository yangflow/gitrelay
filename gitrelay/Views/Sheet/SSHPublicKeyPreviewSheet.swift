import SwiftUI

struct SSHPublicKeyPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let publicKey: String
    let publicKeyPath: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text("Public Key Preview")
                    .font(.headline)
                Text(publicKeyPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if didCopy {
                    Label("Copied to Clipboard", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.success)
                }
            }
            .padding(DesignTokens.Spacing.sheetContent)

            Divider()

            ScrollView {
                Text(publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DesignTokens.Spacing.sheetContent)
            }
            .frame(maxHeight: 160)

            Divider()

            HStack {
                Button("Copy Public Key") {
                    ClipboardService.copy(publicKey)
                    didCopy = true
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .gitRelaySheetFooterPadding()
        }
        .frame(width: 520)
        .gitRelayChrome(.sheet)
    }
}
