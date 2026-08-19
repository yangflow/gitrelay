import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM
    @State private var selectedRepoID: UUID?
    @State private var sheetMode: SheetMode?
    @State private var browsePrefill: BrowseRemotePrefill?

    var body: some View {
        @Bindable var appVM = appVM
        NavigationSplitView {
            SidebarView(selectedRepoID: $selectedRepoID, sheetMode: $sheetMode)
        } detail: {
            DetailView(
                selectedRepoID: $selectedRepoID,
                onAdd: { sheetMode = .add }
            )
        }
        .frame(minWidth: 720, minHeight: 500)
        .onAppear {
            applyPendingMainWindowSelection()
            applyPendingBrowsePrefill()
        }
        .onChange(of: appVM.pendingMainWindowRepoID) { _, _ in
            applyPendingMainWindowSelection()
        }
        .onChange(of: appVM.pendingBrowsePrefill?.id) { _, _ in
            applyPendingBrowsePrefill()
        }
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .add:
                AddEditRepoSheet(repo: nil)
            case .edit(let repo):
                AddEditRepoSheet(repo: repo)
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

    private func applyPendingMainWindowSelection() {
        guard let repoID = appVM.pendingMainWindowRepoID else { return }
        selectedRepoID = repoID
        appVM.pendingMainWindowRepoID = nil
    }

    private func applyPendingBrowsePrefill() {
        guard let prefill = appVM.consumePendingBrowsePrefill() else { return }
        browsePrefill = prefill
        sheetMode = .browse
    }
}
