import SwiftUI

struct DetailView: View {
    @Environment(AppViewModel.self) private var appVM
    @Binding var selectedRepoID: UUID?
    let onAdd: () -> Void
    var onExamplePrefill: ((RepoSourceDropPrefill) -> Void)? = nil
    var isDropTargeted: Bool = false

    var body: some View {
        Group {
            if let id = selectedRepoID, let repo = appVM.repos.first(where: { $0.id == id }) {
                RepoDetailView(repo: repo)
            } else {
                EmptyStateView(
                    onAdd: onAdd,
                    onExamplePrefill: onExamplePrefill,
                    isDropTargeted: isDropTargeted
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
