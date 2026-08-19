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
    var inProgressVerifyIDs: Set<UUID> = []
    var verificationPreferences: VerificationPreferences

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

    var hasAnyDivergence: Bool {
        statuses.values.contains { if case .diverged = $0 { true } else { false } }
            || repos.contains { $0.isDiverged }
    }

    var healthSummary: SyncHealthSummary {
        SyncHealthSummary.make(repos: repos, statuses: statuses)
    }

    var allKnownTags: [String] {
        RepoTagGrouping.allUniqueTags(from: repos)
    }

    /// Current reason scheduled syncs are paused, if any.
    var scheduledSyncPauseReason: SyncPauseReason? {
        environmentMonitor.pauseReason(using: notificationPreferences.preferences.pausePolicy)
    }

    let notificationPreferences = NotificationPreferencesStore()
    let environmentMonitor = SyncEnvironmentMonitor()
    let failureNotifier = SyncFailureNotifier()

    private let scheduler = SyncScheduler()
    private let verificationScheduler = VerificationScheduler()
    private let verificationPreferencesStore: VerificationPreferencesStore
    private var activeSyncEngines: [UUID: SyncEngine] = [:]
    private var activeVerifiers: [UUID: IntegrityVerifier] = [:]
    private var focusFlushTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    init(verificationPreferencesStore: VerificationPreferencesStore? = nil) {
        let store = verificationPreferencesStore ?? VerificationPreferencesStore()
        self.verificationPreferencesStore = store
        self.verificationPreferences = store.preferences

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
        verificationScheduler.onFire = { [weak self] in
            Task { self?.runScheduledVerificationSample() }
        }
        store.onPreferencesChange = { [weak self] (prefs: VerificationPreferences) in
            self?.verificationPreferences = prefs
            self?.verificationScheduler.reschedule(frequency: prefs.frequency)
        }

        for repo in repos {
            statuses[repo.id] = initialStatus(for: repo)
            records[repo.id]  = []
            scheduler.schedule(repo: repo)
        }
        verificationScheduler.schedule(frequency: verificationPreferences.frequency)

        environmentMonitor.start()
        failureNotifier.requestAuthorizationIfNeeded()
        startFocusFlushLoop()
        observeAppActivation()
        AppIntentBridge.register(self)
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
        if updated.isDiverged {
            statuses[updated.id] = .diverged(updated.divergedDetail ?? "内容分歧")
        } else if case .diverged = statuses[updated.id] {
            statuses[updated.id] = updated.lastSyncError.map(SyncStatus.failed) ?? .unknown
        }
        scheduler.reschedule(repo: updated)
        saveRepos()
    }

    func deleteRepo(id: UUID) {
        scheduler.deschedule(repoID: id)
        cancelSync(repoID: id)
        cancelVerify(repoID: id)
        repos.removeAll { $0.id == id }
        statuses.removeValue(forKey: id)
        records.removeValue(forKey: id)
        failureNotifier.clearPending(for: id)
        try? MirrorStore.deleteMirror(for: id)
        let scratch = Constants.baseDirectory
            .appendingPathComponent("verify-scratch")
            .appendingPathComponent(id.uuidString)
        try? FileManager.default.removeItem(at: scratch)
        saveRepos()
    }

    // MARK: - Sync

    func triggerSync(repoID: UUID) {
        guard !inProgressSyncIDs.contains(repoID),
              !inProgressVerifyIDs.contains(repoID),
              let repo = repos.first(where: { $0.id == repoID }) else { return }

        let engine = SyncEngine(repo: repo)
        activeSyncEngines[repoID] = engine
        inProgressSyncIDs.insert(repoID)
        statuses[repoID] = .syncing

        engine.confirmDestructivePush = { [weak self] plan, target in
            guard let self else { return false }
            return await self.requestDestructiveConfirmation(
                repoID: repoID,
                repoName: repo.name,
                targetURL: target.url,
                plan: plan
            )
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

    func repos(matchingTag tag: String?) -> [RepoConfig] {
        RepoTagGrouping.repos(matching: tag, in: repos)
    }

    func triggerSync(matchingTag tag: String?) {
        repos(matchingTag: tag).forEach { triggerSync(repoID: $0.id) }
    }

    func triggerVerify(matchingTag tag: String?) {
        repos(matchingTag: tag).forEach { triggerVerify(repoID: $0.id) }
    }

    func updateFrequency(matchingTag tag: String?, frequency: SyncFrequency) {
        let targetIDs = Set(RepoTagGrouping.repoIDs(matching: tag, in: repos))
        guard !targetIDs.isEmpty else { return }

        for index in repos.indices where targetIDs.contains(repos[index].id) {
            repos[index].frequency = frequency
            scheduler.reschedule(repo: repos[index])
        }
        saveRepos()
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

    // MARK: - Integrity verification

    func updateVerificationPreferences(_ preferences: VerificationPreferences) {
        verificationPreferencesStore.preferences = preferences
    }

    func nextVerificationFireDate() -> Date? {
        verificationScheduler.nextFireDate()
    }

    func triggerVerify(repoID: UUID) {
        guard !inProgressSyncIDs.contains(repoID),
              !inProgressVerifyIDs.contains(repoID),
              let repo = repos.first(where: { $0.id == repoID }) else { return }
        startVerify(repo: repo)
    }

    func triggerVerifySampleNow() {
        runScheduledVerificationSample()
    }

    func cancelVerify(repoID: UUID) {
        activeVerifiers[repoID]?.cancel()
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

    private func runScheduledVerificationSample() {
        let sample = VerificationSampler.sample(
            from: repos,
            count: verificationPreferences.sampleSize
        )
        for repo in sample {
            triggerVerify(repoID: repo.id)
        }
    }

    private func startVerify(repo: RepoConfig) {
        let repoID = repo.id
        let verifier = IntegrityVerifier(repo: repo)
        activeVerifiers[repoID] = verifier
        inProgressVerifyIDs.insert(repoID)

        verifier.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .started, .log:
                break
            case .completed(let decision, let record):
                self.appendRecord(record, for: repoID)
                self.finishVerify(repoID: repoID)
                switch decision {
                case .matched:
                    self.patchVerification(repoID: repoID, divergedDetail: nil)
                    if case .failed = self.statuses[repoID] {
                        // Keep sync failure visible.
                    } else {
                        self.statuses[repoID] = .idle
                    }
                case .diverged(let detail):
                    self.patchVerification(repoID: repoID, divergedDetail: detail.summary)
                    self.statuses[repoID] = .diverged(detail.summary)
                case .inconclusive:
                    if let index = self.repos.firstIndex(where: { $0.id == repoID }) {
                        self.repos[index].lastVerifiedAt = Date()
                        self.saveRepos()
                    }
                }
            case .failed(_, let record):
                self.appendRecord(record, for: repoID)
                self.finishVerify(repoID: repoID)
                if let index = self.repos.firstIndex(where: { $0.id == repoID }) {
                    self.repos[index].lastVerifiedAt = Date()
                    self.saveRepos()
                }
            }
        }

        Task { await verifier.run() }
    }

    private func appendRecord(_ record: SyncRecord, for repoID: UUID) {
        var existing = records[repoID] ?? []
        existing.append(record)
        if existing.count > 200 { existing.removeFirst(existing.count - 200) }
        records[repoID] = existing
        try? SyncLogStore.append(record, for: repoID)
    }

    private func finishSync(repoID: UUID) {
        denyPendingDestructiveConfirmation(for: repoID)
        inProgressSyncIDs.remove(repoID)
        activeSyncEngines.removeValue(forKey: repoID)
    }

    private func finishVerify(repoID: UUID) {
        inProgressVerifyIDs.remove(repoID)
        activeVerifiers.removeValue(forKey: repoID)
    }

    private func requestDestructiveConfirmation(
        repoID: UUID,
        repoName: String,
        targetURL: String?,
        plan: DestructivePushPlan
    ) async -> Bool {
        denyPendingDestructiveConfirmation(for: repoID)
        bringAppForwardForConfirmation()

        return await withCheckedContinuation { continuation in
            let request = DestructivePushConfirmationRequest(
                repoID: repoID,
                repoName: repoName,
                targetURL: targetURL,
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

    private func patchVerification(repoID: UUID, divergedDetail: String?) {
        guard let index = repos.firstIndex(where: { $0.id == repoID }) else { return }
        repos[index].recordVerificationResult(divergedDetail: divergedDetail)
        saveRepos()
    }

    private func initialStatus(for repo: RepoConfig) -> SyncStatus {
        if let error = repo.lastSyncError {
            return .failed(error)
        }
        if let detail = repo.divergedDetail {
            return .diverged(detail)
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
