import Foundation

nonisolated enum TargetNamespace: Hashable, Sendable {
    case currentUser
    case organization(String)
    case adminForUser(String)

    var displayLabel: String {
        switch self {
        case .currentUser:              "Current User"
        case .organization(let org):    "Organization: \(org)"
        case .adminForUser(let user):   "Administrator → User: \(user)"
        }
    }
}

nonisolated enum TargetCreateOutcome: Sendable {
    case created(httpsCloneURL: String, sshCloneURL: String)
    case alreadyExists(httpsCloneURL: String, sshCloneURL: String)
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
        case .unauthorized(let m): return m.map { "Authentication failed (401): \($0)" } ?? "Authentication failed (401)"
        case .forbidden(let m):    return m.map { "Permission denied (403): \($0)" } ?? "Permission denied (403)"
        case .validation(let m):   return m.map { "Invalid parameters: \($0)" } ?? "Invalid parameters (422)"
        case .network(let e):      return "Network error: \(e.localizedDescription)"
        case .decoding(let e):     return "Failed to parse response: \(e.localizedDescription)"
        case .http(let s, let m):  return m.map { "HTTP \(s)：\($0)" } ?? "HTTP \(s)"
        }
    }
}

protocol TargetProviderAPIClient: Sendable {
    nonisolated var provider: GitProvider { get }
    nonisolated func fetchTokenScopes() async throws -> Set<String>
    nonisolated func createRepo(
        name: String,
        namespace: TargetNamespace,
        isPrivate: Bool,
        description: String?
    ) async throws -> TargetCreateOutcome
}
