import Foundation

nonisolated enum MirrorRunKind: String, Codable, Equatable, Sendable {
    case sync
    case verification
}

nonisolated enum MirrorRunOutcome: String, Codable, Equatable, Sendable {
    case succeeded
    case partiallySucceeded
    case failed
    case cancelled
}

nonisolated struct MirrorDestinationRunResult: Codable, Identifiable, Equatable, Sendable {
    var destinationID: UUID
    var succeeded: Bool
    var completedAt: Date?
    var failure: MirrorFailureSummary?

    var id: UUID { destinationID }
}

nonisolated struct MirrorDestinationVerificationResult: Codable, Identifiable, Equatable, Sendable {
    var destinationID: UUID
    var completedAt: Date
    var integrity: MirrorIntegrityState
    var failure: MirrorFailureSummary?

    var id: UUID { destinationID }
}

nonisolated struct MirrorRunRecord: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var mirrorID: UUID
    var kind: MirrorRunKind
    var startedAt: Date
    var finishedAt: Date?
    var outcome: MirrorRunOutcome
    var failure: MirrorFailureSummary?
    var logLines: [String]
    var destinationResults: [MirrorDestinationRunResult]
    var verificationResults: [MirrorDestinationVerificationResult]

    init(
        id: UUID = UUID(),
        mirrorID: UUID,
        kind: MirrorRunKind = .sync,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        outcome: MirrorRunOutcome,
        failure: MirrorFailureSummary? = nil,
        logLines: [String] = [],
        destinationResults: [MirrorDestinationRunResult] = [],
        verificationResults: [MirrorDestinationVerificationResult] = []
    ) {
        self.id = id
        self.mirrorID = mirrorID
        self.kind = kind
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.failure = failure
        self.logLines = logLines
        self.destinationResults = destinationResults
        self.verificationResults = verificationResults
    }
}
