import SwiftUI

struct RepoDetailView: View {
    let repo: RepoConfig
    @Environment(AppViewModel.self) private var appVM
    @Environment(WindowLayoutStore.self) private var windowLayout

    @State private var detailVM = RepoDetailViewModel()
    @State private var selectedTab: RepoDetailTab = .overview
    @State private var scrollToSyncLogToken: UUID?
    @State private var didRestoreDetailTab = false

    private var status: SyncStatus { appVM.statuses[repo.id] ?? .unknown }
    private var records: [SyncRecord] { appVM.records[repo.id] ?? [] }
    private var isSyncing: Bool { appVM.inProgressSyncIDs.contains(repo.id) }
    private var isVerifying: Bool { appVM.inProgressVerifyIDs.contains(repo.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker(String(localized: "Detail Page"), selection: $selectedTab) {
                ForEach(RepoDetailTab.allCases) { tab in
                    Text(tab.localizedTitle).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.regular)
            .accessibilityLabel(String(localized: "Detail Page"))
            .padding(.horizontal, DesignTokens.Spacing.detailContent)
            .padding(.top, DesignTokens.Spacing.sm)
            .padding(.bottom, DesignTokens.Spacing.xs)

            ScrollViewReader { proxy in
                Form {
                    switch selectedTab {
                    case .overview:
                        overviewSections
                    case .releases:
                        releasesSections
                    }
                }
                .formStyle(.grouped)
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
        .onAppear {
            restoreDetailTabIfNeeded()
        }
        .onChange(of: selectedTab) { _, newValue in
            guard didRestoreDetailTab else { return }
            windowLayout.detailTab = newValue
        }
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

    @ViewBuilder
    private var overviewSections: some View {
        Section {
            RepoHeaderView(repo: repo, recentSyncRecords: records)
        }

        Section {
            RepoStatusSectionView(
                repo: repo,
                status: status,
                isSyncing: isSyncing,
                isVerifying: isVerifying,
                records: records,
                syncPhase: appVM.syncPhases[repo.id],
                nextFireDate: appVM.nextFireDate(for: repo.id),
                onSyncNow: { appVM.triggerSync(repoID: repo.id) },
                onVerifyNow: { appVM.triggerVerify(repoID: repo.id) },
                onCancel: { appVM.cancelSync(repoID: repo.id) },
                onReenterCredentials: { appVM.requestReenterCredentials(repoID: repo.id) },
                onOpenLog: { scrollToSyncLog() }
            )
        } header: {
            Text(String(localized: "Status"))
        }

        Section {
            SyncHistorySparklineView(
                sparkline: SyncHistorySparkline.make(from: repo.dailySyncOutcomes)
            )
        } header: {
            Text(String(localized: "Syncs in the Last 30 Days"))
        }

        Section {
            BranchListView(branches: detailVM.branches, isLoading: detailVM.isLoadingBranches)
        } header: {
            Text(String(localized: "Branches"))
        }

        Section {
            SyncLogView(records: records)
                .id(RepoDetailScrollTarget.syncLog)
        } header: {
            Text(String(localized: "Sync Log"))
        }
    }

    @ViewBuilder
    private var releasesSections: some View {
        Section {
            RepoHeaderView(repo: repo, recentSyncRecords: records)
        }

        Section {
            ReleaseMirrorStatusView(
                repo: repo,
                statuses: detailVM.releaseStatuses,
                isSyncing: isSyncing
            )
        } header: {
            Text(String(localized: "Releases"))
        }
    }

    private func restoreDetailTabIfNeeded() {
        guard !didRestoreDetailTab else { return }
        selectedTab = windowLayout.detailTab
        didRestoreDetailTab = true
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

private extension RepoDetailTab {
    var localizedTitle: String {
        switch self {
        case .overview:
            String(localized: "Overview")
        case .releases:
            String(localized: "Releases")
        }
    }
}
