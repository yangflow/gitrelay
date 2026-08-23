import AppKit
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationController {
    let failureNotifier: SyncFailureNotifier
    let orgDiscoveryNotifier: OrgDiscoveryNotifier

    private let library: MirrorLibraryModel
    private let operations: MirrorOperationsController
    private let scheduling: MirrorSchedulingController
    private let workspace: WorkspaceModel
    private let cache: MirrorCacheController
    private let preferences: NotificationPreferencesStore
    private let issues: AppIssueModel
    private var flushTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?

    var onOpenOrgDiscovery: ((UUID) -> Void)? {
        didSet {
            orgDiscoveryNotifier.onView = onOpenOrgDiscovery
            failureNotifier.onOrgDiscoveryView = onOpenOrgDiscovery
        }
    }

    init(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        scheduling: MirrorSchedulingController,
        workspace: WorkspaceModel,
        cache: MirrorCacheController,
        preferences: NotificationPreferencesStore,
        issues: AppIssueModel,
        failureNotifier: SyncFailureNotifier? = nil,
        orgDiscoveryNotifier: OrgDiscoveryNotifier? = nil
    ) {
        let failureNotifier = failureNotifier ?? SyncFailureNotifier()
        let orgDiscoveryNotifier = orgDiscoveryNotifier ?? OrgDiscoveryNotifier()
        self.library = library
        self.operations = operations
        self.scheduling = scheduling
        self.workspace = workspace
        self.cache = cache
        self.preferences = preferences
        self.issues = issues
        self.failureNotifier = failureNotifier
        self.orgDiscoveryNotifier = orgDiscoveryNotifier
        configureOperationCallbacks()
        configureNotificationActions()
        start()
    }

    func clearFailure(mirrorID: UUID) {
        failureNotifier.clearPending(for: mirrorID)
    }

    func notifyDiscovery(_ result: OrgSubscriptionCheckResult, enabled: Bool) {
        orgDiscoveryNotifier.handleDiscovery(
            result,
            notificationsEnabled: enabled,
            interruptionLevel: preferences.preferences.interruptionLevel
        )
    }

    func flushDeferred() {
        failureNotifier.flushPendingIfFocusEnded(
            level: preferences.preferences.interruptionLevel
        )
        orgDiscoveryNotifier.flushPendingIfFocusEnded(
            level: preferences.preferences.interruptionLevel
        )
    }

    func presentMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .gitrelayOpenMainWindow, object: nil)
    }

    func presentConfirmation() {
        presentMainWindow()
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func configureNotificationActions() {
        failureNotifier.onSyncAgain = { [weak operations] id in
            operations?.triggerSync(mirrorID: id)
        }
        failureNotifier.onOpen = { [weak self] id in
            guard let self, self.library.mirror(id: id) != nil else { return }
            self.workspace.requestOpenSyncLog(mirrorID: id)
            self.presentMainWindow()
        }
        UNUserNotificationCenter.current().delegate = failureNotifier
    }

    private func configureOperationCallbacks() {
        operations.retryPolicyProvider = { [weak preferences] in
            preferences?.preferences.gitRetryPolicy ?? .default
        }
        operations.onStateChange = {
            WidgetSnapshotPublisher.publish()
        }
        operations.onError = { [weak issues] message in
            issues?.report(message)
        }
        operations.onCredentialsRequired = { [weak issues, weak scheduling] id, message in
            issues?.report(message)
            scheduling?.deschedule(mirrorID: id)
        }
        operations.onSyncSettled = { [weak scheduling] id in
            scheduling?.noteOperationSettled(mirrorID: id)
        }
        operations.onSyncCompletion = { [weak self] id, completion in
            guard let self else { return }
            switch completion {
            case .succeeded:
                self.failureNotifier.clearPending(for: id)
                Task { await self.cache.enforceQuota(excluding: [id]) }
            case .failed(let message):
                self.notifyFailure(mirrorID: id, message: message)
            }
        }
        operations.onDestructiveConfirmationRequested = { [weak self] in
            self?.presentConfirmation()
        }
        scheduling.onStateChange = {
            WidgetSnapshotPublisher.publish()
        }
    }

    private func notifyFailure(mirrorID: UUID, message: String) {
        guard let mirror = library.mirror(id: mirrorID) else { return }
        failureNotifier.handleSyncFailure(
            repoID: mirrorID,
            repoName: mirror.name,
            message: message,
            consecutiveFailureCount: mirror.consecutiveFailureCount,
            preferences: preferences.preferences
        )
    }

    private func start() {
        failureNotifier.requestAuthorizationIfNeeded()
        orgDiscoveryNotifier.requestAuthorizationIfNeeded()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.flushDeferred()
            }
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushDeferred()
                self?.scheduling.catchUpMissedScheduledRuns()
            }
        }
    }
}
