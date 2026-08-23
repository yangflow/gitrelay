import AppKit
import SwiftUI

/// The mirror route is the repository's identity: source first, then every
/// destination, with secondary account and capability warnings beneath it.
struct RepoHeaderView: View {
    let repo: MirrorSnapshot
    var recentSyncRecords: [SyncRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            endpointRow(
                role: String.loc("Source"),
                label: MirrorSummaryProjection.sourceLabel(for: repo.srcURL),
                provider: GitRemoteHost.inferredProvider(fromRemoteURL: repo.srcURL),
                location: RepoOpenLocation.source(of: repo),
                help: repo.srcURL
            )

            HStack(spacing: DesignTokens.Spacing.sm) {
                Color.clear.frame(width: 58, height: 1)
                Image(systemName: "arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            ForEach(Array(repo.targets.enumerated()), id: \.element.id) { index, target in
                endpointRow(
                    role: targetRole(index: index),
                    label: MirrorSummaryProjection.targetLabel(for: target),
                    provider: MirrorSummaryProjection.targetProvider(for: target),
                    location: RepoOpenLocation.target(target),
                    help: target.displayLabel,
                    target: target
                )
            }

            if let accountLine = RepoAccountLine.resolve(for: repo) {
                Divider()
                Text(accountLine.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if repo.usesSelectiveRefSync {
                warningLabel(
                    repo.partialSyncWarning ?? String.loc("Partial ref sync (not a complete backup)"),
                    detail: nil
                )
            }

            if let lfsWarning = missingGitLFSWarningFromRecentSync {
                warningLabel(lfsWarning, detail: LFSMirrorMessages.installHint)
            }
        }
    }

    private func endpointRow(
        role: String,
        label: String,
        provider: GitProvider?,
        location: RepoOpenLocation?,
        help: String,
        target: MirrorTarget? = nil
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(role)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            ProviderIdentityIcon(provider: provider, size: 14)
                .frame(width: 16)

            Text(label)
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            if let target, target.kind == .filesystem {
                Text(target.resolvedArchiveFormat.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let target, !target.enabled {
                Text(String.loc("Disabled"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            if let target {
                destinationHealth(targetID: target.id)
            }

            if let location {
                Button(location.actionTitle) {
                    open(location)
                }
                .buttonStyle(.link)
                .font(.caption)
                .help(help)
                .accessibilityLabel("\(location.actionTitle) \(role)")
            }
        }
    }

    @ViewBuilder
    private func destinationHealth(targetID: UUID) -> some View {
        if let health = repo.health.destinations.first(where: { $0.destinationID == targetID }) {
            if case .diverged = health.integrity {
                Label(String.loc("Diverged"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.StatusColor.diverged)
            } else if health.lastFailure != nil {
                Label(String.loc("Failed"), systemImage: "xmark.circle.fill")
                    .foregroundStyle(DesignTokens.StatusColor.error)
            } else if let date = health.lastSuccessfulAt {
                Text(date, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
            } else {
                Text(String.loc("Never Run"))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(String.loc("Never Run"))
                .foregroundStyle(.secondary)
        }
    }

    private func targetRole(index: Int) -> String {
        guard repo.targets.count > 1 else { return String.loc("Target") }
        return String(format: String.loc("Target %lld"), index + 1)
    }

    private func warningLabel(_ title: String, detail: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.StatusColor.pause)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.StatusColor.pause)
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

    private func open(_ location: RepoOpenLocation) {
        switch location {
        case .web(let url):
            NSWorkspace.shared.open(url)
        case .revealInFinder(let url):
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
