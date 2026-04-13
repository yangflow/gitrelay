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
                RepoHeaderView(repo: repo)

                Divider()

                RepoStatusSectionView(
                    repo: repo,
                    status: status,
                    isSyncing: isSyncing,
                    records: records,
                    nextFireDate: appVM.nextFireDate(for: repo.id),
                    onSyncNow: { appVM.triggerSync(repoID: repo.id) },
                    onCancel: { appVM.cancelSync(repoID: repo.id) }
                )

                Divider()

                BranchListView(branches: detailVM.branches, isLoading: detailVM.isLoadingBranches)

                Divider()

                SyncLogView(records: records)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: repo.id) {
            await detailVM.loadBranches(for: repo.id)
        }
        .onChange(of: status) {
            if case .idle = status {
                Task { await detailVM.loadBranches(for: repo.id) }
            }
        }
    }
}
