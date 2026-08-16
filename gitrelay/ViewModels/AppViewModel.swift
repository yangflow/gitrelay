import Foundation
import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class AppViewModel {
    var repos: [RepoConfig] = []
    var statuses: [UUID: SyncStatus] = [:]
    var records: [UUID: [SyncRecord]] = [:]
    var inProgressSyncIDs: Set<UUID> = []

    var errorMessage: String?
    /// FIFO queue: parallel syncs may each need a destructive-push prompt.
    var pendingDestructiveConfirmations: [DestructivePushConfirmationRequest] = []

    var presentedDestructiveConfirmation: DestructivePushConfirmationRequest? {
        pendingDestructiveConfirmations.first
    }

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

    private let scheduler = SyncScheduler()
    private var activeSyncEngines: [UUID: SyncEngine] = [:]

    init() {
        do {
            try MirrorStore.ensureBaseDirectoryExists()
            repos = try RepoStore.load()
        } catch {
            errorMessage = "加载仓库配置失败：\(error.localizedDescription)"
        }

        scheduler.onFire = { [weak self] id in
            Task { self?.triggerSync(repoID: id) }
        }

        for repo in repos {
            statuses[repo.id] = initialStatus(for: repo)
            records[repo.id]  = []
            scheduler.schedule(repo: repo)
        }
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

        engine.confirmDestructivePush = { [weak self] plan in
            guard let self else { return false }
            return await self.requestDestructiveConfirmation(repoID: repoID, repoName: repo.name, plan: plan)
        }

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
        denyPendingDestructiveConfirmation(for: repoID)
        activeSyncEngines[repoID]?.cancel()
    }

    func confirmPendingDestructivePush() {
        guard !pendingDestructiveConfirmations.isEmpty else { return }
        let pending = pendingDestructiveConfirmations.removeFirst()
        pending.respond(true)
    }

    func cancelPendingDestructivePush() {
        guard !pendingDestructiveConfirmations.isEmpty else { return }
        let pending = pendingDestructiveConfirmations.removeFirst()
        pending.respond(false)
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
        denyPendingDestructiveConfirmation(for: repoID)
        inProgressSyncIDs.remove(repoID)
        activeSyncEngines.removeValue(forKey: repoID)
    }

    private func requestDestructiveConfirmation(
        repoID: UUID,
        repoName: String,
        plan: DestructivePushPlan
    ) async -> Bool {
        // Replace any unanswered prompt for this repo (re-entrancy / retry).
        denyPendingDestructiveConfirmation(for: repoID)
        bringAppForwardForConfirmation()

        return await withCheckedContinuation { continuation in
            let request = DestructivePushConfirmationRequest(
                repoID: repoID,
                repoName: repoName,
                plan: plan,
                continuation: continuation
            )
            pendingDestructiveConfirmations.append(request)
        }
    }

    private func denyPendingDestructiveConfirmation(for repoID: UUID?) {
        guard let repoID else { return }
        let matching = pendingDestructiveConfirmations.filter { $0.repoID == repoID }
        pendingDestructiveConfirmations.removeAll { $0.repoID == repoID }
        matching.forEach { $0.respond(false) }
    }

    private func bringAppForwardForConfirmation() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .gitrelayOpenMainWindow, object: nil)
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
        }
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
}
