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
    var targetResults: [TargetSyncResult]

    init(repoID: UUID) {
        self.id = UUID()
        self.repoID = repoID
        self.startedAt = Date()
        self.succeeded = false
        self.logLines = []
        self.targetResults = []
    }
}

extension SyncRecord {
    static func aggregateSucceeded(from results: [TargetSyncResult]) -> Bool {
        !results.isEmpty && results.allSatisfy(\.succeeded)
    }

    static func aggregateErrorMessage(from results: [TargetSyncResult]) -> String? {
        let failures = results.filter { !$0.succeeded }
        guard !failures.isEmpty else { return nil }
        if failures.count == results.count {
            return failures.map { failureSummary($0) }.joined(separator: "; ")
        }
        let succeededCount = results.count - failures.count
        let detail = failures.map { failureSummary($0) }.joined(separator: "; ")
        return "\(failures.count)/\(results.count) 个目标失败（\(succeededCount) 个成功）: \(detail)"
    }

    private static func failureSummary(_ result: TargetSyncResult) -> String {
        let label = result.targetURL
        if let error = result.error, !error.isEmpty {
            return "\(label): \(error)"
        }
        return label
    }
}
