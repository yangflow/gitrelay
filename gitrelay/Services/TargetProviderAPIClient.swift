import Foundation

nonisolated enum TargetNamespace: Hashable, Sendable {
    case currentUser
    case organization(String)
    case adminForUser(String)

    var displayLabel: String {
        switch self {
        case .currentUser:              "当前用户"
        case .organization(let org):    "组织: \(org)"
        case .adminForUser(let user):   "管理员 → 用户: \(user)"
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
        case .unauthorized(let m): return m.map { "鉴权失败(401)：\($0)" } ?? "鉴权失败(401)"
        case .forbidden(let m):    return m.map { "无权限(403)：\($0)" } ?? "无权限(403)"
        case .validation(let m):   return m.map { "参数错误：\($0)" } ?? "参数错误(422)"
        case .network(let e):      return "网络错误：\(e.localizedDescription)"
        case .decoding(let e):     return "响应解析失败：\(e.localizedDescription)"
        case .http(let s, let m):  return m.map { "HTTP \(s)：\($0)" } ?? "HTTP \(s)"
        }
    }
}

protocol TargetProviderAPIClient: Sendable {
    nonisolated var provider: GitProvider { get }
    nonisolated func createRepo(
        name: String,
        namespace: TargetNamespace,
        isPrivate: Bool,
        description: String?
    ) async throws -> TargetCreateOutcome
}
