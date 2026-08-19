import SwiftUI

enum SidebarDisplayMode: String, CaseIterable, Identifiable {
    case all = "所有"
    case byTag = "按标签分组"

    var id: String { rawValue }
}

private struct TagGroupSheetItem: Identifiable {
    let tag: String?
    var id: String { tag ?? "__untagged__" }
}

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selectedRepoID: UUID?
    @Binding var sheetMode: SheetMode?

    @State private var displayMode: SidebarDisplayMode = .all
    @State private var pendingDeleteID: UUID?
    @State private var showDeleteAlert = false
    @State private var batchFrequencyGroup: TagGroupSheetItem?

    var body: some View {
        VStack(spacing: 0) {
            Picker("显示", selection: $displayMode) {
                ForEach(SidebarDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $selectedRepoID) {
                switch displayMode {
                case .all:
                    allReposList
                case .byTag:
                    groupedReposList
                }
            }
            .listStyle(.sidebar)

            if let pauseReason = appVM.scheduledSyncPauseReason {
                Divider()
                Label(pauseReason.displayMessage, systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !appVM.repos.isEmpty {
                Divider()
                SyncHealthSummaryView(summary: appVM.healthSummary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("手动添加", systemImage: "plus") { sheetMode = .add }
                    .help("手动添加仓库")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("浏览远端仓库", systemImage: "magnifyingglass") { sheetMode = .browse }
                    .help("从 GitHub / GitLab 浏览并选择")
            }
            ToolbarItem(placement: .automatic) {
                Button("全部同步", systemImage: "arrow.triangle.2.circlepath") {
                    appVM.triggerSyncAll()
                }
                .disabled(appVM.repos.isEmpty)
            }
            if displayMode == .byTag {
                ToolbarItem(placement: .automatic) {
                    tagGroupToolbarMenu
                }
            }
        }
        .sheet(item: $batchFrequencyGroup) { group in
            EditTagGroupFrequencySheet(
                tag: group.tag,
                repoCount: appVM.repos(matchingTag: group.tag).count
            )
        }
        .alert("删除仓库", isPresented: $showDeleteAlert, presenting: pendingDeleteID) { id in
            Button("删除", role: .destructive) {
                if selectedRepoID == id { selectedRepoID = nil }
                appVM.deleteRepo(id: id)
            }
            Button("取消", role: .cancel) { }
        } message: { id in
            let name = appVM.repos.first(where: { $0.id == id })?.name ?? ""
            Text("确认删除「\(name)」?本地镜像缓存也将被删除,此操作不可撤销。")
        }
    }

    @ViewBuilder
    private var allReposList: some View {
        ForEach(appVM.repos) { repo in
            repoRow(repo)
        }
    }

    @ViewBuilder
    private var groupedReposList: some View {
        let sections = RepoTagGrouping.sections(from: appVM.repos)
        if sections.isEmpty {
            ContentUnavailableView("暂无仓库", systemImage: "folder")
        } else {
            ForEach(sections) { section in
                Section {
                    ForEach(section.repos) { repo in
                        repoRow(repo)
                    }
                } header: {
                    tagSectionHeader(section)
                }
            }
        }
    }

    private func tagSectionHeader(_ section: RepoTagGrouping.Section) -> some View {
        HStack(spacing: 6) {
            if section.tag != nil {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(section.title)
            Spacer()
            Text("\(section.repos.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            tagGroupContextMenu(tag: section.tag, repoCount: section.repos.count)
        }
    }

    @ViewBuilder
    private func tagGroupContextMenu(tag: String?, repoCount: Int) -> some View {
        Button("同步此组") {
            appVM.triggerSync(matchingTag: tag)
        }
        .disabled(repoCount == 0)

        Button("校验此组") {
            appVM.triggerVerify(matchingTag: tag)
        }
        .disabled(repoCount == 0)

        Divider()

        Button("编辑组内所有仓库频率...") {
            batchFrequencyGroup = TagGroupSheetItem(tag: tag)
        }
        .disabled(repoCount == 0)
    }

    private var tagGroupToolbarMenu: some View {
        Menu("组操作", systemImage: "tag") {
            ForEach(RepoTagGrouping.sections(from: appVM.repos)) { section in
                Menu("\(section.title) (\(section.repos.count))") {
                    tagGroupContextMenu(tag: section.tag, repoCount: section.repos.count)
                }
            }
        }
        .disabled(appVM.repos.isEmpty)
    }

    private func repoRow(_ repo: RepoConfig) -> some View {
        let status = appVM.statuses[repo.id] ?? .unknown
        return RepoRowView(
            repo: repo,
            status: status,
            onSyncNow: { appVM.triggerSync(repoID: repo.id) },
            onVerifyNow: { appVM.triggerVerify(repoID: repo.id) },
            onEdit: { sheetMode = .edit(repo) },
            onDelete: {
                pendingDeleteID = repo.id
                showDeleteAlert = true
            }
        )
        .tag(repo.id)
    }
}
