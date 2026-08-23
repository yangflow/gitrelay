import SwiftUI
import UniformTypeIdentifiers

private struct SidebarColumnWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentView: View {
    @Environment(MirrorLibraryModel.self) private var library
    @Environment(MirrorOperationsController.self) private var operations
    @Environment(AppIssueModel.self) private var issues
    @Environment(OrgDiscoveryController.self) private var orgDiscovery
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(AppPreferencesModel.self) private var preferences
    @Environment(\.openWindow) private var openWindow
    @State private var sheetMode: SheetMode?
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var issues = issues
        NavigationSplitView {
            sidebarColumn
        } content: {
            mirrorListPane
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        } detail: {
            mirrorDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .uiTestWindowSizing()
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
            workspace.reconcileLibrary()
            applyPendingMainWindowSelection()
            applyPendingEditFocusAuth()
            applyPendingOpenAddRepository()
            applyPendingFocusSearch()
        }
        .onChange(of: library.mirrors.map(\.id)) { _, _ in
            workspace.reconcileLibrary()
        }
        .onChange(of: workspace.pendingMirrorSelectionID) { _, _ in
            applyPendingMainWindowSelection()
        }
        .onChange(of: workspace.pendingEditCredentialsMirrorID) { _, _ in
            applyPendingEditFocusAuth()
        }
        .onChange(of: workspace.pendingOpenAddMirror) { _, isPending in
            guard isPending else { return }
            applyPendingOpenAddRepository()
        }
        .onChange(of: workspace.pendingFocusSearch) { _, isPending in
            guard isPending else { return }
            applyPendingFocusSearch()
        }
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .edit(let repo, let focusAuth):
                MirrorEditorSheet(
                    repo: repo,
                    focusAuth: focusAuth,
                    defaultPolicy: preferences.defaultPolicyStore.preferences
                )
            }
        }
        .alert(
            "An Error Occurred",
            isPresented: $issues.isShowingError,
            presenting: issues.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
        .sheet(item: Binding(
            get: { operations.presentedDestructiveConfirmation },
            // Buttons own the lifecycle; ignore SwiftUI writes so confirming one
            // queued prompt cannot cancel the next via a transient nil set.
            set: { _ in }
        )) { request in
            DestructivePushConfirmationSheet(
                repoName: request.repoName,
                targetURL: request.targetURL,
                plan: request.plan,
                onDecision: { operations.resolvePendingDestructivePush($0) }
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: Binding(
            get: { orgDiscovery.presentedDiscovery },
            set: { _ in }
        )) { item in
            OrgDiscoverySheet(
                item: item,
                canJoinAndSync: orgDiscovery.canJoinAndSync(item),
                onDecision: { orgDiscovery.resolve($0) }
            )
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Columns

    private var sidebarColumn: some View {
        MirrorSmartViewSidebar()
            .gitRelaySidebarColumnWidth(ideal: workspace.windowLayout.sidebarWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SidebarColumnWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(SidebarColumnWidthKey.self) { width in
                workspace.windowLayout.sidebarWidth = width
            }
    }

    // MARK: - List and detail

    private var mirrorListPane: some View {
        MirrorListView(
            onOpen: { select(repoID: $0) },
            onAdd: { openAddSheet(prefill: nil) },
            onEdit: { sheetMode = .edit($0, focusAuth: false) },
            onExamplePrefill: { openAddSheet(prefill: $0) },
            isDropTargeted: isDropTargeted
        )
    }

    @ViewBuilder
    private var mirrorDetailPane: some View {
        if let selectedMirrorID = workspace.selectedMirrorID,
           let repo = library.mirror(id: selectedMirrorID) {
            RepoDetailPane(
                repo: repo,
                onBack: { select(repoID: nil) },
                onEdit: { sheetMode = .edit(repo, focusAuth: false) }
            )
        } else {
            PaneEmptyStateView(
                systemImage: "square.stack.3d.up",
                message: String.loc("Select a Mirror")
            )
        }
    }

    // MARK: - Navigation

    private func select(repoID: UUID?) {
        workspace.selectMirror(repoID)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            guard let prefill = await RepoDropImport.prefill(from: providers) else { return }
            openAddSheet(prefill: prefill)
        }
        return true
    }

    private func openAddSheet(prefill: RepoSourceDropPrefill?) {
        workspace.requestOpenAddMirror(prefill: prefill)
    }

    private func applyPendingMainWindowSelection() {
        guard let repoID = workspace.consumePendingMirrorSelection() else { return }
        select(repoID: repoID)
    }

    private func applyPendingEditFocusAuth() {
        guard let repoID = workspace.consumePendingEditCredentialsMirrorID() else { return }
        select(repoID: repoID)
        guard let repo = library.mirror(id: repoID) else { return }
        sheetMode = .edit(repo, focusAuth: true)
    }

    private func applyPendingOpenAddRepository() {
        guard workspace.consumePendingOpenAddMirror() else { return }
        openWindow(id: "add-mirror")
    }

    /// The list column is persistent in the continuity workspace, so the list
    /// itself consumes the pending focus request.
    private func applyPendingFocusSearch() {
        guard workspace.pendingFocusSearch else { return }
    }
}

private extension View {
    @ViewBuilder
    func uiTestWindowSizing() -> some View {
        #if DEBUG
        background(UITestWindowSizeConfigurator())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct UITestWindowSizeConfigurator: NSViewRepresentable {
    final class Coordinator {
        var configured = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configure(view, context: context)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configure(view, context: context)
    }

    private func configure(_ view: NSView, context: Context) {
        guard !context.coordinator.configured else { return }
        let environment = ProcessInfo.processInfo.environment
        guard environment["GITRELAY_UI_TEST_MODE"] == "1",
              let widthText = environment["GITRELAY_UI_TEST_WINDOW_WIDTH"],
              let heightText = environment["GITRELAY_UI_TEST_WINDOW_HEIGHT"],
              let width = Double(widthText),
              let height = Double(heightText) else { return }

        DispatchQueue.main.async {
            guard let window = view.window else { return }
            context.coordinator.configured = true
            window.setContentSize(NSSize(width: width, height: height))
            window.center()
        }
    }
}
#endif
