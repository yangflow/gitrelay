import SwiftUI

struct SSHPublicKeyPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let publicKey: String
    let publicKeyPath: String

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("公钥预览")
                    .font(.headline)
                Text(publicKeyPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if didCopy {
                    Label("已复制到剪贴板", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(20)

            Divider()

            ScrollView {
                Text(publicKey)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxHeight: 160)

            Divider()

            HStack {
                Button("复制公钥") {
                    ClipboardService.copy(publicKey)
                    didCopy = true
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.escape)
            }
            .padding(16)
        }
        .frame(width: 520)
    }
}
