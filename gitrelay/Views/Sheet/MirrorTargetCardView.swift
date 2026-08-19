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
                Picker("类型", selection: $target.kind) {
                    ForEach(MirrorTargetKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                switch target.kind {
                case .gitRemote:
                    gitRemoteFields
                case .filesystem:
                    filesystemFields
                }

                Toggle("启用", isOn: $target.enabled)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text("目标 \(index + 1)")
                    .font(.subheadline.weight(.medium))
                Text(targetSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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

    private var targetSummary: String {
        switch target.kind {
        case .gitRemote:
            let trimmed = target.url.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Git 远程" : trimmed
        case .filesystem:
            let trimmed = target.filesystemPath.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "文件系统归档" : trimmed
        }
    }

    @ViewBuilder
    private var gitRemoteFields: some View {
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
    }

    @ViewBuilder
    private var filesystemFields: some View {
        HStack {
            TextField("/Volumes/Backup/git-archives", text: $target.filesystemPath)
                .font(.system(.caption, design: .monospaced))
            Button("选择…") {
                pickArchiveDirectory()
            }
        }
        if let err = error {
            Text(err).font(.caption).foregroundStyle(.red)
        }

        Picker("归档格式", selection: $target.archiveFormat) {
            ForEach(ArchiveFormat.allCases) { format in
                Text(format.displayName).tag(format)
            }
        }

        TextField("文件名模板", text: $target.filenameTemplate, prompt: Text(target.archiveFormat.defaultFilenameTemplate))
            .font(.system(.caption, design: .monospaced))
        Text("可用占位符: {name}、{date} (yyyy-MM-dd)")
            .font(.caption2)
            .foregroundStyle(.secondary)

        TextField("保留份数 (可选)", text: $target.retentionCount)
            .font(.system(.caption, design: .monospaced))
        Text("留空表示不自动清理旧归档。")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func pickArchiveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择归档输出目录"
        if panel.runModal() == .OK, let url = panel.url {
            target.filesystemPath = url.path
        }
    }
}
