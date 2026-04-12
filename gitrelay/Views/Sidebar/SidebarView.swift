import SwiftUI

struct SidebarView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selectedRepoID: UUID?
    @Binding var sheetMode: SheetMode?

    @State private var pendingDeleteID: UUID?
    @State private var showDeleteAlert = false

    var body: some View {
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheetMode = .add } label: {
                    Label("添加", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button { appVM.triggerSyncAll() } label: {
                    Label("全部同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(appVM.repos.isEmpty)
            }
        }
        .alert("删除仓库", isPresented: $showDeleteAlert, presenting: pendingDeleteID) { id in
            Button("删除", role: .destructive) {
                if selectedRepoID == id { selectedRepoID = nil }
                appVM.deleteRepo(id: id)
            }
            Button("取消", role: .cancel) {}
        } message: { id in
            let name = appVM.repos.first(where: { $0.id == id })?.name ?? ""
            Text("确认删除「\(name)」？本地镜像缓存也将被删除，此操作不可撤销。")
        }
    }
}
