import Foundation

nonisolated enum MirrorFailureKind: String, Codable, Equatable, Hashable, Sendable {
    case sourceAuthentication
    case destinationAuthentication
    case sourceUnavailable
    case destinationRejected
    case destructiveChangeBlocked
    case network
    case localStorage
    case cancelled
    case unknown
}

nonisolated struct MirrorFailureSummary: Codable, Equatable, Hashable, Sendable {
    var kind: MirrorFailureKind
    var message: String
    var failedAt: Date
    var destinationID: UUID?

    init(
        kind: MirrorFailureKind,
        message: String,
        failedAt: Date = Date(),
        destinationID: UUID? = nil
    ) {
        self.kind = kind
        self.message = CredentialRedactor.redact(message)
        self.failedAt = failedAt
        self.destinationID = destinationID
    }
}

nonisolated enum MirrorIntegrityState: Codable, Equatable, Hashable, Sendable {
    case unknown
    case verified
    case diverged(String)
    case inconclusive(String)
}

nonisolated struct MirrorDestinationHealthSnapshot: Codable, Identifiable, Equatable, Hashable, Sendable {
    var destinationID: UUID
    var lastAttemptAt: Date?
    var lastSuccessfulAt: Date?
    var lastFailure: MirrorFailureSummary?
    var lastVerifiedAt: Date?
    var integrity: MirrorIntegrityState

    var id: UUID { destinationID }

    init(
        destinationID: UUID,
        lastAttemptAt: Date? = nil,
        lastSuccessfulAt: Date? = nil,
        lastFailure: MirrorFailureSummary? = nil,
        lastVerifiedAt: Date? = nil,
        integrity: MirrorIntegrityState = .unknown
    ) {
        self.destinationID = destinationID
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulAt = lastSuccessfulAt
        self.lastFailure = lastFailure
        self.lastVerifiedAt = lastVerifiedAt
        self.integrity = integrity
    }
}

nonisolated struct MirrorHealthSnapshot: Codable, Identifiable, Equatable, Sendable {
    var mirrorID: UUID
    var lastAttemptAt: Date?
    var lastSuccessfulAt: Date?
    var lastFailure: MirrorFailureSummary?
    var consecutiveFailures: Int
    var lastVerifiedAt: Date?
    var integrity: MirrorIntegrityState
    var dailyOutcomes: [String: SyncDayOutcome]
    var destinations: [MirrorDestinationHealthSnapshot]

    var id: UUID { mirrorID }

    init(
        mirrorID: UUID,
        lastAttemptAt: Date? = nil,
        lastSuccessfulAt: Date? = nil,
        lastFailure: MirrorFailureSummary? = nil,
        consecutiveFailures: Int = 0,
        lastVerifiedAt: Date? = nil,
        integrity: MirrorIntegrityState = .unknown,
        dailyOutcomes: [String: SyncDayOutcome] = [:],
        destinations: [MirrorDestinationHealthSnapshot] = []
    ) {
        self.mirrorID = mirrorID
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessfulAt = lastSuccessfulAt
        self.lastFailure = lastFailure
        self.consecutiveFailures = max(0, consecutiveFailures)
        self.lastVerifiedAt = lastVerifiedAt
        self.integrity = integrity
        self.dailyOutcomes = dailyOutcomes
        self.destinations = destinations
    }
}
