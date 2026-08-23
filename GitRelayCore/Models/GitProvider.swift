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
        case .gitea:  String(localized: "Gitea (the open-source edition of Gitee)")
        }
    }

    /// The brand name on its own, without the Gitee gloss ``displayName`` carries.
    /// Used where the name sits inline, such as the 账号 line on repo detail.
    var shortName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .gitea:  "Gitea"
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
            String(localized: "Create a Personal Access Token (classic) with the repo and read:org scopes. https://github.com/settings/tokens")
        case .gitlab:
            String(localized: "Create a Personal Access Token with the read_api scope. https://gitlab.com/-/user_settings/personal_access_tokens")
        case .gitea:
            String(localized: "Create a token with the write:repository scope (required to create repositories). Visit <your-gitea-host>/user/settings/applications")
        }
    }
}
