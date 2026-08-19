import SwiftUI

struct ReleaseMirrorStatusView: View {
    let repo: RepoConfig
    let statuses: [ReleaseTargetMirrorStatus]
    let isSyncing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !repo.mirrorReleases {
                ContentUnavailableView {
                    Label("Release 镜像未启用", systemImage: "shippingbox")
                } description: {
                    Text("在编辑仓库中开启「镜像 Releases 及二进制 assets」，同步时会将 Release 附件复制到每个已启用目标。")
                }
            } else if statuses.isEmpty {
                ContentUnavailableView {
                    Label("尚无 Release 同步记录", systemImage: "clock")
                } description: {
                    Text("执行一次同步后，此处会显示各目标的 Release 与 asset 进度。")
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
                    Text("上次 \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
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
                Text("等待首次 Release 同步…")
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
                    Text("无附件")
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
        case .pending:  "待同步"
        case .syncing:  "同步中"
        case .synced:   "已同步"
        case .partial:  "部分完成"
        case .failed:   "失败"
        }
    }
}
