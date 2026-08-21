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

    /// SF Symbol stand-in for the provider. GitRelay ships no third-party
    /// brand marks, so these are neutral glyphs rather than logos.
    var symbolName: String {
        switch self {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .gitlab: "arrow.triangle.branch"
        case .gitea:  "cup.and.saucer"
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
