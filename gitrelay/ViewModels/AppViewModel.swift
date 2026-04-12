import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class AppViewModel {
    var repos: [RepoConfig] = []
    var statuses: [UUID: SyncStatus] = [:]
    var records: [UUID: [SyncRecord]] = [:]
    var inProgressSyncIDs: Set<UUID> = []

    private let scheduler = SyncScheduler()
    private var activeSyncEngines: [UUID: SyncEngine] = [:]

    init() {
        do {
            try MirrorStore.ensureBaseDirectoryExists()
            repos = try RepoStore.load()
        } catch {
            print("[AppViewModel] Load failed: \(error)")
        }

        scheduler.onFire = { [weak self] id in
            Task { self?.triggerSync(repoID: id) }
        }

        for repo in repos {
            statuses[repo.id] = .unknown
            records[repo.id]  = []
            scheduler.schedule(repo: repo)
        }
    }

    // MARK: - CRUD

    func addRepo(_ repo: RepoConfig) {
        repos.append(repo)
        statuses[repo.id] = .unknown
        records[repo.id]  = []
        scheduler.schedule(repo: repo)
        saveRepos()
    }

    func updateRepo(_ updated: RepoConfig) {
        guard let index = repos.firstIndex(where: { $0.id == updated.id }) else { return }
        repos[index] = updated
        scheduler.reschedule(repo: updated)
        saveRepos()
    }

    func deleteRepo(id: UUID) {
        scheduler.deschedule(repoID: id)
        cancelSync(repoID: id)
        repos.removeAll { $0.id == id }
        statuses.removeValue(forKey: id)
        records.removeValue(forKey: id)
        try? MirrorStore.deleteMirror(for: id)
        saveRepos()
    }

    // MARK: - Sync

    func triggerSync(repoID: UUID) {
        guard !inProgressSyncIDs.contains(repoID),
              let repo = repos.first(where: { $0.id == repoID }) else { return }

        let engine = SyncEngine(repo: repo)
        activeSyncEngines[repoID] = engine
        inProgressSyncIDs.insert(repoID)
        statuses[repoID] = .syncing

        engine.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .statusChanged(let status):
                self.statuses[repoID] = status
            case .completed(let record):
                self.appendRecord(record, for: repoID)
                self.finishSync(repoID: repoID)
                self.patchLastSynced(repoID: repoID, error: nil)
                self.statuses[repoID] = .idle
            case .failed(let message, let record):
                self.appendRecord(record, for: repoID)
                self.finishSync(repoID: repoID)
                self.patchLastSynced(repoID: repoID, error: message)
                self.statuses[repoID] = .failed(message)
            case .started, .log:
                break
            }
        }

        Task { await engine.run() }
    }

    func triggerSyncAll() {
        repos.forEach { triggerSync(repoID: $0.id) }
    }

    func cancelSync(repoID: UUID) {
        activeSyncEngines[repoID]?.cancel()
    }

    func nextFireDate(for repoID: UUID) -> Date? {
        scheduler.nextFireDate(for: repoID)
    }

    func latestRecord(for repoID: UUID) -> SyncRecord? {
        records[repoID]?.last
    }

    // MARK: - Private

    private func appendRecord(_ record: SyncRecord, for repoID: UUID) {
        var existing = records[repoID] ?? []
        existing.append(record)
        if existing.count > 200 { existing.removeFirst(existing.count - 200) }
        records[repoID] = existing
    }

    private func finishSync(repoID: UUID) {
        inProgressSyncIDs.remove(repoID)
        activeSyncEngines.removeValue(forKey: repoID)
    }

    private func patchLastSynced(repoID: UUID, error: String?) {
        guard let index = repos.firstIndex(where: { $0.id == repoID }) else { return }
        repos[index].lastSyncedAt  = Date()
        repos[index].lastSyncError = error
        saveRepos()
    }

    private func saveRepos() {
        try? RepoStore.save(repos)
    }
}
