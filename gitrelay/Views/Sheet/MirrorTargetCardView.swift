import SwiftUI

struct MirrorTargetCardView: View {
    let index: Int
    @Binding var target: MirrorTargetDraft
    let error: String?
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $target.isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("git@github.com:user/repo.git", text: $target.url)
                    .font(.system(.caption, design: .monospaced))
                if let err = error {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                AuthFieldView(
                    label: "Target \(index + 1)",
                    remoteURL: target.url,
                    mode: $target.authMode,
                    keyPath: $target.keyPath,
                    token: $target.token
                )
                Toggle("启用", isOn: $target.enabled)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("目标 \(index + 1)")
                    .font(.subheadline.weight(.medium))
                if !target.enabled {
                    Text("已禁用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除目标")
                }
            }
        }
    }
}
