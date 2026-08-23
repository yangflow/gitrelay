import Observation

/// Owns global preference stores and propagates changes to the controllers
/// that consume them. Feature controllers never compete for a store callback.
@MainActor
@Observable
final class AppPreferencesModel {
    let verificationStore: VerificationPreferencesStore
    let orgSubscriptionStore: OrgSubscriptionStore
    let webhookStore: WebhookPreferencesStore
    let securityStore: SecurityPreferencesStore
    let cacheStore: CachePreferencesStore
    let notificationStore: NotificationPreferencesStore
    let behaviorStore: AppBehaviorPreferencesStore
    let defaultPolicyStore: MirrorDefaultPolicyStore

    private(set) var verification: VerificationPreferences
    private(set) var orgSubscriptionPreferences: OrgSubscriptionPreferences
    private(set) var orgSubscriptions: [OrgSubscription]

    var onOrgPreferencesChange: ((OrgSubscriptionPreferences) -> Void)?
    var onOrgSubscriptionsChange: (([OrgSubscription]) -> Void)?
    var onWebhookPreferencesChange: ((WebhookPreferences) -> Void)?
    private var isSchedulingBound = false

    init(
        verificationStore: VerificationPreferencesStore? = nil,
        orgSubscriptionStore: OrgSubscriptionStore? = nil,
        webhookStore: WebhookPreferencesStore? = nil,
        securityStore: SecurityPreferencesStore? = nil,
        cacheStore: CachePreferencesStore? = nil,
        notificationStore: NotificationPreferencesStore? = nil,
        behaviorStore: AppBehaviorPreferencesStore? = nil,
        defaultPolicyStore: MirrorDefaultPolicyStore? = nil
    ) {
        let verificationStore = verificationStore ?? VerificationPreferencesStore()
        let orgSubscriptionStore = orgSubscriptionStore ?? OrgSubscriptionStore()
        let webhookStore = webhookStore ?? WebhookPreferencesStore()
        let securityStore = securityStore ?? SecurityPreferencesStore()
        let cacheStore = cacheStore ?? CachePreferencesStore()
        let notificationStore = notificationStore ?? NotificationPreferencesStore()
        let behaviorStore = behaviorStore ?? AppBehaviorPreferencesStore()
        let defaultPolicyStore = defaultPolicyStore ?? MirrorDefaultPolicyStore()
        self.verificationStore = verificationStore
        self.orgSubscriptionStore = orgSubscriptionStore
        self.webhookStore = webhookStore
        self.securityStore = securityStore
        self.cacheStore = cacheStore
        self.notificationStore = notificationStore
        self.behaviorStore = behaviorStore
        self.defaultPolicyStore = defaultPolicyStore
        self.verification = verificationStore.preferences
        self.orgSubscriptionPreferences = orgSubscriptionStore.preferences
        self.orgSubscriptions = orgSubscriptionStore.subscriptions

        verificationStore.onPreferencesChange = { [weak self] value in
            self?.verification = value
        }
        orgSubscriptionStore.onPreferencesChange = { [weak self] value in
            self?.orgSubscriptionPreferences = value
            self?.onOrgPreferencesChange?(value)
        }
        orgSubscriptionStore.onSubscriptionsChange = { [weak self] value in
            self?.orgSubscriptions = value
            self?.onOrgSubscriptionsChange?(value)
        }
        webhookStore.onPreferencesChange = { [weak self] value in
            self?.onWebhookPreferencesChange?(value)
        }
    }

    func bindScheduling(
        _ scheduling: MirrorSchedulingController,
        operations: MirrorOperationsController
    ) {
        guard !isSchedulingBound else { return }
        isSchedulingBound = true
        verificationStore.onPreferencesChange = { [weak self, weak scheduling] value in
            self?.verification = value
            scheduling?.updateVerificationPreferences(value)
        }
        notificationStore.onPreferencesChange = { [weak scheduling, weak operations] value in
            scheduling?.updateNotificationPreferences(value)
            operations?.updateMaxConcurrentSyncs(value.maxConcurrentSyncs)
        }
        operations.updateMaxConcurrentSyncs(notificationStore.preferences.maxConcurrentSyncs)
        scheduling.start(
            notificationPreferences: notificationStore.preferences,
            verificationPreferences: verification
        )
    }

    func updateVerification(_ value: VerificationPreferences) {
        verificationStore.preferences = value
    }

    func updateOrgSubscriptionPreferences(_ value: OrgSubscriptionPreferences) {
        orgSubscriptionStore.preferences = value
    }

    func refreshOrgProjection() {
        orgSubscriptions = orgSubscriptionStore.subscriptions
        orgSubscriptionPreferences = orgSubscriptionStore.preferences
    }

    func exportedProviderAccounts() -> [ExportedProviderAccount] {
        ProviderAccountStore.exportedAccounts()
    }

    func applyProviderAccounts(_ accounts: [ExportedProviderAccount], mode: ConfigImportMode) {
        switch mode {
        case .replace:
            ProviderAccountStore.replaceExportedAccounts(accounts)
        case .merge:
            ProviderAccountStore.mergeExportedAccounts(accounts)
        }
    }

    func providerHost(for provider: GitProvider, accountLabel: String) -> String? {
        ProviderAccountStore.host(for: provider, label: accountLabel)
    }
}
