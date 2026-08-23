import Foundation

/// Compares a remote org/group repo listing against locally configured mirrors.
nonisolated enum OrgRepoDiff {
    /// Returns remote repos whose `fullName` is not already mirrored in `localRepos`.
    static func newRepos(
        remoteRepos: [RemoteRepo],
        localMirrors: [MirrorPlan]
    ) -> [RemoteRepo] {
        let existingPaths = syncedRemotePaths(from: localMirrors)
        return remoteRepos.filter { repo in
            !existingPaths.contains(repo.fullName.lowercased())
        }
    }

    static func syncedRemotePaths(from localMirrors: [MirrorPlan]) -> Set<String> {
        Set(
            localMirrors.compactMap { mirror in
                GitRemoteRepoPath.parse(from: mirror.source.url)?
                    .pathWithNamespace
                    .lowercased()
            }
        )
    }
}
