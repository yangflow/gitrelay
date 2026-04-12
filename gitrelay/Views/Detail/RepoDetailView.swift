import SwiftUI

struct RepoDetailView: View {
    let repo: RepoConfig
    @Environment(AppViewModel.self) private var appVM

    @State private var detailVM = RepoDetailViewModel()

    private var status: SyncStatus { appVM.statuses[repo.id] ?? .unknown }
    private var records: [SyncRecord] { appVM.records[repo.id] ?? [] }
    private var isSyncing: Bool { appVM.inProgressSyncIDs.contains(repo.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Status / progress / failure
                statusSection

                Divider()

                // Branch list
                BranchListView(branches: detailVM.branches, isLoading: detailVM.isLoadingBranches)

                Divider()

                // Sync log
                SyncLogView(records: records)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { detailVM.loadBranches(for: repo.id) }
        .onChange(of: status) {
            if case .idle = status { detailVM.loadBranches(for: repo.id) }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(repo.name)
                .font(.title2)
                .fontWeight(.semibold)

            LabeledContent("Source") {
                Text(repo.srcURL)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
            LabeledContent("Target") {
                Text(repo.dstURL)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isSyncing {
                syncingView
            } else if case .failed(let msg) = status {
                failureView(message: msg)
            } else {
                idleView
            }
        }
    }

    private var syncingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在同步...")
                    .font(.callout)
                if let line = records.last?.logLines.last {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("取消") { appVM.cancelSync(repoID: repo.id) }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func failureView(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text("上次同步失败")
                    .font(.callout)
                    .fontWeight(.medium)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let date = repo.lastSyncedAt {
                    Text(date.shortFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("重试") { appVM.triggerSync(repoID: repo.id) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
    }

    private var idleView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                statusLabel
                if let date = repo.lastSyncedAt {
                    Text("上次同步：\(date.shortFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let next = appVM.nextFireDate(for: repo.id) {
                    Text("下次同步：\(next.relativeFormatted)（需 App 保持运行）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("立即同步") { appVM.triggerSync(repoID: repo.id) }
                .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch status {
        case .ahead(let n):
            Label("src 领先 \(n) 个 commit", systemImage: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
                .font(.callout)
        case .idle:
            Label("已同步", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        default:
            Label("未知状态", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
