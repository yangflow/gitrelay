import SwiftUI

struct ReleaseMirrorStatusView: View {
    let repo: RepoConfig
    let statuses: [ReleaseTargetMirrorStatus]
    let isSyncing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if !repo.mirrorReleases {
                ContentUnavailableView {
                    Label("Release Mirroring Is Disabled", systemImage: "shippingbox")
                } description: {
                    Text("Enable “Mirror Releases and Binary Assets” when editing the repository to copy Release attachments to each enabled target during sync.")
                }
            } else if statuses.isEmpty {
                ContentUnavailableView {
                    Label("No Release Sync Records Yet", systemImage: "clock")
                } description: {
                    Text("After a sync, the Release and asset progress for each target will appear here.")
                }
            } else {
                ForEach(statuses, id: \.targetID) { status in
                    targetSection(status)
                }
            }
        }
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
                    Text("Last \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
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
                Text("Waiting for the First Release Sync…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(status.tags, id: \.tagName) { tag in
                    tagRow(tag)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(
            DesignTokens.Surface.suggestionFill,
            in: RoundedRectangle(
                cornerRadius: DesignTokens.CornerRadius.banner,
                style: .continuous
            )
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
                    Text(String(localized: "\(tag.completedCount)/\(tag.totalAssets) assets"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "No Attachments"))
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
        case .pending:  String(localized: "Pending")
        case .syncing:  String(localized: "Syncing")
        case .synced:   String(localized: "Synced")
        case .partial:  String(localized: "Partially Completed")
        case .failed:   String(localized: "Failed")
        }
    }
}
