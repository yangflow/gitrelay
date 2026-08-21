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
    @State private var scrollToSyncLogToken: UUID?

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
            .padding(.horizontal, DesignTokens.Spacing.detailContent)
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.md)

            ScrollViewReader { proxy in
                ScrollView {
                    switch selectedTab {
                    case .overview:
                        overviewContent
                    case .releases:
                        releasesContent
                    }
                }
                .onChange(of: scrollToSyncLogToken) { _, token in
                    guard token != nil else { return }
                    selectedTab = .overview
                    DispatchQueue.main.async {
                        withAnimation {
                            proxy.scrollTo(RepoDetailScrollTarget.syncLog, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: repo.id) {
            await detailVM.loadBranches(for: repo.id)
            await detailVM.loadReleaseStatus(for: repo)
            applyPendingScrollToSyncLogIfNeeded()
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
        .onChange(of: appVM.pendingScrollToSyncLogRepoID) { _, repoID in
            guard repoID == repo.id else { return }
            applyPendingScrollToSyncLogIfNeeded()
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.detailSection) {
            RepoHeaderView(repo: repo, recentSyncRecords: records)

            detailDivider

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
                onCancel: { appVM.cancelSync(repoID: repo.id) },
                onReenterCredentials: { appVM.requestReenterCredentials(repoID: repo.id) },
                onOpenLog: { scrollToSyncLog() }
            )

            detailDivider

            SyncHistorySparklineView(
                sparkline: SyncHistorySparkline.make(from: repo.dailySyncOutcomes)
            )

            detailDivider

            BranchListView(branches: detailVM.branches, isLoading: detailVM.isLoadingBranches)

            detailDivider

            SyncLogView(records: records)
                .id(RepoDetailScrollTarget.syncLog)
        }
        .padding(DesignTokens.Spacing.detailContent)
    }

    private var releasesContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            RepoHeaderView(repo: repo, recentSyncRecords: records)

            ReleaseMirrorStatusView(
                repo: repo,
                statuses: detailVM.releaseStatuses,
                isSyncing: isSyncing
            )
        }
        .padding(DesignTokens.Spacing.detailContent)
    }

    private var detailDivider: some View {
        Divider()
    }

    private func scrollToSyncLog() {
        selectedTab = .overview
        scrollToSyncLogToken = UUID()
    }

    private func applyPendingScrollToSyncLogIfNeeded() {
        guard appVM.pendingScrollToSyncLogRepoID == repo.id else { return }
        _ = appVM.consumePendingScrollToSyncLogRepoID()
        scrollToSyncLog()
    }
}

private enum RepoDetailScrollTarget {
    static let syncLog = "repo-detail-sync-log"
}
