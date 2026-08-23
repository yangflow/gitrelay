import Foundation

/// Global quiet-hours window in the user's local timezone.
/// When enabled, scheduled syncs are skipped inside the window; manual / webhook / App Intent syncs are not.
nonisolated struct QuietHoursSettings: Equatable, Sendable {
    /// Master switch. Off by default.
    var isEnabled: Bool

    /// Minutes from local midnight for the window start (`0..<1440`).
    var startMinutes: Int

    /// Minutes from local midnight for the window end (`0..<1440`).
    /// May be less than `startMinutes` when the window wraps midnight (e.g. 23:00–07:00).
    var endMinutes: Int

    /// Suggested example window (23:00–07:00), still disabled until the user turns it on.
    static let suggested = QuietHoursSettings(
        isEnabled: false,
        startMinutes: 23 * 60,
        endMinutes: 7 * 60
    )

    static let `default` = QuietHoursSettings.suggested

    static let minutesPerDay = 24 * 60

    init(isEnabled: Bool, startMinutes: Int, endMinutes: Int) {
        self.isEnabled = isEnabled
        self.startMinutes = Self.clampedMinutes(startMinutes)
        self.endMinutes = Self.clampedMinutes(endMinutes)
    }

    /// Whether `date` falls inside the quiet-hours window in `calendar`'s time zone.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        if startMinutes == endMinutes {
            // Zero-width window: never active.
            return false
        }
        let minutes = Self.minutesSinceMidnight(of: date, calendar: calendar)
        return Self.isMinutes(minutes, insideStart: startMinutes, end: endMinutes)
    }

    /// Next local time when the active/inactive state flips after `date`.
    func nextTransitionDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        if startMinutes == endMinutes {
            return nil
        }

        let active = contains(date, calendar: calendar)
        let targetMinutes = active ? endMinutes : startMinutes
        return Self.nextDate(matchingMinutes: targetMinutes, after: date, calendar: calendar)
    }

    static func clampedMinutes(_ value: Int) -> Int {
        let normalized = value % minutesPerDay
        return normalized >= 0 ? normalized : normalized + minutesPerDay
    }

    static func minutesSinceMidnight(of date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return clampedMinutes(hour * 60 + minute)
    }

    static func isMinutes(_ minutes: Int, insideStart start: Int, end: Int) -> Bool {
        let m = clampedMinutes(minutes)
        let s = clampedMinutes(start)
        let e = clampedMinutes(end)
        if s == e {
            return false
        }
        if s < e {
            return m >= s && m < e
        }
        // Wraps midnight: active from start through midnight, then until end.
        return m >= s || m < e
    }

    static func nextDate(matchingMinutes minutes: Int, after date: Date, calendar: Calendar) -> Date? {
        let target = clampedMinutes(minutes)
        let startOfDay = calendar.startOfDay(for: date)
        guard let today = calendar.date(byAdding: .minute, value: target, to: startOfDay) else {
            return nil
        }
        if today > date {
            return today
        }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }
}

/// Remembers repos whose scheduled tick was skipped during quiet hours so we
/// can catch up **once** when the window ends (no stacked backlog).
nonisolated struct QuietHoursCatchUpTracker: Equatable, Sendable {
    private(set) var pendingRepoIDs: Set<UUID> = []

    mutating func noteScheduledSkip(repoID: UUID) {
        pendingRepoIDs.insert(repoID)
    }

    mutating func clear(repoID: UUID) {
        pendingRepoIDs.remove(repoID)
    }

    mutating func takePendingCatchUp() -> Set<UUID> {
        let ids = pendingRepoIDs
        pendingRepoIDs.removeAll()
        return ids
    }
}

/// Pure decision helper for scheduled ticks (injectable clock for tests).
enum ScheduledSyncGate {
    /// Whether a **scheduled** tick should start a sync at `date`.
    /// Manual / App Intent / webhook callers should not use this gate.
    static func shouldRunScheduledSync(
        pausePolicy: SyncPausePolicy,
        isLowPowerMode: Bool,
        isExpensiveNetwork: Bool,
        at date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        pausePolicy.pauseReason(
            isLowPowerMode: isLowPowerMode,
            isExpensiveNetwork: isExpensiveNetwork,
            date: date,
            calendar: calendar
        ) == nil
    }
}
