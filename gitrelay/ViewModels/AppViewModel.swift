import Foundation
import SwiftUI
import AppKit
import Observation
import UserNotifications

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
    var mirrorCacheRepoUsages: [MirrorCacheRepoUsage] = []
    var isCleaningMirrorCache = false

    /// When opening the main window from the menu bar, select this repo in the sidebar.
    var pendingMainWindowRepoID: UUID?

    /// Sidebar row the main window should show when it comes forward. The
    /// menu-bar footer uses it for Settings, which lives in the window now.
    var pendingMainWindowSidebarItem: MainSidebarItem?

    /// After selecting a repo, open the edit sheet focused on authentication fields.
    var pendingEditFocusAuthRepoID: UUID?

    /// After selecting a repo, scroll the detail pane to the Sync Log section.
    var pendingScrollToSyncLogRepoID: UUID?

    /// Opens the browse-remote pane prefilled from an org subscription discovery notification.
    var pendingBrowsePrefill: BrowseRemotePrefill?

    /// Opens the add-repository sheet from the main-window ⌘N / File menu command.
    var pendingOpenAddRepository = false

    /// Focuses the sidebar search field from the main-window ⌘F / Edit menu command.
    var pendingFocusSidebarSearch = false

    /// Sidebar selection mirrored from the main window for ⌘R sync.
    var mainWindowSelectedRepoID: UUID?

    var errorMessage: String?
    /// FIFO queue: parallel syncs may each need a destructive-push prompt.
    var pendingDestructiveConfirmations: [DestructivePushConfirmationRequest] = []

    /// Sidebar search query; display-only, never written to `repos.json`.
    var sidebarSearchText: String = ""
    /// Sidebar status quick filter; display-only, never written to `repos.json`.
    var sidebarStatusFilter: SidebarRepoFilter.StatusFilter = .all

    /// Repos visible in the sidebar after search + status filter (AND).
    var displayedSidebarRepos: [RepoConfig] {
        SidebarRepoFilter.filteredRepos(
            repos,
            searchText: sidebarSearchText,
            statusFilter: sidebarStatusFilter,
            statuses: statuses
        )
    }

    /// Run state, counts, and pause affordance for the sidebar footer.
    var sidebarFooterSummary: SidebarFooterSummary {
        SidebarFooterSummary.make(
            repos: repos,
            statuses: statuses,
            pauseReason: scheduledSyncPauseReason
        )
    }

    /// Repos holding or waiting for a sync slot, in queue order.
    var syncQueueEntries: [SyncQueueEntry] {
        SyncQueueList.entries(repos: repos, statuses: statuses, syncPhases: syncPhases)
    }

    var isScheduledSyncManuallyPaused: Bool {
        notificationPreferences.preferences.scheduledSyncManuallyPaused
    }

    /// Explicitly pauses or resumes frequency-driven syncs. Manual sync and
    /// instant webhook sync are unaffected; resuming runs quiet-hours catch-up.
    func setScheduledSyncManuallyPaused(_ paused: Bool) {
        var prefs = notificationPreferences.preferences
        guard prefs.scheduledSyncManuallyPaused != paused else { return }
        prefs.scheduledSyncManuallyPaused = paused
        notificationPreferences.preferences = prefs
    }

    func toggleScheduledSyncPause() {
        setScheduledSyncManuallyPaused(!isScheduledSyncManuallyPaused)
    }

    /// Whether this one pair's frequency-driven syncs are paused, independent of
    /// the app-wide pause in the sidebar footer.
    func isScheduledSyncPaused(repoID: UUID) -> Bool {
        repos.first(where: { $0.id == repoID })?.scheduledSyncPaused ?? false
    }

    /// Pauses or resumes the frequency timer of one pair. Manual 同步 and
    /// webhook syncs keep working while it is paused.
    func setScheduledSyncPaused(_ paused: Bool, repoID: UUID) {
        guard let index = repos.firstIndex(where: { $0.id == repoID }),
              repos[index].scheduledSyncPaused != paused else { return }
        repos[index].scheduledSyncPaused = paused
        scheduler.reschedule(repo: repos[index])
        saveRepos()
    }

    func toggleScheduledSyncPause(repoID: UUID) {
        setScheduledSyncPaused(!isScheduledSyncPaused(repoID: repoID), repoID: repoID)
    }

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

    /// The single quiet line under the menu-bar search field: why the schedule
    /// is paused, or how far behind the wake-up catch-up still is (#107).
    var menuBarStatusLine: MenuBarStatusLine? {
        MenuBarStatusLine.make(
            pauseReason: scheduledSyncPauseReason,
            missedRuns: missedRunCatchUp.isCatchingUp ? missedRunCatchUp.missedRunCount : 0
        )
    }

    /// Current reason scheduled syncs are paused, if any.
    var scheduledSyncPauseReason: SyncPauseReason? {
        // Touch QuietHoursMonitor.isActive so Observation refreshes the menu bar
        // when the local-time window opens or closes.
        _ = quietHoursMonitor.isActive
        return notificationPreferences.preferences.pausePolicy.pauseReason(
            isLowPowerMode: environmentMonitor.isLowPowerModeEnabled,
            isExpensiveNetwork: environmentMonitor.isExpensiveNetwork,
            date: quietHoursMonitor.now(),
            calendar: quietHoursMonitor.calendar
        )
    }

    let notificationPreferences: NotificationPreferencesStore
    let orgSubscriptionStore: OrgSubscriptionStore
    let securityPreferences: SecurityPreferencesStore
    let cachePreferences: CachePreferencesStore
    let appBehaviorPreferences: AppBehaviorPreferencesStore
    let windowLayout: WindowLayoutStore
    let environmentMonitor = SyncEnvironmentMonitor()
    let quietHoursMonitor = QuietHoursMonitor()
    let failureNotifier = SyncFailureNotifier()
    let orgDiscoveryNotifier = OrgDiscoveryNotifier()
    let webhookPreferences: WebhookPreferencesStore

    private let biometricAuthenticator: BiometricAuthenticating
    private let scheduler = SyncScheduler()
    private let syncConcurrencyGate = SyncConcurrencyGate()
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
    private var wakeObserver: NSObjectProtocol?
    private var quietHoursCatchUp = QuietHoursCatchUpTracker()
    private var missedRunCatchUp = MissedRunCatchUpProgress()
    private var lastScheduledSkipLogAt: Date?
    private var wasScheduledSyncPaused = false

    /// Test seam: admitted syncs stay in-progress without launching SyncEngine / git.
    var suspendSyncEngineForTesting = false

    /// Bound loopback port when the webhook listener is running.
    var webhookListenPort: UInt16? { webhookListener.port }

    var isWebhookListenerRunning: Bool { webhookListener.isRunning }

    /// Override in tests to avoid Keychain. Production loads HMAC secrets from Keychain only.
    var webhookSecretProvider: (UUID) -> String? = { WebhookSecretStore.loadSecret(repoID: $0) }

    init(
        verificationPreferencesStore: VerificationPreferencesStore? = nil,
        orgSubscriptionStore: OrgSubscriptionStore? = nil,
        orgSubscriptionFetcher: OrgRemoteRepoFetcher? = nil,
        webhookPreferencesStore: WebhookPreferencesStore? = nil,
        securityPreferencesStore: SecurityPreferencesStore? = nil,
        cachePreferencesStore: CachePreferencesStore? = nil,
        notificationPreferencesStore: NotificationPreferencesStore? = nil,
        appBehaviorPreferencesStore: AppBehaviorPreferencesStore? = nil,
        windowLayoutStore: WindowLayoutStore? = nil,
        biometricAuthenticator: BiometricAuthenticating? = nil
    ) {
        let store = verificationPreferencesStore ?? VerificationPreferencesStore()
        self.verificationPreferencesStore = store
        self.verificationPreferences = store.preferences
        let orgStore = orgSubscriptionStore ?? OrgSubscriptionStore()
        self.orgSubscriptionStore = orgStore
        self.orgSubscriptionPreferences = orgStore.preferences
        self.orgSubscriptions = orgStore.subscriptions
        self.orgSubscriptionPoller = OrgSubscriptionPoller(
            store: orgStore,
            fetcher: orgSubscriptionFetcher ?? .live
        )
        let webhookStore = webhookPreferencesStore ?? WebhookPreferencesStore()
        self.webhookPreferences = webhookStore
        self.securityPreferences = securityPreferencesStore ?? SecurityPreferencesStore()
        self.cachePreferences = cachePreferencesStore ?? CachePreferencesStore()
        self.notificationPreferences = notificationPreferencesStore ?? NotificationPreferencesStore()
        self.appBehaviorPreferences = appBehaviorPreferencesStore ?? AppBehaviorPreferencesStore()
        self.windowLayout = windowLayoutStore ?? WindowLayoutStore()
        self.biometricAuthenticator = biometricAuthenticator ?? LocalAuthenticationClient()
        syncConcurrencyGate.updateMaxConcurrent(
            notificationPreferences.preferences.maxConcurrentSyncs
        )

        do {
            try MirrorStore.ensureBaseDirectoryExists()
            repos = try RepoStore.load()
        } catch {
            errorMessage = String(localized: "Failed to load repository configuration: \(error.localizedDescription)")
        }

        self.windowLayout.reconcileSelection(withExistingIDs: Set(repos.map(\.id)))

        failureNotifier.onSyncAgain = { [weak self] id in
            self?.triggerSync(repoID: id)
        }
        failureNotifier.onOpen = { [weak self] id in
            self?.requestFocusRepositoryFromFailureNotification(repoID: id)
        }

        let openDiscovery: (UUID) -> Void = { [weak self] subscriptionID in
            self?.openBrowsePrefill(for: subscriptionID)
        }
        orgDiscoveryNotifier.onView = openDiscovery
        failureNotifier.onOrgDiscoveryView = openDiscovery
        // OrgDiscoveryNotifier registers categories after us; keep this notifier as the
        // center delegate so Sync again / Open (and forwarded discovery) responses arrive.
        UNUserNotificationCenter.current().delegate = failureNotifier

        scheduler.onFire = { [weak self] id in
            Task { @MainActor [weak self] in
                self?.handleScheduledSyncFire(repoID: id)
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
        notificationPreferences.onPreferencesChange = { [weak self] prefs in
            self?.quietHoursMonitor.update(settings: prefs.quietHours)
            self?.handleScheduledPauseTransition()
            self?.applySyncConcurrencyCap(prefs.maxConcurrentSyncs)
        }

        webhookListener.onRequest = { [weak self] request in
            await MainActor.run { [weak self] in
                self?.handleWebhookRequest(request)
                    ?? WebhookHTTPResponse.plain(503, "Service Unavailable", message: "unavailable\n")
            }
        }

        var needsCredentialsChanged = false
        for index in repos.indices {
            let refreshed = RepoCredentialGate.refreshedNeedsCredentials(for: repos[index])
            if repos[index].needsCredentials != refreshed {
                repos[index].needsCredentials = refreshed
                needsCredentialsChanged = true
            }
            statuses[repos[index].id] = initialStatus(for: repos[index])
            records[repos[index].id] = []
            scheduler.schedule(repo: repos[index])
        }
        if needsCredentialsChanged {
            saveRepos()
        }
        verificationScheduler.schedule(frequency: verificationPreferences.frequency)
        orgSubscriptionScheduler.schedule(frequency: orgSubscriptionPreferences.pollFrequency)

        environmentMonitor.onEnvironmentChange = { [weak self] in
            self?.handleScheduledPauseTransition()
        }
        environmentMonitor.start()
        quietHoursMonitor.onTransition = { [weak self] in
            self?.handleScheduledPauseTransition()
        }
        quietHoursMonitor.start(settings: notificationPreferences.preferences.quietHours)
        wasScheduledSyncPaused = scheduledSyncPauseReason != nil
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
        var stored = repo
        stored.needsCredentials = RepoCredentialGate.refreshedNeedsCredentials(for: stored)
        repos.append(stored)
        statuses[stored.id] = initialStatus(for: stored)
        records[stored.id]  = []
        scheduler.schedule(repo: stored)
        saveRepos()
        refreshWebhookListener()
    }

    func addRepos(_ newRepos: [RepoConfig], triggerSync: Bool = false) {
        guard !newRepos.isEmpty else { return }
        for var repo in newRepos {
            repo.needsCredentials = RepoCredentialGate.refreshedNeedsCredentials(for: repo)
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
        var stored = updated
        stored.needsCredentials = RepoCredentialGate.refreshedNeedsCredentials(for: stored)
        repos[index] = stored
        if stored.isDiverged {
            statuses[stored.id] = .diverged(stored.divergedDetail ?? String(localized: "Content divergence"))
        } else if case .diverged = statuses[stored.id] {
            statuses[stored.id] = stored.lastSyncError.map(SyncStatus.failed) ?? .unknown
        } else if stored.needsCredentials {
            statuses[stored.id] = .failed(RepoCredentialGate.missingCredentialsMessage)
        } else if case .failed(let message) = statuses[stored.id],
                  message == RepoCredentialGate.missingCredentialsMessage {
            statuses[stored.id] = stored.lastSyncError.map(SyncStatus.failed) ?? .unknown
        }
        scheduler.reschedule(repo: stored)
        saveRepos()
        refreshWebhookListener()
    }

    func deleteRepo(id: UUID) {
        scheduler.deschedule(repoID: id)
        cancelSync(repoID: id)
        missedRunCatchUp.noteFinished(repoID: id)
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
        windowLayout.reconcileSelection(withExistingIDs: Set(repos.map(\.id)))
        saveRepos()
        refreshWebhookListener()
        refreshMirrorCacheUsage()
    }

    // MARK: - Sync

    func triggerSync(repoID: UUID) {
        guard !inProgressSyncIDs.contains(repoID),
              !syncConcurrencyGate.isQueued(repoID),
              !inProgressVerifyIDs.contains(repoID),
              let repo = repos.first(where: { $0.id == repoID }) else { return }

        if repo.needsCredentials || RepoCredentialGate.needsCredentials(for: repo) {
            let message = RepoCredentialGate.missingCredentialsMessage
            if let index = repos.firstIndex(where: { $0.id == repoID }) {
                repos[index].needsCredentials = true
                saveRepos()
            }
            statuses[repoID] = .failed(message)
            errorMessage = message
            scheduler.deschedule(repoID: repoID)
            refreshWidgetSnapshot()
            return
        }

        switch syncConcurrencyGate.request(repoID) {
        case .alreadyTracked:
            return
        case .enqueued:
            statuses[repoID] = .queued
            refreshWidgetSnapshot()
        case .beginImmediately:
            startAdmittedSync(repo: repo)
        }
    }

    func triggerSyncAll() {
        repos.forEach { triggerSync(repoID: $0.id) }
    }

    /// Starts git for a repo that already holds an active concurrency slot.
    private func startAdmittedSync(repo: RepoConfig) {
        let repoID = repo.id
        inProgressSyncIDs.insert(repoID)
        statuses[repoID] = .syncing
        refreshWidgetSnapshot()
        syncPhases[repoID] = SyncPhase(.fetchingSource)
        liveSyncLogLines.removeValue(forKey: repoID)

        if suspendSyncEngineForTesting {
            return
        }

        let engine = SyncEngine(
            repo: repo,
            retryPolicy: notificationPreferences.preferences.gitRetryPolicy
        )
        activeSyncEngines[repoID] = engine

        engine.confirmDestructivePush = { [weak self] plan, target in
            guard let self else { return .cancel }
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
                Task { [self] in
                    await self.enforceMirrorCacheQuotaIfNeeded(excluding: [repoID])
                }
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

    private func applySyncConcurrencyCap(_ value: Int) {
        let admitted = syncConcurrencyGate.updateMaxConcurrent(value)
        for id in admitted {
            promoteQueuedSync(repoID: id)
        }
    }

    private func promoteQueuedSync(repoID: UUID) {
        guard let repo = repos.first(where: { $0.id == repoID }) else {
            // Slot was reserved; release and try the following entry.
            if let next = syncConcurrencyGate.finishActive(repoID) {
                promoteQueuedSync(repoID: next)
            }
            return
        }
        startAdmittedSync(repo: repo)
    }

    // MARK: - Mirror cache

    func refreshMirrorCacheUsage() {
        mirrorCacheUsageBytes = MirrorCacheService.currentUsageBytes(repos: repos)
        mirrorCacheRepoUsages = MirrorCacheService.repoUsages(repos: repos)
    }

    /// Evicts every local mirror (Settings → Cache → Clean All). In-progress syncs are skipped.
    func cleanMirrorCacheNow() async {
        guard !isCleaningMirrorCache else { return }
        isCleaningMirrorCache = true
        defer {
            isCleaningMirrorCache = false
            refreshMirrorCacheUsage()
        }

        _ = await MirrorCacheService.evictAllMirrors(
            repos: repos,
            excluding: inProgressSyncIDs
        )
    }

    /// Evicts one pair's local bare clone. Rebuilds on the next sync.
    func cleanMirrorCache(for repoID: UUID) async {
        guard !isCleaningMirrorCache else { return }
        guard !inProgressSyncIDs.contains(repoID) else { return }
        isCleaningMirrorCache = true
        defer {
            isCleaningMirrorCache = false
            refreshMirrorCacheUsage()
        }
        _ = await MirrorCacheService.freeMirrorSpace(for: repoID)
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
        await cleanMirrorCache(for: repoID)
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

    // MARK: - Config export / import

    func makeConfigExportDocument(exportedAt: Date = Date()) -> ConfigExportDocument {
        ConfigExportCodec.makeDocument(
            repos: repos,
            providerAccounts: ProviderAccountStore.exportedAccounts(),
            orgSubscriptions: orgSubscriptions,
            orgSubscriptionPreferences: orgSubscriptionPreferences,
            exportedAt: exportedAt
        )
    }

    func exportConfigurationData(exportedAt: Date = Date()) throws -> Data {
        try ConfigExportCodec.encode(makeConfigExportDocument(exportedAt: exportedAt))
    }

    /// Decodes and applies an import plan. Throws before mutating when the file is invalid.
    @discardableResult
    func importConfiguration(
        from data: Data,
        mode: ConfigImportMode,
        probe: CredentialProbe? = nil
    ) throws -> ConfigImportPlan {
        let document = try ConfigExportCodec.decode(data)
        let plan = ConfigExportCodec.planImport(
            document: document,
            mode: mode,
            existingRepos: repos,
            probe: probe ?? .live
        )

        // Persist repos first (atomic file replace). Only then update account / org stores.
        let previousRepos = repos
        let previousStatuses = statuses
        let previousRecords = records

        do {
            applyImportedRepos(plan.repos)
            try RepoStore.save(repos)
        } catch {
            repos = previousRepos
            statuses = previousStatuses
            records = previousRecords
            scheduler.invalidateAll()
            for repo in repos {
                scheduler.schedule(repo: repo)
            }
            throw error
        }

        switch mode {
        case .replace:
            ProviderAccountStore.replaceExportedAccounts(plan.providerAccounts)
            orgSubscriptionStore.replaceAll(
                subscriptions: plan.orgSubscriptions,
                preferences: plan.orgSubscriptionPreferences
            )
        case .merge:
            ProviderAccountStore.mergeExportedAccounts(plan.providerAccounts)
            let mergedSubs = ConfigExportCodec.mergeSubscriptions(
                existing: orgSubscriptions,
                imported: plan.orgSubscriptions
            ).merged
            orgSubscriptionStore.replaceSubscriptions(mergedSubs)
            if let prefs = plan.orgSubscriptionPreferences {
                // Keep existing prefs on merge unless the file provides them — still apply when present.
                orgSubscriptionStore.preferences = prefs
            }
        }

        orgSubscriptions = orgSubscriptionStore.subscriptions
        orgSubscriptionPreferences = orgSubscriptionStore.preferences
        refreshWebhookListener()
        refreshWidgetSnapshot()
        return plan
    }

    private func applyImportedRepos(_ imported: [RepoConfig]) {
        scheduler.invalidateAll()
        for id in statuses.keys {
            cancelSync(repoID: id)
            cancelVerify(repoID: id)
            failureNotifier.clearPending(for: id)
        }
        syncConcurrencyGate.reset()
        repos = imported
        statuses = [:]
        records = [:]
        for repo in repos {
            statuses[repo.id] = initialStatus(for: repo)
            records[repo.id] = []
            scheduler.schedule(repo: repo)
        }
    }

    func cancelSync(repoID: UUID) {
        if syncConcurrencyGate.cancelQueued(repoID) {
            missedRunCatchUp.noteFinished(repoID: repoID)
            if let repo = repos.first(where: { $0.id == repoID }) {
                statuses[repoID] = initialStatus(for: repo)
            } else {
                statuses.removeValue(forKey: repoID)
            }
            refreshWidgetSnapshot()
            return
        }

        denyPendingDestructiveConfirmation(for: repoID)

        if suspendSyncEngineForTesting, inProgressSyncIDs.contains(repoID) {
            finishSync(repoID: repoID)
            if let repo = repos.first(where: { $0.id == repoID }) {
                statuses[repoID] = initialStatus(for: repo)
            }
            refreshWidgetSnapshot()
            return
        }

        activeSyncEngines[repoID]?.cancel()
    }

    func resolvePendingDestructivePush(_ decision: DestructivePushDecision) {
        guard !pendingDestructiveConfirmations.isEmpty else { return }
        let pending = pendingDestructiveConfirmations.removeFirst()
        pending.respond(decision)
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

    /// Opens the add-repository two-step sheet (⌘N). Brings the main window forward.
    func requestOpenAddRepository() {
        pendingOpenAddRepository = true
        bringMainWindowForwardForCommands()
    }

    func consumePendingOpenAddRepository() -> Bool {
        guard pendingOpenAddRepository else { return false }
        pendingOpenAddRepository = false
        return true
    }

    /// Focuses the sidebar search field (⌘F). Brings the main window forward.
    func requestFocusSidebarSearch() {
        pendingFocusSidebarSearch = true
        bringMainWindowForwardForCommands()
    }

    func consumePendingFocusSidebarSearch() -> Bool {
        guard pendingFocusSidebarSearch else { return false }
        pendingFocusSidebarSearch = false
        return true
    }

    /// Syncs the main-window selection (⌘R). No-op when nothing is selected or
    /// ``triggerSync(repoID:)`` would already refuse (e.g. already syncing).
    func syncMainWindowSelectedRepository() {
        guard let id = mainWindowSelectedRepoID else { return }
        triggerSync(repoID: id)
    }

    /// Opens the edit sheet for a repo with the authentication fields focused.
    /// Does not mutate repository configuration.
    func requestReenterCredentials(repoID: UUID) {
        guard repos.contains(where: { $0.id == repoID }) else { return }
        pendingEditFocusAuthRepoID = repoID
        pendingMainWindowRepoID = repoID
    }

    /// Selects the repo and scrolls the detail pane to Sync Log.
    /// Does not mutate repository configuration.
    func requestOpenSyncLog(repoID: UUID) {
        guard repos.contains(where: { $0.id == repoID }) else { return }
        pendingScrollToSyncLogRepoID = repoID
        pendingMainWindowRepoID = repoID
    }

    /// Focuses the main window on a repository from a sync-failure notification Open action.
    /// Scrolls to Sync Log when the detail pane loads. Does not mutate repository configuration.
    func requestFocusRepositoryFromFailureNotification(repoID: UUID) {
        guard repos.contains(where: { $0.id == repoID }) else { return }
        pendingScrollToSyncLogRepoID = repoID
        pendingMainWindowRepoID = repoID
        bringMainWindowForwardForCommands()
    }

    func consumePendingEditFocusAuthRepoID() -> UUID? {
        defer { pendingEditFocusAuthRepoID = nil }
        return pendingEditFocusAuthRepoID
    }

    func consumePendingScrollToSyncLogRepoID() -> UUID? {
        defer { pendingScrollToSyncLogRepoID = nil }
        return pendingScrollToSyncLogRepoID
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
              !syncConcurrencyGate.isQueued(repoID),
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

    /// Whether 复制这次失败 has anything to copy. Cheap enough for a view body,
    /// unlike ``failureCopyText(for:)`` which may read the log file.
    func hasFailureToCopy(repoID: UUID) -> Bool {
        guard let repo = repos.first(where: { $0.id == repoID }) else { return false }
        if case .failed = statuses[repoID] { return true }
        return repo.lastSyncError != nil
    }

    /// Redacted clipboard payload behind 复制这次失败, or nil when this pair has
    /// no failure to copy.
    func failureCopyText(for repoID: UUID) -> String? {
        guard let repo = repos.first(where: { $0.id == repoID }) else { return nil }

        let message: String
        if case .failed(let statusMessage) = statuses[repoID] {
            message = statusMessage
        } else if let storedError = repo.lastSyncError {
            message = storedError
        } else {
            return nil
        }

        let failedRun = latestFailedRun(for: repoID)
        return SyncFailureCopy.text(
            repo: repo,
            message: message,
            logLines: failedRun?.logLines ?? [],
            failedAt: failedRun?.finishedAt ?? repo.lastSyncedAt
        )
    }

    /// The last failed run: the in-memory record when the failure happened in
    /// this session, otherwise the last failed run persisted in the log file.
    private func latestFailedRun(for repoID: UUID) -> (logLines: [String], finishedAt: Date?)? {
        if let record = records[repoID]?.last(where: { !$0.succeeded }) {
            return (record.logLines, record.finishedAt)
        }
        guard let persisted = try? SyncLogStore.loadRecords(for: repoID),
              let failed = persisted.last(where: { !$0.succeeded })
        else { return nil }
        return (failed.logLines, failed.finishedAt)
    }

    /// Runs the schedule's backlog after the machine wakes or the app becomes
    /// active. `Timer` does not fire with the lid closed, so without this the
    /// ticks slept through are lost until the next full interval.
    func catchUpMissedScheduledRuns(now: Date = Date()) {
        // A paused schedule has nothing to catch up; the pause line shows instead.
        guard scheduledSyncPauseReason == nil else { return }
        let expectations = repos.compactMap { scheduler.runExpectation(for: $0.id) }
        let outcome = MissedScheduledRuns.evaluate(expectations: expectations, now: now)
        guard outcome.hasMissedRuns else { return }

        var admitted: [UUID] = []
        for id in outcome.dueRepoIDs {
            triggerSync(repoID: id)
            if inProgressSyncIDs.contains(id) || syncConcurrencyGate.isQueued(id) {
                admitted.append(id)
            }
            // Re-arm so the catch-up run does not stack with the next due tick.
            if let repo = repos.first(where: { $0.id == id }) {
                scheduler.reschedule(repo: repo)
            }
        }
        missedRunCatchUp.begin(missedRunCount: outcome.missedRunCount, repoIDs: admitted)
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

    private func handleScheduledSyncFire(repoID: UUID) {
        if let reason = scheduledSyncPauseReason {
            if reason.isQuietHours {
                quietHoursCatchUp.noteScheduledSkip(repoID: repoID)
                logQuietHoursSkipIfNeeded()
            }
            wasScheduledSyncPaused = true
            return
        }
        quietHoursCatchUp.clear(repoID: repoID)
        triggerSync(repoID: repoID)
    }

    private func handleScheduledPauseTransition() {
        let paused = scheduledSyncPauseReason != nil
        if paused {
            wasScheduledSyncPaused = true
            return
        }
        guard wasScheduledSyncPaused || !quietHoursCatchUp.pendingRepoIDs.isEmpty else { return }
        wasScheduledSyncPaused = false
        let ids = quietHoursCatchUp.takePendingCatchUp()
        for id in ids {
            triggerSync(repoID: id)
            // Reset the repeating timer so catch-up does not stack with the next due tick.
            if let repo = repos.first(where: { $0.id == id }) {
                scheduler.reschedule(repo: repo)
            }
        }
    }

    private func logQuietHoursSkipIfNeeded() {
        let now = quietHoursMonitor.now()
        if let last = lastScheduledSkipLogAt, now.timeIntervalSince(last) < 3600 {
            return
        }
        lastScheduledSkipLogAt = now
        // Keep this quiet: at most once per hour while quiet hours stay active.
        print("GitRelay: skipped scheduled sync during quiet hours")
    }

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
        missedRunCatchUp.noteFinished(repoID: repoID)
        inProgressSyncIDs.remove(repoID)
        activeSyncEngines.removeValue(forKey: repoID)
        syncPhases.removeValue(forKey: repoID)
        liveSyncLogLines.removeValue(forKey: repoID)
        if let next = syncConcurrencyGate.finishActive(repoID) {
            promoteQueuedSync(repoID: next)
        }
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
    ) async -> DestructivePushDecision {
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
        matching.forEach { $0.respond(.cancel) }
    }

    private func bringAppForwardForConfirmation() {
        bringMainWindowForwardForCommands()
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func bringMainWindowForwardForCommands() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .gitrelayOpenMainWindow, object: nil)
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
        if repo.needsCredentials {
            return .failed(RepoCredentialGate.missingCredentialsMessage)
        }
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
                self?.catchUpMissedScheduledRuns()
            }
        }
        // A menu-bar-only session may never become active, so watch the lid too.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.catchUpMissedScheduledRuns()
            }
        }
    }
}
