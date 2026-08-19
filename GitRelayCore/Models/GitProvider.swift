import Foundation

nonisolated enum GitProvider: String, CaseIterable, Identifiable, Codable {
    case github
    case gitlab
    case gitea

    var id: String { rawValue }

    static var listingCases: [GitProvider] { [.github, .gitlab] }

    var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .gitea:  "Gitea (the open-source edition of Gitee)"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .github: URL(string: "https://api.github.com")!
        case .gitlab: URL(string: "https://gitlab.com/api/v4")!
        case .gitea:  URL(string: "https://gitea.com/api/v1")!
        }
    }

    var tokenHelpText: String {
        switch self {
        case .github:
            "Create a Personal Access Token (classic) with the repo and read:org scopes. https://github.com/settings/tokens"
        case .gitlab:
            "Create a Personal Access Token with the read_api scope. https://gitlab.com/-/user_settings/personal_access_tokens"
        case .gitea:
            "Create a token with the write:repository scope (required to create repositories). Visit <your-gitea-host>/user/settings/applications"
        }
    }
}
