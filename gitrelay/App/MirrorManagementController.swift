import Foundation
import Observation

/// Owns cross-domain mirror management transactions.
///
/// Views read live state from the focused library/operation controllers. This
/// controller exists only for commands that must commit configuration and then
/// reconcile several runtime owners as one product action.
@MainActor
@Observable
final class MirrorManagementController {
    let library: MirrorLibraryModel
    let operations: MirrorOperationsController
    let scheduling: MirrorSchedulingController

    private let workspace: WorkspaceModel
    private let issues: AppIssueModel
    private let preferences: AppPreferencesModel
    private let cache: MirrorCacheController
    private let webhooks: WebhookController
    private let notifications: NotificationController
    private let orgDiscovery: OrgDiscoveryController

    init(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        scheduling: MirrorSchedulingController,
        workspace: WorkspaceModel,
        issues: AppIssueModel,
        preferences: AppPreferencesModel,
        cache: MirrorCacheController,
        webhooks: WebhookController,
        notifications: NotificationController,
        orgDiscovery: OrgDiscoveryController
    ) {
        self.library = library
        self.operations = operations
        self.scheduling = scheduling
        self.workspace = workspace
        self.issues = issues
        self.preferences = preferences
        self.cache = cache
        self.webhooks = webhooks
        self.notifications = notifications
        self.orgDiscovery = orgDiscovery
    }

    var allKnownTags: [String] {
        RepoTagGrouping.allUniqueTags(from: library.mirrors)
    }

    func add(_ mirror: MirrorSnapshot, triggerSync: Bool = false) {
        add(contentsOf: [mirror], triggerSync: triggerSync)
    }

    func add(contentsOf additions: [MirrorSnapshot], triggerSync: Bool = false) {
        guard !additions.isEmpty else { return }
        let prepared = additions.map { mirror -> MirrorSnapshot in
            var mirror = mirror
            mirror.needsCredentials = MirrorCredentialGate.needsCredentials(for: mirror.plan)
            return mirror
        }
        guard commit({ try library.add(contentsOf: prepared) }) else { return }
        for mirror in prepared {
            operations.register(mirror)
            scheduling.register(mirror)
            if triggerSync { operations.triggerSync(mirrorID: mirror.id) }
        }
        publishSnapshot()
    }

    func update(_ mirror: MirrorSnapshot) {
        guard library.mirror(id: mirror.id) != nil else { return }
        var prepared = mirror
        prepared.needsCredentials = MirrorCredentialGate.needsCredentials(for: mirror.plan)
        guard commit({ try library.update(prepared) }) else { return }
        operations.update(prepared)
        scheduling.update(prepared)
        publishSnapshot()
    }

    func delete(mirrorID: UUID) {
        guard library.mirror(id: mirrorID) != nil,
              commit({ try library.remove(id: mirrorID) }) else { return }
        scheduling.unregister(mirrorID: mirrorID)
        operations.unregister(mirrorID: mirrorID)
        notifications.clearFailure(mirrorID: mirrorID)
        webhooks.removeSecret(mirrorID: mirrorID)
        cache.removeArtifacts(mirrorID: mirrorID)
        workspace.reconcileLibrary()
        publishSnapshot()
    }

    func mirrors(matchingTag tag: String?) -> [MirrorSnapshot] {
        RepoTagGrouping.repos(matching: tag, in: library.mirrors)
    }

    func updateFrequency(matchingTag tag: String?, frequency: SyncFrequency) {
        let targetIDs = Set(RepoTagGrouping.repoIDs(matching: tag, in: library.mirrors))
        guard !targetIDs.isEmpty else { return }
        var updated = library.mirrors
        for index in updated.indices where targetIDs.contains(updated[index].id) {
            updated[index].frequency = frequency
        }
        guard commit({ try library.replace(with: updated, preservePersistedHealth: true) }) else {
            return
        }
        library.mirrors.filter { targetIDs.contains($0.id) }.forEach(scheduling.update)
        publishSnapshot()
    }

    func isScheduledSyncPaused(mirrorID: UUID) -> Bool {
        library.mirror(id: mirrorID)?.scheduledSyncPaused ?? false
    }

    func setScheduledSyncPaused(_ paused: Bool, mirrorID: UUID) {
        guard let mirror = library.mirror(id: mirrorID),
              mirror.scheduledSyncPaused != paused,
              commit({
                  try library.mutateMirror(id: mirrorID) { $0.scheduledSyncPaused = paused }
              }),
              let updated = library.mirror(id: mirrorID) else { return }
        scheduling.update(updated)
        publishSnapshot()
    }

    func toggleScheduledSyncPause(mirrorID: UUID) {
        setScheduledSyncPaused(!isScheduledSyncPaused(mirrorID: mirrorID), mirrorID: mirrorID)
    }

    func surfaceSnapshot(mirrorID: UUID) -> MirrorSurfaceSnapshot? {
        guard let mirror = library.mirror(id: mirrorID) else { return nil }
        let schedule: MirrorScheduleState = mirror.scheduledSyncPaused
            ? .mirrorPaused
            : .active(nextRunAt: scheduling.nextFireDate(mirrorID: mirrorID))
        return MirrorSurfaceSupport.snapshot(
            plan: mirror.plan,
            health: mirror.health,
            activity: operations.activity(mirrorID: mirrorID),
            schedule: schedule
        )
    }

