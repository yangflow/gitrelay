import Foundation

nonisolated struct RemoteRepo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let fullName: String
    let description: String?
    let isPrivate: Bool
    let httpsCloneURL: String
    let sshCloneURL: String
    let defaultBranch: String?
}

nonisolated enum RemoteRepoScope: Hashable, Sendable {
    case currentUser
    case organization(String)

    var displayLabel: String {
        switch self {
        case .currentUser:           String.loc("My Repositories")
        case .organization(let org): String.loc("Organization: \(org)")
        }
    }
}
