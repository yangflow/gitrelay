import Foundation

nonisolated struct TokenScopeValidation: Hashable, Sendable {
    let grantedScopes: Set<String>
    let missingRequiredScopes: [String]

    var isFullyAuthorized: Bool { missingRequiredScopes.isEmpty }

    var sortedGrantedScopes: [String] {
        grantedScopes.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var bannerText: String {
        let scopeList = sortedGrantedScopes.joined(separator: ", ")
        if isFullyAuthorized {
            return "Token 有效, scopes = [\(scopeList)]"
        }
        let missing = missingRequiredScopes.joined(separator: ", ")
        if scopeList.isEmpty {
            return "Token 有效, 但无法读取 scopes; 缺少必需权限: \(missing)"
        }
        return "Token 有效, scopes = [\(scopeList)]; 缺少必需权限: \(missing)"
    }
}

nonisolated enum ProviderTokenUsage: Hashable, Sendable {
    case sourceListing(provider: GitProvider, organizationScope: Bool)
    case giteaTargetCreate
    /// Register / manage repository webhooks (extra scope — must be disclosed in UI).
    case webhookRegistration(provider: GitProvider)

    var requiredScopes: [String] {
        switch self {
        case .sourceListing(let provider, let organizationScope):
            switch provider {
            case .github:
                if organizationScope {
                    return ["repo", "read:org"]
                }
                return ["repo"]
            case .gitlab:
                return ["read_api"]
            case .gitea:
                return ["read:repository"]
            }
        case .giteaTargetCreate:
            return ["write:repository"]
        case .webhookRegistration(let provider):
            switch provider {
            case .github:
                return ["admin:repo_hook"]
            case .gitlab:
                return ["api"]
            case .gitea:
                return ["write:repository"]
            }
        }
    }

    var disclosureText: String? {
        switch self {
        case .webhookRegistration(.github):
            return "在 Provider 上自动注册 webhook 需要额外的 admin:repo_hook 权限（超出日常镜像同步所需）。请仅在信任本机应用时授予。"
        case .webhookRegistration(.gitlab):
            return "在 GitLab 上自动注册 webhook 需要 api 权限。请仅在信任本机应用时授予。"
        case .webhookRegistration(.gitea):
            return "在 Gitea 上自动注册 webhook 需要 write:repository 权限。请仅在信任本机应用时授予。"
        default:
            return nil
        }
    }
}

nonisolated enum ProviderTokenScope {
    static let cacheLifetime: TimeInterval = 24 * 3_600

    static func validate(grantedScopes: Set<String>, usage: ProviderTokenUsage) -> TokenScopeValidation {
        let missing = usage.requiredScopes.filter { !satisfies(required: $0, granted: grantedScopes) }
        return TokenScopeValidation(grantedScopes: grantedScopes, missingRequiredScopes: missing)
    }

    static func satisfies(required: String, granted: Set<String>) -> Bool {
        if granted.contains(required) { return true }
        switch required {
        case "repo":
            return granted.contains("public_repo")
        case "read_api":
            return granted.contains("api")
        case "read:org":
            return granted.contains("admin:org") || granted.contains("read:org")
        case "write:repository":
            return granted.contains("all")
        case "admin:repo_hook":
            return granted.contains("admin:repo_hook")
                || granted.contains("write:repo_hook")
                || granted.contains("repo")
        default:
            return false
        }
    }

    static func parseGitHubOAuthScopesHeader(_ header: String?) -> Set<String> {
        guard let header, !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return Set(
            header
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func parseGitLabScopes(_ scopes: [String]) -> Set<String> {
        Set(scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    static func parseGiteaTokenScopes(_ scopes: [String]) -> Set<String> {
        Set(scopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    static func resolveScopes(
        usage: ProviderTokenUsage,
        cacheKey: String,
        forceRefresh: Bool = false,
        fetch: () async throws -> Set<String>
    ) async throws -> TokenScopeValidation {
        if !forceRefresh, let cached = ProviderTokenScopeCache.load(key: cacheKey) {
            return validate(grantedScopes: cached, usage: usage)
        }
        let scopes = try await fetch()
        ProviderTokenScopeCache.save(key: cacheKey, scopes: scopes)
        return validate(grantedScopes: scopes, usage: usage)
    }
}
