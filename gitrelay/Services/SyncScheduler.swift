import Foundation

@MainActor
final class SyncScheduler {
    /// An armed timer plus the fire it owes next, tracked separately because a
    /// `Timer` silently loses its ticks while the machine sleeps.
    private struct ArmedTimer {
        let interval: TimeInterval
        var expectedFireDate: Date
        let timer: Timer
    }

    private var armed: [UUID: ArmedTimer] = [:]
    var onFire: ((UUID) -> Void)?

    /// Injected clock for tests. Production uses `Date()`.
    var now: () -> Date = { Date() }

    func schedule(repo: RepoConfig) {
        // Manual-only pairs, a paused pair, and imported repos still missing
        // Token/SSH all stay unscheduled. Manual 同步 goes around this.
        guard RepoScheduleState.armsTimer(for: repo), let interval = repo.frequency.interval else {
            deschedule(repoID: repo.id)
            return
        }
        deschedule(repoID: repo.id)
        let id = repo.id
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.noteFired(repoID: id)
                self.onFire?(id)
            }
        }
        armed[id] = ArmedTimer(
            interval: interval,
            expectedFireDate: now().addingTimeInterval(interval),
            timer: timer
        )
    }

    func deschedule(repoID: UUID) {
        armed[repoID]?.timer.invalidate()
        armed.removeValue(forKey: repoID)
    }

    func reschedule(repo: RepoConfig) {
        deschedule(repoID: repo.id)
        schedule(repo: repo)
    }

    func nextFireDate(for repoID: UUID) -> Date? {
        armed[repoID]?.timer.fireDate
    }

    /// What the schedule owes this repo, for missed-run catch-up after wake.
    func runExpectation(for repoID: UUID) -> ScheduledRunExpectation? {
        guard let entry = armed[repoID] else { return nil }
        return ScheduledRunExpectation(
            repoID: repoID,
            interval: entry.interval,
            expectedFireDate: entry.expectedFireDate
        )
    }

    func invalidateAll() {
        armed.values.forEach { $0.timer.invalidate() }
        armed.removeAll()
    }

    private func noteFired(repoID: UUID) {
        guard var entry = armed[repoID] else { return }
        entry.expectedFireDate = now().addingTimeInterval(entry.interval)
        armed[repoID] = entry
    }
}
