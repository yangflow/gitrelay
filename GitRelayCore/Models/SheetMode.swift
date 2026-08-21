import Foundation

enum SheetMode: Identifiable {
    case add
    case edit(RepoConfig, focusAuth: Bool)
    case browse

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let repo, let focusAuth):
            return "edit-\(repo.id)-auth:\(focusAuth)"
        case .browse:
            return "browse"
        }
    }
}
