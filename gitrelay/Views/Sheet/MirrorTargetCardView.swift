import AppKit
import SwiftUI

/// Flat target fields for Add / Edit repository (no nested card chrome).
struct MirrorTargetFieldsView: View {
    let index: Int
    @Binding var target: MirrorTargetDraft
    let error: String?
    let canRemove: Bool
    let onRemove: () -> Void
    var showsHeader: Bool = true
    var urlFieldTitle: String? = nil
    var authPickerTitle: String? = nil

    private var resolvedURLTitle: String {
        urlFieldTitle ?? String(localized: "Target URL")
    }

    private var resolvedAuthTitle: String {
        authPickerTitle ?? String(localized: "Authentication Method")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if showsHeader {
                HStack {
                    Text("Target \(index + 1)")
                        .font(.subheadline.weight(.medium))
                    if !target.enabled {
                        Text(String(localized: "Disabled"))
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

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
                Text(String(localized: "Type"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker(String(localized: "Type"), selection: $target.kind) {
                    ForEach(MirrorTargetKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            switch target.kind {
            case .gitRemote:
                gitRemoteFields
            case .filesystem:
                filesystemFields
            }

            Toggle(String(localized: "Enabled"), isOn: $target.enabled)
        }
    }

    @ViewBuilder
    private var gitRemoteFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Text(resolvedURLTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("git@github.com:user/repo.git", text: $target.url)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            if let err = error {
                Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
            }
        }

        AuthFieldView(
            label: "Target \(index + 1)",
            remoteURL: target.url,
            mode: $target.authMode,
            keyPath: $target.keyPath,
            token: $target.token,
            pickerTitle: resolvedAuthTitle
        )
    }

    @ViewBuilder
    private var filesystemFields: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Text(String(localized: "Archive Directory"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("/Volumes/Backup/git-archives", text: $target.filesystemPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Button("Choose…") {
                    pickArchiveDirectory()
                }
            }
            if let err = error {
                Text(err).font(.caption).foregroundStyle(DesignTokens.StatusColor.error)
            }
        }

        VStack(alignment: .leading, spacing: DesignTokens.Spacing.formFieldGap) {
            Text(String(localized: "Archive Format"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(String(localized: "Archive Format"), selection: $target.archiveFormat) {
                ForEach(ArchiveFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }

        TextField("Filename Template", text: $target.filenameTemplate, prompt: Text(target.archiveFormat.defaultFilenameTemplate))
            .textFieldStyle(.roundedBorder)
            .font(.system(.caption, design: .monospaced))
        Text("Available placeholders: {name}, {date} (yyyy-MM-dd)")
            .font(.caption2)
            .foregroundStyle(.secondary)

        TextField("Number to Keep (Optional)", text: $target.retentionCount)
            .textFieldStyle(.roundedBorder)
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
