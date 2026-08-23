import Observation

/// Application composition root. It wires focused state owners together but
/// intentionally contains no feature behavior.
@MainActor
@Observable
final class GitRelayAppModel {
    let library: MirrorLibraryModel
    let operations: MirrorOperationsController
    let scheduling: MirrorSchedulingController
    let workspace: WorkspaceModel
    let issues: AppIssueModel
    let preferences: AppPreferencesModel
    let security: SecurityController
    let cache: MirrorCacheController
    let webhooks: WebhookController
    let notifications: NotificationController
    let orgDiscovery: OrgDiscoveryController
    let management: MirrorManagementController

    init(
        verificationPreferencesStore: VerificationPreferencesStore? = nil,
        orgSubscriptionStore: OrgSubscriptionStore? = nil,
        orgSubscriptionFetcher: OrgRemoteRepoFetcher? = nil,
        webhookPreferencesStore: WebhookPreferencesStore? = nil,
        securityPreferencesStore: SecurityPreferencesStore? = nil,
        cachePreferencesStore: CachePreferencesStore? = nil,
        notificationPreferencesStore: NotificationPreferencesStore? = nil,
        appBehaviorPreferencesStore: AppBehaviorPreferencesStore? = nil,
        defaultPolicyStore: MirrorDefaultPolicyStore? = nil,
        windowLayoutStore: WindowLayoutStore? = nil,
        biometricAuthenticator: BiometricAuthenticating? = nil,
        mirrorPlanStore: MirrorPlanStore = MirrorPlanStore(),
        mirrorStateStore: MirrorStateStore = MirrorStateStore(),
        mirrorRunStore: MirrorRunStore = MirrorRunStore(),
        library suppliedLibrary: MirrorLibraryModel? = nil,
        operations suppliedOperations: MirrorOperationsController? = nil,
        scheduling suppliedScheduling: MirrorSchedulingController? = nil,
        workspace suppliedWorkspace: WorkspaceModel? = nil,
        issues suppliedIssues: AppIssueModel? = nil,
        preferences suppliedPreferences: AppPreferencesModel? = nil,
        security suppliedSecurity: SecurityController? = nil,
        cache suppliedCache: MirrorCacheController? = nil,
        webhooks suppliedWebhooks: WebhookController? = nil,
        notifications suppliedNotifications: NotificationController? = nil,
        orgDiscovery suppliedOrgDiscovery: OrgDiscoveryController? = nil
    ) {
        let library = suppliedLibrary ?? MirrorLibraryModel(
            planStore: mirrorPlanStore,
            stateStore: mirrorStateStore,
            runStore: mirrorRunStore
        )
        let operations = suppliedOperations ?? MirrorOperationsController(library: library)
        let scheduling = suppliedScheduling ?? MirrorSchedulingController(
            library: library,
            operations: operations
        )
        let workspace = suppliedWorkspace ?? WorkspaceModel(
            library: library,
            operations: operations,
            scheduling: scheduling,
            windowLayout: windowLayoutStore ?? WindowLayoutStore()
        )
        let issues = suppliedIssues ?? AppIssueModel()
        let preferences = suppliedPreferences ?? AppPreferencesModel(
            verificationStore: verificationPreferencesStore,
            orgSubscriptionStore: orgSubscriptionStore,
            webhookStore: webhookPreferencesStore,
            securityStore: securityPreferencesStore,
            cacheStore: cachePreferencesStore,
            notificationStore: notificationPreferencesStore,
            behaviorStore: appBehaviorPreferencesStore,
            defaultPolicyStore: defaultPolicyStore
        )
        preferences.bindScheduling(scheduling, operations: operations)
        let security = suppliedSecurity ?? SecurityController(
            preferences: preferences.securityStore,
            authenticator: biometricAuthenticator
        )
        let cache = suppliedCache ?? MirrorCacheController(
            library: library,
            operations: operations,
            preferences: preferences.cacheStore,
            issues: issues
        )
        let webhooks = suppliedWebhooks ?? WebhookController(
            library: library,
            operations: operations,
            preferences: preferences.webhookStore,
            issues: issues
        )
        preferences.onWebhookPreferencesChange = { [weak webhooks] _ in
            webhooks?.refreshListener()
        }
        let notifications = suppliedNotifications ?? NotificationController(
            library: library,
            operations: operations,
            scheduling: scheduling,
            workspace: workspace,
            cache: cache,
            preferences: preferences.notificationStore,
            issues: issues
        )
        let orgDiscovery = suppliedOrgDiscovery ?? OrgDiscoveryController(
            library: library,
            scheduling: scheduling,
            preferences: preferences,
            notifications: notifications,
            issues: issues,
            fetcher: orgSubscriptionFetcher ?? .live
        )
        notifications.onOpenOrgDiscovery = { [weak orgDiscovery] id in
            orgDiscovery?.openDiscovery(subscriptionID: id)
        }
        let management = MirrorManagementController(
            library: library,
            operations: operations,
            scheduling: scheduling,
            workspace: workspace,
            issues: issues,
            preferences: preferences,
            cache: cache,
            webhooks: webhooks,
            notifications: notifications,
            orgDiscovery: orgDiscovery
        )
        orgDiscovery.onAddMirrors = { [weak management] mirrors, triggerSync in
            management?.add(contentsOf: mirrors, triggerSync: triggerSync)
        }
        self.library = library
        self.operations = operations
        self.scheduling = scheduling
        self.workspace = workspace
        self.issues = issues
        self.preferences = preferences
        self.security = security
        self.cache = cache
        self.webhooks = webhooks
        self.notifications = notifications
        self.orgDiscovery = orgDiscovery
        self.management = management
        if let libraryError = library.lastErrorMessage {
            issues.report(libraryError)
        }
        workspace.reconcileLibrary()
        AppIntentBridge.register(
            library: library,
            operations: operations,
            management: management
        )
        WidgetSnapshotPublisher.publish()
    }
}
