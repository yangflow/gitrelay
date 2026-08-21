import SwiftUI

struct RepoHeaderView: View {
    let repo: RepoConfig
    var recentSyncRecords: [SyncRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(repo.name)
                .font(.title2)
                .fontWeight(.semibold)

            LabeledContent("Source") {
                Text(repo.srcURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            if repo.targets.count == 1 {
                LabeledContent("Target") {
                    targetLabel(repo.targets[0])
                }
            } else {
                LabeledContent("Targets (\(repo.targets.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(repo.targets.enumerated()), id: \.element.id) { index, target in
                            HStack(spacing: 6) {
                                Text("\(index + 1).")
                                    .foregroundStyle(.secondary)
                                targetLabel(target)
                            }
                        }
                    }
                }
            }

            if repo.usesSelectiveRefSync {
                Label {
                    Text(repo.partialSyncWarning ?? "Partial ref sync (not a complete backup)")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.StatusColor.pause)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.StatusColor.pause)
                }
            }

            if let lfsWarning = missingGitLFSWarningFromRecentSync {
                Label {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                        Text(lfsWarning)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.StatusColor.pause)
                        Text(LFSMirrorMessages.installHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DesignTokens.StatusColor.pause)
                }
            }
        }
    }

    private var missingGitLFSWarningFromRecentSync: String? {
        for record in recentSyncRecords.reversed() {
            if let line = record.logLines.first(where: LFSMirrorMessages.isMissingGitLFSWarning) {
                return line
            }
        }
        return nil
    }

    @ViewBuilder
    private func targetLabel(_ target: MirrorTarget) -> some View {
        HStack(spacing: 6) {
            if target.kind == .filesystem {
                Text("Archive")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(.rect(cornerRadius: 3))
            }
            Text(target.displayLabel)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
            if target.kind == .filesystem {
                Text(target.resolvedArchiveFormat.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !target.enabled {
                Text("Disabled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
