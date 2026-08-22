import Foundation

/// Tone of the quiet menu-bar status line, kept as a name so tests can assert
/// it without touching SwiftUI colors.
nonisolated enum MenuBarStatusTone: String, Equatable, Sendable {
    case pause
    case info
}

/// The single quiet line under the menu-bar search field (#107).
///
/// Only one line ever shows. A pause outranks catch-up progress because a
/// paused schedule is not catching anything up.
nonisolated enum MenuBarStatusLine: Equatable, Sendable {
    case paused(SyncPauseReason)
    case catchingUp(missedRuns: Int)

    static func make(pauseReason: SyncPauseReason?, missedRuns: Int) -> MenuBarStatusLine? {
        if let pauseReason {
            return .paused(pauseReason)
        }
        guard missedRuns > 0 else { return nil }
        return .catchingUp(missedRuns: missedRuns)
    }

    var message: String {
        switch self {
        case .paused(let reason):
            return String.loc("Schedule paused · \(reason.shortLabel)")
        case .catchingUp(let missedRuns):
            return String.loc("Missed runs: \(missedRuns) · catching up")
        }
    }

    var tone: MenuBarStatusTone {
        switch self {
        case .paused: return .pause
        case .catchingUp: return .info
        }
    }
}
