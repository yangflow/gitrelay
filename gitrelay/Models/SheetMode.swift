import Foundation

enum SheetMode: Identifiable {
    case add
    case edit(RepoConfig)

    var id: String {
        switch self {
        case .add:         "add"
        case .edit(let r): "edit-\(r.id)"
        }
    }
}
