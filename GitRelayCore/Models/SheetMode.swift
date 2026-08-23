import Foundation

/// Modal sheets the main window can present. 浏览远程 is a right-pane
/// destination rather than a sheet, so it is not listed here.
enum SheetMode: Identifiable {
    case edit(MirrorSnapshot, focusAuth: Bool)

    var id: String {
        switch self {
        case .edit(let repo, let focusAuth):
            return "edit-\(repo.id)-auth:\(focusAuth)"
        }
    }
}
