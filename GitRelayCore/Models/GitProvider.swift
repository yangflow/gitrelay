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
        case .gitea:  "Gitea (Gitee 开源版)"
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
            "创建 Personal Access Token(classic)，勾选 repo / read:org 权限。https://github.com/settings/tokens"
        case .gitlab:
            "创建 Personal Access Token，勾选 read_api 权限。https://gitlab.com/-/user_settings/personal_access_tokens"
        case .gitea:
            "创建 Token,勾选 write:repository(创建仓库需要)。访问 <your-gitea-host>/user/settings/applications"
        }
    }
}
