import Foundation

/// Filters org discovery results to repos that still need a join-or-ignore decision.
nonisolated enum OrgDiscoveryPendingFilter {
  /// Returns `newRepos` minus subscription ignores and anything already mirrored locally.
  static func actionableRepos(
    subscription: OrgSubscription,
    newRepos: [RemoteRepo],
    localMirrors: [MirrorPlan]
  ) -> [RemoteRepo] {
    let mirrored = OrgRepoDiff.syncedRemotePaths(from: localMirrors)
    let ignored = Set(subscription.ignoredDiscoveredRepoIDs)
    return newRepos.filter { repo in
      !ignored.contains(repo.id)
        && !mirrored.contains(repo.fullName.lowercased())
    }
  }

  /// Returns actionable repos when only the subscription ignore list is applied.
  static func actionableRepos(
    subscription: OrgSubscription,
    newRepos: [RemoteRepo]
  ) -> [RemoteRepo] {
    let ignored = Set(subscription.ignoredDiscoveredRepoIDs)
    return newRepos.filter { !ignored.contains($0.id) }
  }
}
