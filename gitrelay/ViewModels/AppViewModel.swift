import Foundation
import SwiftUI
import Observation
import AppKit

@MainActor
@Observable
final class AppViewModel {
    var repos: [RepoConfig] = []
    var statuses: [UUID: SyncStatus] = [:]
    var records: [UUID: [SyncRecord]] = [:]
    var inProgressSyncIDs: Set<UUID> = []

    var errorMessage: String?

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var hasAnyFailure: Bool {
        statuses.values.contains { if case .failed = $0 { true } else { false } }
    }

    var healthSummary: SyncHealthSummary {
        SyncHealthSummary.make(repos: repos, statuses: statuses)
    }

    /// Current reason scheduled syncs are paused, if any.
    var scheduledSyncPauseReason: SyncPauseReason? {
        environmentMonitor.pauseReason(using: notificationPreferences.preferences.pausePolicy)
    }

    let notificationPreferences = NotificationPreferencesStore()
    let environmentMonitor = SyncEnvironmentMonitor()
    let failureNotifier = SyncFailureNotifier()

    private let scheduler = SyncScheduler()
    private var activeSyncEngines: [UUID: SyncEngine] = [:]
    private var focusFlushTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    init() {
        do {
            try MirrorStore.ensureBaseDirectoryExists()
            repos = try RepoStore.load()
        } catch {
            errorMessage = "加载仓库配置失败：\(error.localizedDescription)"
        }

        failureNotifier.onRetry = { [weak self] id in
            self?.triggerSync(repoID: id)
        }

        scheduler.onFire = { [weak self] id in
            Task { @MainActor in
                guard let self else { return }
                guard self.scheduledSyncPauseReason == nil else { return }
                self.triggerSync(repoID: id)
            }
        }

        for repo in repos {
            statuses[repo.id] = initialStatus(for: repo)
            records[repo.id]  = []
            scheduler.schedule(repo: repo)
        }

        environmentMonitor.start()
        failureNotifier.requestAuthorizationIfNeeded()
        startFocusFlushLoop()
        observeAppActivation()
    }

    // MARK: - CRUD

    func addRepo(_ repo: RepoConfig) {
        repos.append(repo)
        statuses[repo.id] = initialStatus(for: repo)
        records[repo.id]  = []
        scheduler.schedule(repo: repo)
        saveRepos()
    }

    func addRepos(_ newRepos: [RepoConfig], triggerSync: Bool = false) {
        guard !newRepos.isEmpty else { return }
        for repo in newRepos {
            repos.append(repo)
            statuses[repo.id] = initialStatus(for: repo)
            records[repo.id]  = []
            scheduler.schedule(repo: repo)
        }
        saveRepos()
        if triggerSync {
            for repo in newRepos {
                self.triggerSync(repoID: repo.id)
            }
        }
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
        failureNotifier.clearPending(for: id)
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
                self.failureNotifier.clearPending(for: repoID)
            case .failed(let message, let record):
                self.appendRecord(record, for: repoID)
                self.finishSync(repoID: repoID)
                self.patchLastSynced(repoID: repoID, error: message)
                self.statuses[repoID] = .failed(message)
                self.notifySyncFailure(repoID: repoID, message: message)
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

    func flushDeferredFailureNotifications() {
        failureNotifier.flushPendingIfFocusEnded(
            level: notificationPreferences.preferences.interruptionLevel
        )
    }

    // MARK: - Private

    private func notifySyncFailure(repoID: UUID, message: String) {
        guard let repo = repos.first(where: { $0.id == repoID }) else { return }
        failureNotifier.handleSyncFailure(
            repoID: repoID,
            repoName: repo.name,
            message: message,
            consecutiveFailureCount: repo.consecutiveFailureCount,
            preferences: notificationPreferences.preferences
        )
    }

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
        repos[index].recordSyncResult(error: error)
        saveRepos()
    }

    private func initialStatus(for repo: RepoConfig) -> SyncStatus {
        if let error = repo.lastSyncError {
            return .failed(error)
        }
        return .unknown
    }

    private func saveRepos() {
        do {
            try RepoStore.save(repos)
        } catch {
            errorMessage = "保存仓库配置失败:\(error.localizedDescription)"
        }
    }

    private func startFocusFlushLoop() {
        focusFlushTask?.cancel()
        focusFlushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.flushDeferredFailureNotifications()
            }
        }
    }

    private func observeAppActivation() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushDeferredFailureNotifications()
            }
        }
    }
}
