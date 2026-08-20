import SwiftUI

private enum RepoDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case releases = "Releases"

    var id: String { rawValue }
}

struct RepoDetailView: View {
    let repo: RepoConfig
    @Environment(AppViewModel.self) private var appVM

    @State private var detailVM = RepoDetailViewModel()
    @State private var selectedTab: RepoDetailTab = .overview

    private var status: SyncStatus { appVM.statuses[repo.id] ?? .unknown }
    private var records: [SyncRecord] { appVM.records[repo.id] ?? [] }
    private var isSyncing: Bool { appVM.inProgressSyncIDs.contains(repo.id) }
    private var isVerifying: Bool { appVM.inProgressVerifyIDs.contains(repo.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Detail Page", selection: $selectedTab) {
                ForEach(RepoDetailTab.allCases) { tab in
                    Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView {
                switch selectedTab {
                case .overview:
                    overviewContent
                case .releases:
                    releasesContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: repo.id) {
            await detailVM.loadBranches(for: repo.id)
            await detailVM.loadReleaseStatus(for: repo)
        }
        .onChange(of: status) {
            if case .idle = status {
                Task {
                    await detailVM.loadBranches(for: repo.id)
                    await detailVM.loadReleaseStatus(for: repo)
                }
            }
        }
        .onChange(of: repo.mirrorReleases) {
            Task { await detailVM.loadReleaseStatus(for: repo) }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            RepoHeaderView(repo: repo, recentSyncRecords: records)

            Divider()

            RepoStatusSectionView(
                repo: repo,
                status: status,
                isSyncing: isSyncing,
                isVerifying: isVerifying,
                records: records,
                syncPhase: appVM.syncPhases[repo.id],
                liveSyncLogLine: appVM.liveSyncLogLines[repo.id],
                nextFireDate: appVM.nextFireDate(for: repo.id),
                onSyncNow: { appVM.triggerSync(repoID: repo.id) },
                onVerifyNow: { appVM.triggerVerify(repoID: repo.id) },
                onCancel: { appVM.cancelSync(repoID: repo.id) }
            )

            Divider()

            SyncHistorySparklineView(
                sparkline: SyncHistorySparkline.make(from: repo.dailySyncOutcomes)
            )

            Divider()

            BranchListView(branches: detailVM.branches, isLoading: detailVM.isLoadingBranches)

            Divider()

            SyncLogView(records: records)
        }
        .padding(20)
    }

    private var releasesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            RepoHeaderView(repo: repo, recentSyncRecords: records)

            ReleaseMirrorStatusView(
                repo: repo,
                statuses: detailVM.releaseStatuses,
                isSyncing: isSyncing
            )
        }
        .padding(20)
    }
}
