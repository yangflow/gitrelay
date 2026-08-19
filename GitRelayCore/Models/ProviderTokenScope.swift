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
