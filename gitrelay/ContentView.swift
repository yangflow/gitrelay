import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var appVM
    @State private var selectedRepoID: UUID?
    @State private var sheetMode: SheetMode?

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
        .sheet(item: $sheetMode) { mode in
            switch mode {
            case .add:
                AddEditRepoSheet(repo: nil)
            case .edit(let repo):
                AddEditRepoSheet(repo: repo)
            }
        }
        .alert(
            "发生错误",
            isPresented: $appVM.isShowingError,
            presenting: appVM.errorMessage
        ) { _ in
            Button("确定", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }
}
