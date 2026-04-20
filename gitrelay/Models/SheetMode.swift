import Foundation

enum SheetMode: Identifiable {
    case add
    case edit(RepoConfig)
    case browse

    var id: String {
        switch self {
        case .add:         "add"
        case .edit(let r): "edit-\(r.id)"
        case .browse:      "browse"
        }
    }
}
