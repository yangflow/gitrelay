import SwiftUI

struct MirrorTargetCardView: View {
    let index: Int
    @Binding var target: MirrorTargetDraft
    let error: String?
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $target.isExpanded) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Picker("Type", selection: $target.kind) {
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

                Toggle("Enabled", isOn: $target.enabled)
            }
            .padding(.top, DesignTokens.Spacing.xs)
        } label: {
            HStack {
                Text("Target \(index + 1)")
                    .font(.subheadline.weight(.medium))
                Text(targetSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !target.enabled {
                    Text("Disabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if canRemove {
                    Button(role: .destructive, action: onRemove) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete Target")
                }
            }
        }
    }

    private var targetSummary: String {
        switch target.kind {
        case .gitRemote:
            let trimmed = target.url.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? String(localized: "Git Remote") : trimmed
        case .filesystem:
            let trimmed = target.filesystemPath.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? String(localized: "Filesystem Archive") : trimmed
        }
    }

    @ViewBuilder
    private var gitRemoteFields: some View {
        TextField("git@github.com:user/repo.git", text: $target.url)
            .font(.system(.caption, design: .monospaced))
        if let err = error {
            Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
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
            Button("Choose…") {
                pickArchiveDirectory()
            }
        }
        if let err = error {
            Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
        }

        Picker("Archive Format", selection: $target.archiveFormat) {
            ForEach(ArchiveFormat.allCases) { format in
                Text(format.displayName).tag(format)
            }
        }

        TextField("Filename Template", text: $target.filenameTemplate, prompt: Text(target.archiveFormat.defaultFilenameTemplate))
            .font(.system(.caption, design: .monospaced))
        Text("Available placeholders: {name}, {date} (yyyy-MM-dd)")
            .font(.caption2)
            .foregroundStyle(.secondary)

        TextField("Number to Keep (Optional)", text: $target.retentionCount)
            .font(.system(.caption, design: .monospaced))
        Text("Leave blank to keep old archives indefinitely.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func pickArchiveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose an archive output directory")
        if panel.runModal() == .OK, let url = panel.url {
            target.filesystemPath = url.path
        }
    }
}
