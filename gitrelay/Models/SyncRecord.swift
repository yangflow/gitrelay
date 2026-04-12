import Foundation

struct SyncRecord: Identifiable {
    let id: UUID
    let repoID: UUID
    let startedAt: Date
    var finishedAt: Date?
    var succeeded: Bool
    var logLines: [String]
    var commitsBefore: Int?
    var commitsAfter: Int?

    init(repoID: UUID) {
        self.id = UUID()
        self.repoID = repoID
        self.startedAt = Date()
        self.succeeded = false
        self.logLines = []
    }
}
