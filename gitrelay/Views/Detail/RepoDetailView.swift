import SwiftUI

struct RepoDetailView: View {
    let repo: MirrorSnapshot
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(MirrorSchedulingController.self) private var scheduling
    @Environment(MirrorManagementController.self) private var management
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(WindowLayoutStore.self) private var windowLayout

    @State private var detailVM = RepoDetailViewModel()
    @State private var selectedTab: RepoDetailTab = .overview
    @State private var scrollToSyncLogToken: UUID?
    @State private var didRestoreDetailTab = false
    @State private var isBranchesExpanded = false
    @State private var isLogExpanded = false

    private var status: SyncStatus { operations.statuses[repo.id] ?? .unknown }
    private var records: [SyncRecord] { operations.records[repo.id] ?? [] }
    private var isSyncing: Bool { operations.inProgressSyncIDs.contains(repo.id) }
    private var isVerifying: Bool { operations.inProgressVerifyIDs.contains(repo.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if repo.mirrorReleases {
                Picker(String.loc("Detail Page"), selection: $selectedTab) {
                    ForEach(RepoDetailTab.allCases) { tab in
                        Text(tab.localizedTitle).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.regular)
                .accessibilityLabel(String.loc("Detail Page"))
                .padding(.horizontal, DesignTokens.Spacing.detailContent)
                .padding(.top, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.sm)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.detailSection) {
                        switch selectedTab {
                        case .overview:
                            overviewSections
                        case .releases:
                            releasesSections
                        }
                    }
                    .frame(maxWidth: DesignTokens.Layout.repoDetailContentMaxWidth, alignment: .leading)
                    .padding(.horizontal, DesignTokens.Spacing.detailContent)
                    .padding(
                        .top,
                        repo.mirrorReleases
                            ? DesignTokens.Spacing.sm
                            : DesignTokens.Spacing.lg
                    )
                    .padding(.bottom, DesignTokens.Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: scrollToSyncLogToken) { _, token in
                    guard token != nil else { return }
                    selectedTab = .overview
                    isLogExpanded = true
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
            normalizeTabForRepository()
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
            normalizeTabForRepository()
            Task { await detailVM.loadReleaseStatus(for: repo) }
        }
        .onChange(of: workspace.pendingScrollToLogMirrorID) { _, repoID in
            guard repoID == repo.id else { return }
            applyPendingScrollToSyncLogIfNeeded()
        }
    }

    @ViewBuilder
    private var overviewSections: some View {
        decisionSection
        destinationsSection
        activitySection
    }

    private var decisionSection: some View {
        detailSection(String.loc("Status")) {
            RepoStatusSectionView(
                repo: repo,
                status: status,
                isSyncing: isSyncing,
                isVerifying: isVerifying,
                records: records,
                syncPhase: operations.syncPhases[repo.id],
                nextFireDate: scheduling.nextFireDate(mirrorID: repo.id),
                onSyncNow: { operations.triggerSync(mirrorID: repo.id) },
                onVerifyNow: { operations.triggerVerify(mirrorID: repo.id) },
                onCancel: { operations.cancelSync(mirrorID: repo.id) },
                onReenterCredentials: { workspace.requestEditCredentials(mirrorID: repo.id) },
                onOpenLog: { scrollToSyncLog() },
                onCopyFailure: copyFailureAction
            )
        }
    }

    private var destinationsSection: some View {
        detailSection(String.loc("Mirror Path")) {
            RepoHeaderView(repo: repo, recentSyncRecords: records)
        }
    }

    private var activitySection: some View {
        detailSection(String.loc("Activity")) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                activityMetrics

                Divider()

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    inlineSectionLabel(
                        String.loc("Syncs in the Last 30 Days"),
                        systemImage: "chart.bar.xaxis"
                    )
                    SyncHistorySparklineView(sparkline: historySparkline)
                        .frame(minHeight: 72, alignment: .topLeading)
                }

                Divider()

                branchesDisclosure

                Divider()

                logDisclosure
            }
        }
    }

    @ViewBuilder
    private var releasesSections: some View {
        detailSection(String.loc("Mirror Path")) {
            RepoHeaderView(repo: repo, recentSyncRecords: records)
        }

        detailSection(String.loc("Releases"), usesSurface: false) {
            ReleaseMirrorStatusView(
                repo: repo,
                statuses: detailVM.releaseStatuses,
                isSyncing: isSyncing
            )
        }
    }

    private var activityMetrics: some View {
        HStack(spacing: 0) {
            activityMetric(
                value: historySuccessCount,
                title: String.loc("Succeeded"),
                tint: DesignTokens.StatusColor.success
            )
            metricDivider
            activityMetric(
                value: historyFailureCount,
                title: String.loc("Failed"),
                tint: DesignTokens.StatusColor.escalatedFailure
            )
            metricDivider
            activityMetric(
                value: detailVM.branches.count,
                title: String.loc("Branches"),
                tint: Color.accentColor
            )
            metricDivider
            activityMetric(
                value: records.count,
                title: String.loc("Sync Log"),
                tint: Color.secondary
            )
        }
    }

    private func activityMetric(value: Int, title: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
            Text(value, format: .number)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignTokens.Spacing.sm)
    }

    private var metricDivider: some View {
        Divider()
            .frame(height: 36)
    }

    private var branchesDisclosure: some View {
        DisclosureGroup(isExpanded: $isBranchesExpanded) {
            BranchListView(branches: detailVM.branches, isLoading: detailVM.isLoadingBranches)
                .padding(.top, DesignTokens.Spacing.sm)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Label(String.loc("Branches"), systemImage: "arrow.branch")
                    .font(.callout.weight(.medium))
                Spacer(minLength: DesignTokens.Spacing.md)
                Text(branchesSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var branchesSummary: String {
        if detailVM.isLoadingBranches {
            return String.loc("Loading...")
        }
        if detailVM.branches.isEmpty {
            return String.loc("No Branches Detected (Visible After Sync)")
        }
        return String(format: String.loc("%lld branches"), detailVM.branches.count)
    }

    private var logDisclosure: some View {
        DisclosureGroup(isExpanded: $isLogExpanded) {
            SyncLogView(records: records)
                .padding(.top, DesignTokens.Spacing.sm)
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Label(String.loc("Sync Log"), systemImage: "doc.text.magnifyingglass")
                    .font(.callout.weight(.medium))
                Spacer(minLength: DesignTokens.Spacing.md)
                Text(records.count, format: .number)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .id(RepoDetailScrollTarget.syncLog)
    }

    private var historySparkline: SyncHistorySparkline {
        SyncHistorySparkline.make(from: repo.dailySyncOutcomes)
    }

    private var historySuccessCount: Int {
        historySparkline.days.reduce(0) { $0 + $1.successes }
    }

    private var historyFailureCount: Int {
        historySparkline.days.reduce(0) { $0 + $1.failures }
    }

    private func inlineSectionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ title: String? = nil,
        usesSurface: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            if let title {
                Text(title)
                    .font(.headline)
            }

            if usesSurface {
                content()
                    .padding(DesignTokens.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gitRelayPanelSurface(cornerRadius: DesignTokens.CornerRadius.panel)
            } else {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func restoreDetailTabIfNeeded() {
        guard !didRestoreDetailTab else { return }
        selectedTab = windowLayout.detailTab
        didRestoreDetailTab = true
    }

    private func normalizeTabForRepository() {
        if !repo.mirrorReleases, selectedTab == .releases {
            selectedTab = .overview
        }
    }

    private func scrollToSyncLog() {
        selectedTab = .overview
        isLogExpanded = true
        scrollToSyncLogToken = UUID()
    }

    /// 复制这次失败 builds its payload on the press, not on every body pass: it
    /// may have to read the log file for a failure from an earlier session.
    private var copyFailureAction: (() -> Void)? {
        guard management.hasFailureToCopy(mirrorID: repo.id) else { return nil }
        return {
            guard let text = management.failureCopyText(mirrorID: repo.id) else { return }
            ClipboardService.copy(text)
        }
    }

    private func applyPendingScrollToSyncLogIfNeeded() {
        guard workspace.pendingScrollToLogMirrorID == repo.id else { return }
        _ = workspace.consumePendingScrollToLogMirrorID()
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
            String.loc("Overview")
        case .releases:
            String.loc("Releases")
        }
    }
}
