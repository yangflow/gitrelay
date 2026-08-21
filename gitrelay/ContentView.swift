import SwiftUI
import UniformTypeIdentifiers

private struct SidebarColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM
    @State private var sidebarSelection: MainSidebarItem = .default
    /// Last non-transient row, so picking 浏览远程 can hand selection back.
    @State private var lastPaneSelection: MainSidebarItem = .default
    @State private var selectedRepoID: UUID?
    @State private var sheetMode: SheetMode?
    @State private var browsePrefill: BrowseRemotePrefill?
    @State private var addPrefill: RepoSourceDropPrefill?
    @State private var isDropTargeted = false
    @State private var didRestoreWindowLayout = false

    var body: some View {
        @Bindable var appVM = appVM
        NavigationSplitView {
            MainSidebarView(selection: $sidebarSelection)
                .gitRelaySidebarColumnWidth(ideal: appVM.windowLayout.sidebarWidth)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: SidebarColumnWidthKey.self, value: proxy.size.width)
                    }
                }
                .onPreferenceChange(SidebarColumnWidthKey.self) { width in
                    guard didRestoreWindowLayout else { return }
                    appVM.windowLayout.sidebarWidth = width
                }
                .gitRelayChrome(.sidebar)
        } detail: {
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gitRelayChrome(.detail)
        }
        .frame(
            minWidth: DesignTokens.Layout.windowMinWidth,
            minHeight: DesignTokens.Layout.windowMinHeight
        )
        .onDrop(
            of: [UTType.fileURL, UTType.url, UTType.plainText],
            isTargeted: $isDropTargeted
        ) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            restoreWindowLayoutIfNeeded()
            appVM.mainWindowSelectedRepoID = selectedRepoID
            applyPendingMainWindowSelection()
            applyPendingBrowsePrefill()
            applyPendingEditFocusAuth()
            applyPendingOpenAddRepository()
            applyPendingFocusSearch()
        }
        .onChange(of: sidebarSelection) { previous, current in
            handleSidebarSelectionChange(from: previous, to: current)
        }
        .onChange(of: selectedRepoID) { _, newValue in
            appVM.mainWindowSelectedRepoID = newValue
            guard didRestoreWindowLayout else { return }
            appVM.windowLayout.selectedRepoID = newValue
        }
        .onChange(of: appVM.repos.map(\.id)) { _, ids in
            appVM.windowLayout.reconcileSelection(withExistingIDs: Set(ids))
            if let selectedRepoID, !ids.contains(selectedRepoID) {
                self.selectedRepoID = nil
            }
        }
        .onChange(of: appVM.pendingMainWindowRepoID) { _, _ in
            applyPendingMainWindowSelection()
        }
        .onChange(of: appVM.pendingBrowsePrefill?.id) { _, _ in
            applyPendingBrowsePrefill()
        }
        .onChange(of: appVM.pendingEditFocusAuthRepoID) { _, _ in
            applyPendingEditFocusAuth()
        }
        .onChange(of: appVM.pendingOpenAddRepository) { _, isPending in
            guard isPending else { return }
            applyPendingOpenAddRepository()
        }
        .onChange(of: appVM.pendingFocusSidebarSearch) { _, isPending in
            guard isPending else { return }
            applyPendingFocusSearch()
        }
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .add:
                AddEditRepoSheet(repo: nil, prefill: addPrefill)
                    .onDisappear { addPrefill = nil }
            case .edit(let repo, let focusAuth):
                AddEditRepoSheet(repo: repo, focusAuth: focusAuth)
            case .browse:
                BrowseRemoteRepoSheet(prefill: browsePrefill)
            }
        }
        .alert(
            "An Error Occurred",
            isPresented: $appVM.isShowingError,
            presenting: appVM.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .sheet(item: Binding(
            get: { appVM.presentedDestructiveConfirmation },
            // Buttons own the lifecycle; ignore SwiftUI writes so confirming one
            // queued prompt cannot cancel the next via a transient nil set.
            set: { _ in }
        )) { request in
            DestructivePushConfirmationSheet(
                repoName: request.repoName,
                targetURL: request.targetURL,
                plan: request.plan,
                onConfirm: { appVM.confirmPendingDestructivePush() },
                onCancel: { appVM.cancelPendingDestructivePush() }
            )
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Right pane

    @ViewBuilder
    private var detailPane: some View {
        switch sidebarSelection {
        case .repositories, .browseRemote:
            repositoriesPane
        case .queue:
            SyncQueueView(onOpen: { select(repoID: $0) })
        case .githubAccounts, .gitlabAccounts:
            ProviderAccountsView(
                provider: sidebarSelection.provider ?? .github,
                onBrowse: { sheetMode = .browse }
            )
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private var repositoriesPane: some View {
        if let selectedRepoID, let repo = appVM.repos.first(where: { $0.id == selectedRepoID }) {
            RepoDetailPane(repo: repo) { select(repoID: nil) }
        } else {
            RepoPairTableView(
                onOpen: { select(repoID: $0) },
                onAdd: { openAddSheet(prefill: nil) },
                onEdit: { sheetMode = .edit($0, focusAuth: false) },
                onExamplePrefill: { openAddSheet(prefill: $0) },
                isDropTargeted: isDropTargeted
            )
        }
    }

    // MARK: - Navigation

    /// 浏览远程 runs the browse sheet instead of owning a pane, so selection
    /// returns to whichever row the user was on.
    private func handleSidebarSelectionChange(
        from previous: MainSidebarItem,
        to current: MainSidebarItem
    ) {
        guard current.isTransientAction else {
            lastPaneSelection = current
            return
        }
        sheetMode = .browse
        sidebarSelection = previous.isTransientAction ? lastPaneSelection : previous
    }

    private func select(repoID: UUID?) {
        sidebarSelection = .repositories
        selectedRepoID = repoID
    }

    private func restoreWindowLayoutIfNeeded() {
        guard !didRestoreWindowLayout else { return }
        appVM.windowLayout.reconcileSelection(withExistingIDs: Set(appVM.repos.map(\.id)))
        selectedRepoID = appVM.windowLayout.selectedRepoID
        didRestoreWindowLayout = true
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            guard let prefill = await RepoDropImport.prefill(from: providers) else { return }
            openAddSheet(prefill: prefill)
        }
        return true
    }

    private func openAddSheet(prefill: RepoSourceDropPrefill?) {
        addPrefill = prefill
        sheetMode = .add
    }

    private func applyPendingMainWindowSelection() {
        guard let repoID = appVM.pendingMainWindowRepoID else { return }
        select(repoID: repoID)
        appVM.mainWindowSelectedRepoID = repoID
        appVM.pendingMainWindowRepoID = nil
    }

    private func applyPendingBrowsePrefill() {
        guard let prefill = appVM.consumePendingBrowsePrefill() else { return }
        browsePrefill = prefill
        sheetMode = .browse
    }

    private func applyPendingEditFocusAuth() {
        guard let repoID = appVM.consumePendingEditFocusAuthRepoID() else { return }
        select(repoID: repoID)
        guard let repo = appVM.repos.first(where: { $0.id == repoID }) else { return }
        sheetMode = .edit(repo, focusAuth: true)
    }

    private func applyPendingOpenAddRepository() {
        guard appVM.consumePendingOpenAddRepository() else { return }
        openAddSheet(prefill: nil)
    }

    /// ⌘F focuses the pair-table search field, which only exists on the 仓库
    /// pane. Bring that pane forward and let it consume the pending flag.
    private func applyPendingFocusSearch() {
        guard appVM.pendingFocusSidebarSearch else { return }
        sidebarSelection = .repositories
        selectedRepoID = nil
    }
}
