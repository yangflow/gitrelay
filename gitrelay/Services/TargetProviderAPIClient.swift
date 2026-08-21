import Foundation

nonisolated enum TargetNamespace: Hashable, Sendable {
    case currentUser
    case organization(String)
    case adminForUser(String)

    var displayLabel: String {
        switch self {
        case .currentUser:              String(localized: "Current User")
        case .organization(let org):    String(localized: "Organization: \(org)")
        case .adminForUser(let user):   String(localized: "Administrator → User: \(user)")
        }
    }
}

nonisolated enum TargetCreateOutcome: Sendable {
    case created(httpsCloneURL: String, sshCloneURL: String)
    case alreadyExists(httpsCloneURL: String, sshCloneURL: String)
}

/// Answer to "is this repository already there?", used by the add sheet's
/// preflight before it offers to create an empty destination.
nonisolated enum TargetRepoLookup: Sendable, Equatable {
    case found(httpsCloneURL: String, sshCloneURL: String)
    case missing
}

nonisolated enum TargetProviderAPIError: LocalizedError {
    case unauthorized(String?)
    case forbidden(String?)
    case validation(String?)
    case network(Error)
    case decoding(Error)
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let m): return m.map { String(localized: "Authentication failed (401): \($0)") } ?? String(localized: "Authentication failed (401)")
        case .forbidden(let m):    return m.map { String(localized: "Permission denied (403): \($0)") } ?? String(localized: "Permission denied (403)")
        case .validation(let m):   return m.map { String(localized: "Invalid parameters: \($0)") } ?? String(localized: "Invalid parameters (422)")
        case .network(let e):      return String(localized: "Network error: \(e.localizedDescription)")
        case .decoding(let e):     return String(localized: "Failed to parse response: \(e.localizedDescription)")
        case .http(let s, let m):  return m.map { String(localized: "HTTP \(s): \($0)") } ?? String(localized: "HTTP \(s)")
        }
    }
}

protocol TargetProviderAPIClient: Sendable {
    nonisolated var provider: GitProvider { get }
    nonisolated func fetchTokenScopes() async throws -> Set<String>
    nonisolated func fetchRepo(path: GitRemoteRepoPath) async throws -> TargetRepoLookup
    nonisolated func createRepo(
        name: String,
        namespace: TargetNamespace,
        isPrivate: Bool,
        description: String?
    ) async throws -> TargetCreateOutcome
}
