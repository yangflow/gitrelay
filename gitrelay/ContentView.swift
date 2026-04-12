import SwiftUI

enum SheetMode: Identifiable {
    case add
    case edit(RepoConfig)

    var id: String {
        switch self {
        case .add:         return "add"
        case .edit(let r): return "edit-\(r.id)"
        }
    }
}

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM
    @State private var selectedRepoID: UUID?
    @State private var sheetMode: SheetMode?

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedRepoID: $selectedRepoID, sheetMode: $sheetMode)
        } detail: {
            DetailView(
                selectedRepoID: $selectedRepoID,
                onAdd: { sheetMode = .add }
            )
        }
        .frame(minWidth: 720, minHeight: 500)
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .add:
                AddEditRepoSheet(repo: nil)
            case .edit(let repo):
                AddEditRepoSheet(repo: repo)
            }
        }
    }
}
