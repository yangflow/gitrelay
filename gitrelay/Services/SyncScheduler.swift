import Foundation

@MainActor
final class SyncScheduler {
    private var timers: [UUID: Timer] = [:]
    var onFire: ((UUID) -> Void)?

    func schedule(repo: RepoConfig) {
        guard let interval = repo.frequency.interval else { return }
        deschedule(repoID: repo.id)
        let id = repo.id
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFire?(id) }
        }
        timers[id] = timer
    }

    func deschedule(repoID: UUID) {
        timers[repoID]?.invalidate()
        timers.removeValue(forKey: repoID)
    }

    func reschedule(repo: RepoConfig) {
        deschedule(repoID: repo.id)
        schedule(repo: repo)
    }

    func nextFireDate(for repoID: UUID) -> Date? {
        timers[repoID]?.fireDate
    }

    func invalidateAll() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
