import Foundation

nonisolated enum MirrorActivityState: Equatable, Sendable {
    case idle
    case queued(position: Int)
    case synchronizing(phase: SyncPhase, progress: Double?)
    case verifying(progress: Double?)
}

nonisolated enum MirrorHealthState: Equatable, Sendable {
    case needsSetup
    case neverRun
    case healthy
    case stale(since: Date)
    case failed(MirrorFailureSummary)
    case diverged(String)
}

nonisolated enum MirrorGlobalPauseReason: String, Codable, Equatable, Sendable {
    case manual
    case quietHours
    case lowPower
    case expensiveNetwork
    case lowPowerAndExpensiveNetwork
}

nonisolated enum MirrorScheduleState: Equatable, Sendable {
    case active(nextRunAt: Date?)
    case mirrorPaused
    case globallyPaused(MirrorGlobalPauseReason)
    case deferred(MirrorGlobalPauseReason)
}
