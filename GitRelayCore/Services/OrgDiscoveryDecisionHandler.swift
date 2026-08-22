import Foundation

/// User choice on the org-discovery quiet sheet (#108).
nonisolated enum OrgDiscoveryDecision: Equatable, Sendable {
  case ignore
  case later
  case joinAndSync
}

/// Pure effect table for org-discovery sheet actions (tested in GitRelayCore).
nonisolated struct OrgDiscoveryDecisionOutcome: Equatable, Sendable {
  let shouldPersistIgnore: Bool
  let ignoredRepoID: String?
  let shouldJoinAndSync: Bool
  let shouldDismissFromQueue: Bool
}

nonisolated enum OrgDiscoveryDecisionHandler {
  static func outcome(
    for decision: OrgDiscoveryDecision,
    repoRemoteID: String
  ) -> OrgDiscoveryDecisionOutcome {
    switch decision {
    case .ignore:
      OrgDiscoveryDecisionOutcome(
        shouldPersistIgnore: true,
        ignoredRepoID: repoRemoteID,
        shouldJoinAndSync: false,
        shouldDismissFromQueue: true
      )
    case .later:
      OrgDiscoveryDecisionOutcome(
        shouldPersistIgnore: false,
        ignoredRepoID: nil,
        shouldJoinAndSync: false,
        shouldDismissFromQueue: true
      )
    case .joinAndSync:
      OrgDiscoveryDecisionOutcome(
        shouldPersistIgnore: false,
        ignoredRepoID: nil,
        shouldJoinAndSync: true,
        shouldDismissFromQueue: true
      )
    }
  }
}
