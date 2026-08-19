import Foundation

/// Pending UI confirmation for a destructive mirror push under `.strict` policy.
@MainActor
final class DestructivePushConfirmationRequest: Identifiable {
    let id: UUID
    let repoID: UUID
    let repoName: String
    let targetURL: String?
    let plan: DestructivePushPlan

    private let continuation: CheckedContinuation<Bool, Never>
    private var responded = false

    init(
        id: UUID = UUID(),
        repoID: UUID,
        repoName: String,
        targetURL: String? = nil,
        plan: DestructivePushPlan,
        continuation: CheckedContinuation<Bool, Never>
    ) {
        self.id = id
        self.repoID = repoID
        self.repoName = repoName
        self.targetURL = targetURL
        self.plan = plan
        self.continuation = continuation
    }

    func respond(_ confirmed: Bool) {
        guard !responded else { return }
        responded = true
        continuation.resume(returning: confirmed)
    }
}
