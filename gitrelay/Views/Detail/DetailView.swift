import SwiftUI

struct DetailView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selectedRepoID: UUID?
    let onAdd: () -> Void
    let onBrowse: () -> Void
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    var body: some View {
        Group {
            if let id = selectedRepoID, let repo = appVM.repos.first(where: { $0.id == id }) {
                RepoDetailView(repo: repo)
            } else {
                EmptyStateView(
                    onExamplePrefill: onExamplePrefill,
                    isDropTargeted: isDropTargeted
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            // Pin Add / Browse / Sync All on the detail toolbar only so sidebar
            // collapse never reparents these controls into the window chrome.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onAdd()
                } label: {
                    Label(String(localized: "Add Manually"), systemImage: "plus")
                }
                .help(String(localized: "Add a Repository Manually"))
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onBrowse()
                } label: {
                    Label(String(localized: "Browse Remote Repositories"), systemImage: "magnifyingglass")
                }
                .help(String(localized: "Browse and select from GitHub or GitLab"))
            }
            if !appVM.repos.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        appVM.triggerSyncAll()
                    } label: {
                        Label(String(localized: "Sync All"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help(String(localized: "Sync All"))
                }
            }
        }
    }
}
