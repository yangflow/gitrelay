import Foundation

/// One pair's schedule, as the detail face states it: whether a frequency timer
/// belongs to this pair at all, whether the pause toggle is worth showing, and
/// the single line that says when the next run is due.
///
/// Pausing here only stops frequency-driven runs. Manual 同步 and webhook syncs
/// go through the operations controller and never consult this.
nonisolated struct RepoScheduleState: Equatable, Sendable {
    let isPaused: Bool
    /// True when the pair syncs on a frequency rather than only by hand.
    let hasFrequency: Bool
    /// True while the pair waits for a token or key, which already blocks scheduling.
    let needsCredentials: Bool
    let nextFireDate: Date?

    static func make(repo: MirrorSnapshot, nextFireDate: Date? = nil) -> RepoScheduleState {
        RepoScheduleState(
            isPaused: repo.scheduledSyncPaused,
            hasFrequency: repo.frequency != .manual,
            needsCredentials: repo.needsCredentials,
            nextFireDate: nextFireDate
        )
    }

    /// The scheduler arms a repeating timer only for a pair that has a
    /// frequency, is not paused, and is not waiting on credentials.
    static func armsTimer(for repo: MirrorSnapshot) -> Bool {
        make(repo: repo).armsTimer
    }

    var armsTimer: Bool {
        hasFrequency && !isPaused && !needsCredentials
    }

    /// A pause toggle is only meaningful for a pair with a frequency. A paused
    /// pair keeps the toggle even after its frequency is set back to 手动, so
    /// the pause can still be lifted.
    var showsPauseToggle: Bool {
        hasFrequency || isPaused
    }

    var nextRun: RepoNextRun {
        if isPaused { return .paused }
        guard hasFrequency else { return .manualOnly }
        guard !needsCredentials, let nextFireDate else { return .unscheduled }
        return .due(nextFireDate)
    }

    var toggleTitle: String {
        isPaused ? String(localized: "Resume") : String(localized: "Pause")
    }

    var toggleSymbolName: String {
        isPaused ? "play" : "pause"
    }

    var toggleHelp: String {
        isPaused
            ? String(localized: "Resume scheduled sync for this pair")
            : String(localized: "Pause scheduled sync for this pair; manual sync still works")
    }
}

/// The next-run line under the pair's status.
nonisolated enum RepoNextRun: Equatable, Sendable {
    case paused
    /// No frequency: this pair only syncs when asked.
    case manualOnly
    /// Has a frequency, but no timer is armed (missing credentials, or the app
    /// has not scheduled it yet).
    case unscheduled
    case due(Date)

    func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .paused:
            return String(localized: "Paused")
        case .manualOnly:
            return String(localized: "Manual sync only")
        case .unscheduled:
            return String(localized: "Not scheduled")
        case .due(let date):
            return String(localized: "Next at \(Self.timeText(for: date, now: now, calendar: calendar))")
        }
    }

    /// A clock time for a run due today, month and day as well for anything later.
    static func timeText(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, inSameDayAs: now)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month().day().hour().minute())
    }
}
