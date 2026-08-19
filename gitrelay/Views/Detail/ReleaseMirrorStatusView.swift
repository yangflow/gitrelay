import SwiftUI

struct ReleaseMirrorStatusView: View {
    let repo: RepoConfig
    let statuses: [ReleaseTargetMirrorStatus]
    let isSyncing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        VStack(alignment: .leading, spacing: 8) {
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
                    .foregroundStyle(.red)
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
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func tagRow(_ tag: ReleaseTagStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName(for: tag.state))
                .foregroundStyle(color(for: tag.state))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.tagName)
                    .font(.system(.body, design: .monospaced))
                if tag.totalAssets > 0 {
                    Text("\(tag.completedCount)/\(tag.totalAssets) assets")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No Attachments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = tag.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
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
        case .pending:  .secondary
        case .syncing:  .blue
        case .synced:   .green
        case .partial:  .orange
        case .failed:   .red
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
