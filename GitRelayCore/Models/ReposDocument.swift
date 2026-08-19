import Foundation

/// On-disk repos.json envelope. Version 1 was a bare `[RepoConfig]` array.
struct ReposDocument: Codable, Equatable {
    static let currentVersion = 2

    var version: Int
    var repos: [RepoConfig]

    init(version: Int = currentVersion, repos: [RepoConfig]) {
        self.version = version
        self.repos = repos
    }
}
