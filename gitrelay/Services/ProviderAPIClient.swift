import Foundation

nonisolated enum ProviderAPIError: LocalizedError {
    case unauthorized(String?)
    case forbidden(String?)
    case notFound(String?)
    case network(Error)
    case decoding(Error)
    case http(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .unauthorized(let msg):
            let base = String(localized: "Authentication failed (401): Make sure the token has not expired and has the correct scopes (repo + read:org for GitHub, read_api for GitLab)")
            return msg.map { String(localized: "\(base). Server message: \($0)") } ?? base
        case .forbidden(let msg):
            return msg.map { String(localized: "Permission denied or rate limited (403): \($0)") } ?? String(localized: "Permission denied or rate limited (403)")
        case .notFound(let msg):
            let base = String(localized: "Resource not found (404): Check that the username, organization, or group name is correct")
            return msg.map { String(localized: "\(base). Server message: \($0)") } ?? base
        case .network(let e):
            return String(localized: "Network request failed: \(e.localizedDescription)")
        case .decoding(let e):
            return String(localized: "Failed to parse response: \(e.localizedDescription)")
        case .http(let s, let m):
            return m.map { String(localized: "HTTP \(s): \($0)") } ?? String(localized: "HTTP \(s)")
        }
    }
}

nonisolated struct RemoteRepoPage: Sendable {
    let repos: [RemoteRepo]
    let hasMore: Bool
    let nextPage: Int
}

protocol ProviderAPIClient: Sendable {
    nonisolated var provider: GitProvider { get }
    nonisolated func fetchTokenScopes() async throws -> Set<String>
    nonisolated func fetchRepos(scope: RemoteRepoScope, page: Int, perPage: Int) async throws -> RemoteRepoPage
}
