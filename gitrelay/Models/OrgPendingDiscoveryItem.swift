import Foundation

/// One newly discovered org repo waiting for join-or-ignore on the quiet sheet (#108).
struct OrgPendingDiscoveryItem: Identifiable, Equatable, Sendable {
  let subscriptionID: UUID
  let repo: RemoteRepo
  let provider: GitProvider
  let accountLabel: String
  let organizationName: String
  let gitlabHost: String?
  let template: OrgSubscriptionTemplate

  var id: String { "\(subscriptionID.uuidString)-\(repo.id)" }
}
