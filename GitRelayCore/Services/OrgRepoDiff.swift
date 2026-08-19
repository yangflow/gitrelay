import Foundation

/// Compares a remote org/group repo listing against locally configured mirrors.
nonisolated enum OrgRepoDiff {
    /// Returns remote repos whose `fullName` is not already mirrored in `localRepos`.
    static func newRepos(
        remoteRepos: [RemoteRepo],
        localRepos: [RepoConfig]
    ) -> [RemoteRepo] {
        let existingPaths = syncedRemotePaths(from: localRepos)
        return remoteRepos.filter { repo in
            !existingPaths.contains(repo.fullName.lowercased())
        }
    }

    static func syncedRemotePaths(from localRepos: [RepoConfig]) -> Set<String> {
        Set(
            localRepos.compactMap { repo in
                GitRemoteRepoPath.parse(from: repo.srcURL)?
                    .pathWithNamespace
                    .lowercased()
            }
        )
    }
}
