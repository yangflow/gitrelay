import SwiftUI

struct ReleaseMirrorStatusView: View {
    let repo: RepoConfig
    let statuses: [ReleaseTargetMirrorStatus]
    let isSyncing: Bool

    var body: some View {
        Group {
            if !repo.mirrorReleases {
                quietEmpty(
                    symbol: "shippingbox",
                    message: String.loc("Release mirroring is off. Enable it when editing this repository.")
                )
            } else if statuses.isEmpty {
                quietEmpty(
                    symbol: "clock",
                    message: String.loc("No release syncs yet. They appear here after a sync.")
                )
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    ForEach(statuses, id: \.targetID) { status in
                        targetSection(status)
                    }
                }
            }
        }
    }

    private func quietEmpty(symbol: String, message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.md)
    }

    @ViewBuilder
    private func targetSection(_ status: ReleaseTargetMirrorStatus) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(status.targetURL)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if status.isSyncing || isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else if let lastSyncedAt = status.lastSyncedAt {
                    Text(String.loc("Last \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = status.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.StatusColor.error)
            }

            if status.tags.isEmpty {
                Text(String.loc("Waiting for the first release sync…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.tags, id: \.tagName) { tag in
                    tagRow(tag)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .gitRelayPanelSurface(
            fill: DesignTokens.Surface.panelFill,
            cornerRadius: DesignTokens.CornerRadius.banner
        )
    }

    @ViewBuilder
    private func tagRow(_ tag: ReleaseTagStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: iconName(for: tag.state))
                .foregroundStyle(color(for: tag.state))
                .frame(width: DesignTokens.Size.menuBarIconPointSize)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Text(tag.tagName)
                    .font(.system(.body, design: .monospaced))
                if tag.totalAssets > 0 {
                    Text(String.loc("\(tag.completedCount)/\(tag.totalAssets) assets"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String.loc("No Attachments"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = tag.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.StatusColor.error)
                }
            }
            Spacer()
            Text(label(for: tag.state))
                .font(.caption)
                .foregroundStyle(color(for: tag.state))
        }
    }

    private func iconName(for state: ReleaseTagSyncState) -> String {
        switch state {
        case .pending:  "clock"
        case .syncing:  "arrow.triangle.2.circlepath"
        case .synced:   "checkmark.circle.fill"
        case .partial:  "exclamationmark.circle"
        case .failed:   "xmark.circle.fill"
        }
    }

    private func color(for state: ReleaseTagSyncState) -> Color {
        switch state {
        case .pending:  DesignTokens.StatusColor.unknown
        case .syncing:  DesignTokens.StatusColor.info
        case .synced:   DesignTokens.StatusColor.success
        case .partial:  DesignTokens.StatusColor.warning
        case .failed:   DesignTokens.StatusColor.error
        }
    }

    private func label(for state: ReleaseTagSyncState) -> String {
        switch state {
        case .pending:  String.loc("Pending")
        case .syncing:  String.loc("Syncing")
        case .synced:   String.loc("Synced")
        case .partial:  String.loc("Partially Completed")
        case .failed:   String.loc("Failed")
        }
    }
}
