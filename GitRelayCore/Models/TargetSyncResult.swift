import Foundation

struct TargetSyncResult: Identifiable, Equatable {
    let targetID: UUID
    let targetURL: String
    var succeeded: Bool
    var error: String?
    var logLines: [String]
    var commitsBefore: Int?

    var id: UUID { targetID }

    init(
        targetID: UUID,
        targetURL: String,
        succeeded: Bool = false,
        error: String? = nil,
        logLines: [String] = [],
        commitsBefore: Int? = nil
    ) {
        self.targetID = targetID
        self.targetURL = targetURL
        self.succeeded = succeeded
        self.error = error
        self.logLines = logLines
        self.commitsBefore = commitsBefore
    }
}
