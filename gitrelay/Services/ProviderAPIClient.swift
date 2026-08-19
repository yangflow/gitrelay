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
            let base = "鉴权失败(401)：请确认 Token 未过期且包含正确权限(GitHub 需 repo + read:org，GitLab 需 read_api)"
            return msg.map { "\(base)。服务器信息：\($0)" } ?? base
        case .forbidden(let msg):
            return msg.map { "无权限或被限流(403)：\($0)" } ?? "无权限或被限流(403)"
        case .notFound(let msg):
            let base = "资源不存在(404)：检查用户名或组织/群组名是否正确"
            return msg.map { "\(base)。服务器信息：\($0)" } ?? base
        case .network(let e):
            return "网络请求失败：\(e.localizedDescription)"
        case .decoding(let e):
            return "响应解析失败：\(e.localizedDescription)"
        case .http(let s, let m):
            return m.map { "HTTP \(s)：\($0)" } ?? "HTTP \(s)"
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
