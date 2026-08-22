import AppKit
import SwiftUI

struct RepoHeaderView: View {
    let repo: RepoConfig
    var recentSyncRecords: [SyncRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(repo.name)
                .font(.title3)
                .fontWeight(.semibold)

            LabeledContent(String.loc("Source")) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    locationText(repo.srcURL)
                    openButton(
                        for: RepoOpenLocation.source(of: repo),
                        sideLabel: String.loc("Source"),
                        help: repo.srcURL
                    )
                }
            }

            if repo.targets.count == 1 {
                LabeledContent(String.loc("Target")) {
                    targetRow(repo.targets[0])
                }
            } else {
                LabeledContent(String.loc("Targets (\(repo.targets.count))")) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        ForEach(Array(repo.targets.enumerated()), id: \.element.id) { index, target in
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Text(String.loc("\(index + 1)."))
                                    .foregroundStyle(.secondary)
                                targetRow(target)
                            }
                        }
                    }
                }
            }

            if let accountLine = RepoAccountLine.resolve(for: repo) {
                Text(accountLine.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if repo.usesSelectiveRefSync {
                Label {
                    Text(repo.partialSyncWarning ?? String.loc("Partial ref sync (not a complete backup)"))
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
            if let line = record.logLines.first(where: { lfsLineIsMissingGitLFSWarning($0) }) {
                return line
            }
        }
        return nil
    }

    @ViewBuilder
    private func targetRow(_ target: MirrorTarget) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            if target.kind == .filesystem {
                Text(String.loc("Archive"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            locationText(target.displayLabel)
            if target.kind == .filesystem {
                Text(target.resolvedArchiveFormat.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !target.enabled {
                Text(String.loc("Disabled"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            openButton(
                for: RepoOpenLocation.target(target),
                sideLabel: String.loc("Target"),
                help: target.displayLabel
            )
        }
    }

    private func locationText(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    /// 打开 for a remote page, Finder wording for an archive folder, nothing
    /// when the endpoint names no place this Mac can reach.
    @ViewBuilder
    private func openButton(for location: RepoOpenLocation?, sideLabel: String, help: String) -> some View {
        if let location {
            Spacer(minLength: DesignTokens.Spacing.sm)
            Button(location.actionTitle) {
                open(location)
            }
            .buttonStyle(.link)
            .font(.caption)
            .help(help)
            .accessibilityLabel(accessibilityLabel(for: location, sideLabel: sideLabel))
        }
    }

    private func accessibilityLabel(for location: RepoOpenLocation, sideLabel: String) -> String {
        "\(location.actionTitle) \(sideLabel)"
    }

    private func open(_ location: RepoOpenLocation) {
        switch location {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
