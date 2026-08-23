import Foundation

nonisolated struct TargetSyncResult: Identifiable, Equatable, Sendable {
    let targetID: UUID
    let targetURL: String
    var succeeded: Bool
    var error: String?
    var failureKind: MirrorFailureKind?
    var logLines: [String]
    var commitsBefore: Int?

    var id: UUID { targetID }

    init(
        targetID: UUID,
        targetURL: String,
        succeeded: Bool = false,
        error: String? = nil,
        failureKind: MirrorFailureKind? = nil,
        logLines: [String] = [],
        commitsBefore: Int? = nil
    ) {
        self.targetID = targetID
        self.targetURL = targetURL
        self.succeeded = succeeded
        self.error = error
        self.failureKind = failureKind
        self.logLines = logLines
        self.commitsBefore = commitsBefore
    }
}
