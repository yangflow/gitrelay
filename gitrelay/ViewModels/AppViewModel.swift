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
    var syncPhases: [UUID: SyncPhase] = [:]
    var liveSyncLogLines: [UUID: String] = [:]
    var inProgressSyncIDs: Set<UUID> = []
    var inProgressVerifyIDs: Set<UUID> = []
    var verificationPreferences: VerificationPreferences
    var orgSubscriptionPreferences: OrgSubscriptionPreferences
    var orgSubscriptions: [OrgSubscription] = []
    var mirrorCacheUsageBytes: Int64 = 0
    var isCleaningMirrorCache = false

    /// When opening the main window from the menu bar, select this repo in the sidebar.
    var pendingMainWindowRepoID: UUID?

    /// Opens the browse-remote sheet prefilled from an org subscription discovery notification.
    var pendingBrowsePrefill: BrowseRemotePrefill?

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
    let orgSubscriptionStore: OrgSubscriptionStore
    let securityPreferences: SecurityPreferencesStore
    let cachePreferences: CachePreferencesStore
    let environmentMonitor = SyncEnvironmentMonitor()
    let failureNotifier = SyncFailureNotifier()
    let orgDiscoveryNotifier = OrgDiscoveryNotifier()
    let webhookPreferences: WebhookPreferencesStore

    private let biometricAuthenticator: BiometricAuthenticating
    private let scheduler = SyncScheduler()
    private let verificationScheduler = VerificationScheduler()
    private let orgSubscriptionScheduler = OrgSubscriptionScheduler()
    private let orgSubscriptionPoller: OrgSubscriptionPoller
    private let releaseMirrorService = ReleaseMirrorService()
    private let verificationPreferencesStore: VerificationPreferencesStore
    private let webhookListener = WebhookListener()
    private var activeSyncEngines: [UUID: SyncEngine] = [:]
    private var activeVerifiers: [UUID: IntegrityVerifier] = [:]
    private var focusFlushTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    /// Bound loopback port when the webhook listener is running.
    var webhookListenPort: UInt16? { webhookListener.port }

    var isWebhookListenerRunning: Bool { webhookListener.isRunning }

    /// Override in tests to avoid Keychain. Production loads HMAC secrets from Keychain only.
    var webhookSecretProvider: (UUID) -> String? = { WebhookSecretStore.loadSecret(repoID: $0) }

    init(
        verificationPreferencesStore: VerificationPreferencesStore? = nil,
        orgSubscriptionStore: OrgSubscriptionStore? = nil,
        orgSubscriptionFetcher: OrgRemoteRepoFetcher = .live,
        webhookPreferencesStore: WebhookPreferencesStore? = nil,
        securityPreferencesStore: SecurityPreferencesStore? = nil,
        cachePreferencesStore: CachePreferencesStore? = nil,
        biometricAuthenticator: BiometricAuthenticating? = nil
    ) {
        let store = verificationPreferencesStore ?? VerificationPreferencesStore()
        self.verificationPreferencesStore = store
        self.verificationPreferences = store.preferences
        let orgStore = orgSubscriptionStore ?? OrgSubscriptionStore()
        self.orgSubscriptionStore = orgStore
        self.orgSubscriptionPreferences = orgStore.preferences
        self.orgSubscriptions = orgStore.subscriptions
        self.orgSubscriptionPoller = OrgSubscriptionPoller(store: orgStore, fetcher: orgSubscriptionFetcher)
        let webhookStore = webhookPreferencesStore ?? WebhookPreferencesStore()
        self.webhookPreferences = webhookStore
        self.securityPreferences = securityPreferencesStore ?? SecurityPreferencesStore()
        self.cachePreferences = cachePreferencesStore ?? CachePreferencesStore()
        self.biometricAuthenticator = biometricAuthenticator ?? LocalAuthenticationClient()

        do {
            try MirrorStore.ensureBaseDirectoryExists()
            repos = try RepoStore.load()
        } catch {
            errorMessage = String(localized: "Failed to load repository configuration: \(error.localizedDescription)")
        }

        failureNotifier.onRetry = { [weak self] id in
            self?.triggerSync(repoID: id)
        }

        orgDiscoveryNotifier.onView = { [weak self] subscriptionID in
            self?.openBrowsePrefill(for: subscriptionID)
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
        orgSubscriptionScheduler.onFire = { [weak self] in
            Task { await self?.runScheduledOrgSubscriptionPoll() }
        }
        store.onPreferencesChange = { [weak self] (prefs: VerificationPreferences) in
            self?.verificationPreferences = prefs
            self?.verificationScheduler.reschedule(frequency: prefs.frequency)
        }
        orgStore.onPreferencesChange = { [weak self] (prefs: OrgSubscriptionPreferences) in
            self?.orgSubscriptionPreferences = prefs
            self?.orgSubscriptionScheduler.reschedule(frequency: prefs.pollFrequency)
        }
        orgStore.onSubscriptionsChange = { [weak self] subs in
            self?.orgSubscriptions = subs
        }
        webhookStore.onPreferencesChange = { [weak self] _ in
            self?.refreshWebhookListener()
        }

        webhookListener.onRequest = { [weak self] request in
            await MainActor.run {
                self?.handleWebhookRequest(request)
                    ?? WebhookHTTPResponse.plain(503, "Service Unavailable", message: "unavailable\n")
            }
        }

        for repo in repos {
            statuses[repo.id] = initialStatus(for: repo)
            records[repo.id]  = []
            scheduler.schedule(repo: repo)
        }
        verificationScheduler.schedule(frequency: verificationPreferences.frequency)
        orgSubscriptionScheduler.schedule(frequency: orgSubscriptionPreferences.pollFrequency)

        environmentMonitor.start()
        failureNotifier.requestAuthorizationIfNeeded()
        orgDiscoveryNotifier.requestAuthorizationIfNeeded()
        startFocusFlushLoop()
        observeAppActivation()
        AppIntentBridge.register(self)
        refreshWebhookListener()
        refreshWidgetSnapshot()
        refreshMirrorCacheUsage()
    }

    func authorizeSensitiveAction(_ action: SensitiveAction) async -> Bool {
        let gate = BiometricGate(
            policy: SensitiveActionPolicy(preferences: securityPreferences.preferences),
            authenticator: biometricAuthenticator
        )
        return await gate.authorize(action: action)
    }

    // MARK: - CRUD

    func addRepo(_ repo: RepoConfig) {
        repos.append(repo)
        statuses[repo.id] = initialStatus(for: repo)
        records[repo.id]  = []
        scheduler.schedule(repo: repo)
        saveRepos()
        refreshWebhookListener()
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
        refreshWebhookListener()
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
            statuses[updated.id] = .diverged(updated.divergedDetail ?? String(localized: "Content divergence"))
        } else if case .diverged = statuses[updated.id] {
            statuses[updated.id] = updated.lastSyncError.map(SyncStatus.failed) ?? .unknown
        }
        scheduler.reschedule(repo: updated)
        saveRepos()
        refreshWebhookListener()
    }

    func deleteRepo(id: UUID) {
        scheduler.deschedule(repoID: id)
        cancelSync(repoID: id)
        cancelVerify(repoID: id)
        repos.removeAll { $0.id == id }
        statuses.removeValue(forKey: id)
        records.removeValue(forKey: id)
        failureNotifier.clearPending(for: id)
        WebhookSecretStore.deleteSecret(repoID: id)
        try? MirrorStore.deleteMirror(for: id)
        let scratch = Constants.baseDirectory
            .appendingPathComponent("verify-scratch")
            .appendingPathComponent(id.uuidString)
        try? FileManager.default.removeItem(at: scratch)
        saveRepos()
        refreshWebhookListener()
        refreshMirrorCacheUsage()
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
        refreshWidgetSnapshot()
        syncPhases[repoID] = .fetchingSource
        liveSyncLogLines.removeValue(forKey: repoID)

        engine.confirmDestructivePush = { [weak self] plan, target in
            guard let self else { return false }
            return await self.requestDestructiveConfirmation(
                repoID: repoID,
                repoName: repo.name,
                targetURL: target.url,
                plan: plan
            )
        }

        engine.mirrorReleases = { [releaseMirrorService] repo, target, log in
            try await releaseMirrorService.mirrorReleases(repo: repo, target: target, log: log)
        }

        engine.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .statusChanged(let status):
                self.statuses[repoID] = status
                self.refreshWidgetSnapshot()
            case .phase(let phase):
                self.syncPhases[repoID] = phase
            case .log(let line):
                self.liveSyncLogLines[repoID] = line
            case .completed(let record):
                self.appendRecord(record, for: repoID)
                self.finishSync(repoID: repoID)
                self.patchLastSynced(repoID: repoID, error: nil)
                self.statuses[repoID] = .idle
                self.failureNotifier.clearPending(for: repoID)
                Task { await self.enforceMirrorCacheQuotaIfNeeded(excluding: [repoID]) }
            case .failed(let message, let record):
                self.appendRecord(record, for: repoID)
                self.finishSync(repoID: repoID)
                self.patchLastSynced(repoID: repoID, error: message)
                self.statuses[repoID] = .failed(message)
                self.notifySyncFailure(repoID: repoID, message: message)
            case .started:
                break
            }
        }

        Task { await engine.run() }
    }

    func triggerSyncAll() {
        repos.forEach { triggerSync(repoID: $0.id) }
    }

    // MARK: - Mirror cache

    func refreshMirrorCacheUsage() {
        mirrorCacheUsageBytes = MirrorCacheService.currentUsageBytes(repos: repos)
    }

    func cleanMirrorCacheNow() async {
        guard !isCleaningMirrorCache else { return }
        isCleaningMirrorCache = true
        defer {
            isCleaningMirrorCache = false
            refreshMirrorCacheUsage()
        }

        _ = await MirrorCacheService.performCleanup(
            repos: repos,
            quotaGB: cachePreferences.preferences.cacheQuotaGB,
            excluding: inProgressSyncIDs
        )
    }

    func enforceMirrorCacheQuotaIfNeeded(excluding repoIDs: Set<UUID> = []) async {
        refreshMirrorCacheUsage()
        guard MirrorCacheManager.isOverQuota(
            usageBytes: mirrorCacheUsageBytes,
            quotaGB: cachePreferences.preferences.cacheQuotaGB
        ) else { return }

        _ = await MirrorCacheService.performCleanup(
            repos: repos,
            quotaGB: cachePreferences.preferences.cacheQuotaGB,
            excluding: inProgressSyncIDs.union(repoIDs)
        )
        refreshMirrorCacheUsage()
    }

    func freeMirrorSpace(for repoID: UUID) async {
        guard !inProgressSyncIDs.contains(repoID) else { return }
        _ = await MirrorCacheService.freeMirrorSpace(for: repoID)
        refreshMirrorCacheUsage()
    }

    /// Handles an inbound webhook request and may queue an immediate sync (bypasses frequency / pause).
    func handleWebhookRequest(_ request: WebhookHTTPRequest) -> WebhookHTTPResponse {
        let targets = repos.map {
            WebhookPushMapper.HookTarget(
                repoID: $0.id,
                pathID: $0.webhookPathID,
                enabled: $0.webhookEnabled
            )
        }
        let result = WebhookPushMapper.decide(
            request: request,
            targets: targets,
            secretForRepo: { [webhookSecretProvider] in webhookSecretProvider($0) }
        )
        if let repoID = result.syncRepoID {
            triggerSync(repoID: repoID)
        }
        return result.httpResponse
    }

    func webhookURL(for repo: RepoConfig) -> String {
        WebhookURLTemplate.displayURL(
            preferences: webhookPreferences.preferences,
            port: webhookListenPort,
            pathID: repo.webhookPathID
        )
    }

    func refreshWebhookListener() {
        let enabled = webhookPreferences.preferences.listenerEnabled
        if !enabled {
            webhookListener.stop()
            return
        }
        do {
            if webhookListener.isRunning {
                // Already bound — keep the port stable across repo edits.
                return
            }
            try webhookListener.start()
        } catch {
            errorMessage = String(localized: "Failed to start the webhook listener: \(error.localizedDescription)")
            webhookListener.stop()
        }
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

    // MARK: - Org subscription

    func updateOrgSubscriptionPreferences(_ preferences: OrgSubscriptionPreferences) {
        orgSubscriptionStore.preferences = preferences
    }

    func addOrgSubscription(_ subscription: OrgSubscription) {
        orgSubscriptionStore.add(subscription)
    }

    func updateOrgSubscription(_ subscription: OrgSubscription) {
        orgSubscriptionStore.update(subscription)
    }

    func removeOrgSubscription(id: UUID) {
        orgSubscriptionStore.remove(id: id)
    }

    func saveOrgSubscriptionTargetToken(_ token: String, for subscriptionID: UUID) throws {
        try orgSubscriptionStore.saveTargetToken(token, for: subscriptionID)
    }

    func nextOrgSubscriptionFireDate() -> Date? {
        orgSubscriptionScheduler.nextFireDate()
    }

    func triggerOrgSubscriptionPollNow() async {
        await runScheduledOrgSubscriptionPoll()
    }

    func openBrowsePrefill(for subscriptionID: UUID) {
        guard let subscription = orgSubscriptionStore.subscription(id: subscriptionID) else { return }
        Task {
            guard let result = await orgSubscriptionPoller.checkSubscription(subscription, localRepos: repos) else {
                return
            }
            guard !result.newRepos.isEmpty else { return }
            pendingBrowsePrefill = makeBrowsePrefill(from: result)
            bringAppForwardForConfirmation()
        }
    }

    func consumePendingBrowsePrefill() -> BrowseRemotePrefill? {
        defer { pendingBrowsePrefill = nil }
        return pendingBrowsePrefill
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
        orgDiscoveryNotifier.flushPendingIfFocusEnded(
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

    private func runScheduledOrgSubscriptionPoll() async {
        guard scheduledSyncPauseReason == nil else { return }
        let results = await orgSubscriptionPoller.checkAllSubscriptions(localRepos: repos)
        for result in results where !result.newRepos.isEmpty {
            if result.subscription.autoAddEnabled {
                let configs = await OrgSubscriptionAutoAdder.addNewRepos(
                    from: result,
                    store: orgSubscriptionStore
                )
                if !configs.isEmpty {
                    addRepos(configs, triggerSync: true)
                    continue
                }
            }
            orgDiscoveryNotifier.handleDiscovery(
                result,
                notificationsEnabled: orgSubscriptionPreferences.notificationsEnabled,
                interruptionLevel: notificationPreferences.preferences.interruptionLevel
            )
        }
    }

    private func makeBrowsePrefill(from result: OrgSubscriptionCheckResult) -> BrowseRemotePrefill {
        let gitlabHost = result.subscription.provider == .gitlab
            ? ProviderAccountStore.host(for: .gitlab, label: result.subscription.accountLabel)
            : nil
        return BrowseRemotePrefill(
            subscriptionID: result.subscription.id,
            provider: result.subscription.provider,
            accountLabel: result.subscription.accountLabel,
            organizationName: result.subscription.organizationName,
            gitlabHost: gitlabHost,
            repos: result.allRemoteRepos,
            preselectedRepoIDs: Set(result.newRepos.map(\.id)),
            template: result.subscription.template
        )
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
        syncPhases.removeValue(forKey: repoID)
        liveSyncLogLines.removeValue(forKey: repoID)
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
            refreshWidgetSnapshot()
        } catch {
            errorMessage = String(localized: "Failed to save repository configuration: \(error.localizedDescription)")
        }
    }

    private func refreshWidgetSnapshot() {
        WidgetSnapshotPublisher.publish(
            repos: repos,
            statuses: statuses,
            inProgressSyncIDs: inProgressSyncIDs
        )
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