    func hasFailureToCopy(mirrorID: UUID) -> Bool {
        guard let mirror = library.mirror(id: mirrorID) else { return false }
        if case .failed = operations.statuses[mirrorID] { return true }
        return mirror.lastSyncError != nil
    }

    func failureCopyText(mirrorID: UUID) -> String? {
        guard let mirror = library.mirror(id: mirrorID) else { return nil }
        let message: String
        if case .failed(let current) = operations.statuses[mirrorID] {
            message = current
        } else if let persisted = mirror.lastSyncError {
            message = persisted
        } else {
            return nil
        }
        let failedRun = latestFailedRun(mirrorID: mirrorID)
        return SyncFailureCopy.text(
            repo: mirror,
            message: message,
            logLines: failedRun?.logLines ?? [],
            failedAt: failedRun?.finishedAt ?? mirror.lastSyncedAt
        )
    }

    func exportDocument(exportedAt: Date = Date()) -> ConfigExportDocument {
        ConfigExportCodec.makeDocument(
            mirrors: library.plans,
            providerAccounts: preferences.exportedProviderAccounts(),
            orgSubscriptions: preferences.orgSubscriptions,
            orgSubscriptionPreferences: preferences.orgSubscriptionPreferences,
            exportedAt: exportedAt
        )
    }

    func exportData(exportedAt: Date = Date()) throws -> Data {
        try ConfigExportCodec.encode(exportDocument(exportedAt: exportedAt))
    }

    @discardableResult
    func importConfiguration(
        from data: Data,
        mode: ConfigImportMode,
        probe: CredentialProbe? = nil
    ) throws -> ConfigImportPlan {
        let document = try ConfigExportCodec.decode(data)
        let plan = try ConfigExportCodec.planImport(
            document: document,
            mode: mode,
            existingMirrors: library.plans
        )
        let imported = projectedMirrors(
            plan.mirrors,
            preserveExistingHealth: mode == .merge,
            probe: probe ?? .live
        )
        try library.replace(with: imported, preservePersistedHealth: mode == .merge)
        resetRuntime()

        switch mode {
        case .replace:
            preferences.applyProviderAccounts(plan.providerAccounts, mode: .replace)
            preferences.orgSubscriptionStore.replaceAll(
                subscriptions: plan.orgSubscriptions,
                preferences: plan.orgSubscriptionPreferences
            )
        case .merge:
            preferences.applyProviderAccounts(plan.providerAccounts, mode: .merge)
            let merged = ConfigExportCodec.mergeSubscriptions(
                existing: preferences.orgSubscriptions,
                imported: plan.orgSubscriptions
            ).merged
            preferences.orgSubscriptionStore.replaceSubscriptions(merged)
            if let importedPreferences = plan.orgSubscriptionPreferences {
                preferences.orgSubscriptionStore.preferences = importedPreferences
            }
        }

        preferences.refreshOrgProjection()
        webhooks.refreshListener()
        publishSnapshot()
        return plan
    }

    private func projectedMirrors(
        _ plans: [MirrorPlan],
        preserveExistingHealth: Bool,
        probe: CredentialProbe
    ) -> [MirrorSnapshot] {
        let health = preserveExistingHealth
            ? Dictionary(uniqueKeysWithValues: library.mirrors.map { ($0.id, $0.health) })
            : [:]
        return plans.map { plan in
            var mirror = MirrorSnapshot(plan: plan, health: health[plan.id])
            mirror.needsCredentials = MirrorCredentialGate.needsCredentials(for: plan, probe: probe)
            return mirror
        }
    }

    private func resetRuntime() {
        let trackedIDs = operations.resetForCurrentLibrary()
        trackedIDs.forEach(notifications.clearFailure)
        scheduling.resetForCurrentLibrary()
        orgDiscovery.clearPendingDiscoveries()
        workspace.reconcileLibrary()
    }

    private func latestFailedRun(
        mirrorID: UUID
    ) -> (logLines: [String], finishedAt: Date?)? {
        if let record = operations.records[mirrorID]?.last(where: { !$0.succeeded }) {
            return (record.logLines, record.finishedAt)
        }
        guard let persisted = try? library.loadRuns(mirrorID: mirrorID),
              let failed = persisted.last(where: {
                  $0.kind == .sync && $0.outcome != .succeeded
              }) else { return nil }
        return (failed.logLines, failed.finishedAt)
    }

    @discardableResult
    private func commit(_ mutation: () throws -> Void) -> Bool {
        do {
            try mutation()
            return true
        } catch {
            issues.report(
                library.lastErrorMessage
                    ?? String(
                        format: String.loc("Failed to save mirror configuration: %@"),
                        error.localizedDescription
                    )
            )
            return false
        }
    }

    private func publishSnapshot() {
        WidgetSnapshotPublisher.publish()
    }
}
