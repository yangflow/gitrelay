import SwiftUI

struct RepoHeaderView: View {
    let repo: RepoConfig
    var recentSyncRecords: [SyncRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(repo.name)
                .font(.title3)
                .fontWeight(.semibold)

            LabeledContent(String(localized: "Source")) {
                Text(repo.srcURL)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            if repo.targets.count == 1 {
                LabeledContent(String(localized: "Target")) {
                    targetLabel(repo.targets[0])
                }
            } else {
                LabeledContent(String(localized: "Targets (\(repo.targets.count))")) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        ForEach(Array(repo.targets.enumerated()), id: \.element.id) { index, target in
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Text(String(localized: "\(index + 1)."))
                                    .foregroundStyle(.secondary)
                                targetLabel(target)
                            }
                        }
                    }
                }
            }

            if repo.usesSelectiveRefSync {
                Label {
                    Text(repo.partialSyncWarning ?? String(localized: "Partial ref sync (not a complete backup)"))
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
        HStack(spacing: DesignTokens.Spacing.xs) {
            if target.kind == .filesystem {
                Text(String(localized: "Archive"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                Text(String(localized: "Disabled"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
