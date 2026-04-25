import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selectedRepoID: UUID?
    @Binding var sheetMode: SheetMode?

    @State private var pendingDeleteID: UUID?
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selectedRepoID) {
                ForEach(appVM.repos) { repo in
                    let status = appVM.statuses[repo.id] ?? .unknown
                    RepoRowView(
                        repo: repo,
                        status: status,
                        onSyncNow: { appVM.triggerSync(repoID: repo.id) },
                        onEdit:    { sheetMode = .edit(repo) },
                        onDelete:  {
                            pendingDeleteID = repo.id
                            showDeleteAlert = true
                        }
                    )
                    .tag(repo.id)
                }
            }
            .listStyle(.sidebar)

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
}
