import Foundation
@testable import GitRelay

@MainActor
extension GitRelayAppModel {
    var repos: [MirrorSnapshot] { library.mirrors }
    var mirrorPlans: [MirrorPlan] { library.plans }
    var statuses: [UUID: SyncStatus] { operations.statuses }
    var syncPhases: [UUID: SyncPhase] { operations.syncPhases }
    var inProgressSyncIDs: Set<UUID> { operations.inProgressSyncIDs }
    var notificationPreferences: NotificationPreferencesStore { preferences.notificationStore }
    var failureNotifier: SyncFailureNotifier { notifications.failureNotifier }
    var menuBarStatusLine: MenuBarStatusLine? { scheduling.menuBarStatusLine }
    var scheduledSyncPauseReason: SyncPauseReason? { scheduling.pauseReason }
    var errorMessage: String? { issues.errorMessage }
    var pendingEditFocusAuthRepoID: UUID? { workspace.pendingEditCredentialsMirrorID }
    var pendingScrollToSyncLogRepoID: UUID? { workspace.pendingScrollToLogMirrorID }
    var pendingMainWindowRepoID: UUID? { workspace.pendingMirrorSelectionID }
    var pendingOpenAddRepository: Bool { workspace.pendingOpenAddMirror }
    var pendingFocusSidebarSearch: Bool { workspace.pendingFocusSearch }

    var mainWindowSelectedRepoID: UUID? {
        get { workspace.selectedMirrorID }
        set { workspace.selectedMirrorID = newValue }
    }

    var suspendSyncEngineForTesting: Bool {
        get { operations.suspendSyncEngineForTesting }
        set { operations.suspendSyncEngineForTesting = newValue }
    }

    var isScheduledSyncManuallyPaused: Bool {
        preferences.notificationStore.preferences.scheduledSyncManuallyPaused
    }

    func addRepo(_ mirror: MirrorSnapshot) {
        management.add(mirror)
    }

    func updateRepo(_ mirror: MirrorSnapshot) {
        management.update(mirror)
    }

    func deleteRepo(id: UUID) {
        management.delete(mirrorID: id)
    }

    func updateFrequency(matchingTag tag: String?, frequency: SyncFrequency) {
        management.updateFrequency(matchingTag: tag, frequency: frequency)
    }

    func repos(matchingTag tag: String?) -> [MirrorSnapshot] {
        management.mirrors(matchingTag: tag)
    }

    func triggerSync(repoID: UUID) {
        operations.triggerSync(mirrorID: repoID)
    }

    func triggerSyncAll() {
        operations.triggerSyncAll()
    }

    func cancelSync(repoID: UUID) {
        operations.cancelSync(mirrorID: repoID)
    }

    func nextFireDate(for repoID: UUID) -> Date? {
        scheduling.nextFireDate(mirrorID: repoID)
    }

    func setScheduledSyncManuallyPaused(_ paused: Bool) {
        var value = preferences.notificationStore.preferences
        value.scheduledSyncManuallyPaused = paused
        preferences.notificationStore.preferences = value
    }

    func toggleScheduledSyncPause() {
        setScheduledSyncManuallyPaused(!isScheduledSyncManuallyPaused)
    }

    func isScheduledSyncPaused(repoID: UUID) -> Bool {
        management.isScheduledSyncPaused(mirrorID: repoID)
    }

    func toggleScheduledSyncPause(repoID: UUID) {
        management.toggleScheduledSyncPause(mirrorID: repoID)
    }

    func setScheduledSyncPaused(_ paused: Bool, repoID: UUID) {
        management.setScheduledSyncPaused(paused, mirrorID: repoID)
    }

    func requestReenterCredentials(repoID: UUID) {
        workspace.requestEditCredentials(mirrorID: repoID)
    }

    func requestOpenSyncLog(repoID: UUID) {
        workspace.requestOpenSyncLog(mirrorID: repoID)
    }

    func requestOpenAddRepository() {
        workspace.requestOpenAddMirror()
    }

    func consumePendingOpenAddRepository() -> Bool {
        workspace.consumePendingOpenAddMirror()
    }

    func requestFocusSidebarSearch() {
        workspace.requestFocusSearch()
    }

    func consumePendingFocusSidebarSearch() -> Bool {
        workspace.consumePendingFocusSearch()
    }

    func syncMainWindowSelectedRepository() {
        guard let id = workspace.selectedMirrorID else { return }
        operations.triggerSync(mirrorID: id)
    }

    func catchUpMissedScheduledRuns(now: Date = Date()) {
        scheduling.catchUpMissedScheduledRuns(now: now)
    }

    @discardableResult
    func importConfiguration(
        from data: Data,
        mode: ConfigImportMode,
        probe: CredentialProbe? = nil
    ) throws -> ConfigImportPlan {
        try management.importConfiguration(from: data, mode: mode, probe: probe)
    }
}
