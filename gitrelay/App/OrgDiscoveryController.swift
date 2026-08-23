import Foundation
import Observation

@MainActor
@Observable
final class OrgDiscoveryController {
    private let library: MirrorLibraryModel
    private let scheduling: MirrorSchedulingController
    private let preferences: AppPreferencesModel
    private let notifications: NotificationController
    private let issues: AppIssueModel
    private let scheduler: OrgSubscriptionScheduler
    private let poller: OrgSubscriptionPoller

    private(set) var pendingDiscoveries: [OrgPendingDiscoveryItem] = []
    var onAddMirrors: (([MirrorSnapshot], Bool) -> Void)?

    var subscriptions: [OrgSubscription] { preferences.orgSubscriptions }
    var subscriptionPreferences: OrgSubscriptionPreferences {
        preferences.orgSubscriptionPreferences
    }
    var store: OrgSubscriptionStore { preferences.orgSubscriptionStore }
    var presentedDiscovery: OrgPendingDiscoveryItem? { pendingDiscoveries.first }

    init(
        library: MirrorLibraryModel,
        scheduling: MirrorSchedulingController,
        preferences: AppPreferencesModel,
        notifications: NotificationController,
        issues: AppIssueModel,
        fetcher: OrgRemoteRepoFetcher = .live,
        scheduler: OrgSubscriptionScheduler? = nil
    ) {
        let scheduler = scheduler ?? OrgSubscriptionScheduler()
        self.library = library
        self.scheduling = scheduling
        self.preferences = preferences
        self.notifications = notifications
        self.issues = issues
        self.scheduler = scheduler
        self.poller = OrgSubscriptionPoller(
            store: preferences.orgSubscriptionStore,
            fetcher: fetcher
        )
        preferences.onOrgPreferencesChange = { [weak scheduler] value in
            scheduler?.reschedule(frequency: value.pollFrequency)
        }
        scheduler.onFire = { [weak self] in
            Task { await self?.pollNow() }
        }
        scheduler.schedule(frequency: preferences.orgSubscriptionPreferences.pollFrequency)
    }

    func updatePreferences(_ value: OrgSubscriptionPreferences) {
        preferences.updateOrgSubscriptionPreferences(value)
    }

    func add(_ subscription: OrgSubscription) {
        store.add(subscription)
    }

    func update(_ subscription: OrgSubscription) {
        store.update(subscription)
    }

    func remove(id: UUID) {
        store.remove(id: id)
    }

    func saveTargetToken(_ token: String, subscriptionID: UUID) throws {
        try store.saveTargetToken(token, for: subscriptionID)
    }

    func nextFireDate() -> Date? {
        scheduler.nextFireDate()
    }

    func pollNow() async {
        guard scheduling.pauseReason == nil else { return }
        let results = await poller.checkAllSubscriptions(localMirrors: library.plans)
        for result in results where !result.newRepos.isEmpty {
            await process(result)
        }
    }

    func openDiscovery(subscriptionID: UUID) {
        guard let subscription = store.subscription(id: subscriptionID) else { return }
        Task {
            guard let result = await poller.checkSubscription(
                subscription,
                localMirrors: library.plans
            ) else { return }
            enqueue(result)
            presentIfNeeded()
        }
    }

    func resolve(_ decision: OrgDiscoveryDecision) {
        guard let current = presentedDiscovery else { return }
        let outcome = OrgDiscoveryDecisionHandler.outcome(
            for: decision,
            repoRemoteID: current.repo.id
        )
        if outcome.shouldPersistIgnore, let ignoredID = outcome.ignoredRepoID {
            persistIgnored(ignoredID, subscriptionID: current.subscriptionID)
        }
        pendingDiscoveries.removeFirst()
        if outcome.shouldJoinAndSync {
            Task {
                await joinAndSync(current)
                presentIfNeeded()
            }
        } else {
            presentIfNeeded()
        }
    }

    func canJoinAndSync(_ item: OrgPendingDiscoveryItem) -> Bool {
        OrgSubscriptionTemplateApplier.isValidTemplate(item.template)
    }

    func clearPendingDiscoveries() {
        pendingDiscoveries.removeAll()
    }

    private func process(_ result: OrgSubscriptionCheckResult) async {
        let actionable = OrgDiscoveryPendingFilter.actionableRepos(
            subscription: result.subscription,
            newRepos: result.newRepos,
            localMirrors: library.plans
        )
        guard !actionable.isEmpty else { return }
        let filtered = OrgSubscriptionCheckResult(
            subscription: result.subscription,
            newRepos: actionable,
            allRemoteRepos: result.allRemoteRepos
        )

        if result.subscription.autoAddEnabled {
            let plans = await OrgSubscriptionAutoAdder.addNewRepos(from: filtered, store: store)
            if !plans.isEmpty {
                onAddMirrors?(plans.map { MirrorSnapshot(plan: $0) }, true)
                return
            }
        }

        enqueue(filtered)
        presentIfNeeded()
        notifications.notifyDiscovery(
            filtered,
            enabled: subscriptionPreferences.notificationsEnabled
        )
    }

    private func enqueue(_ result: OrgSubscriptionCheckResult) {
        let gitlabHost = result.subscription.provider == .gitlab
            ? preferences.providerHost(
                for: .gitlab,
                accountLabel: result.subscription.accountLabel
            )
            : nil
        for repo in result.newRepos {
            let item = OrgPendingDiscoveryItem(
                subscriptionID: result.subscription.id,
                repo: repo,
                provider: result.subscription.provider,
                accountLabel: result.subscription.accountLabel,
                organizationName: result.subscription.organizationName,
                gitlabHost: gitlabHost,
                template: result.subscription.template
            )
            guard !pendingDiscoveries.contains(where: { $0.id == item.id }) else { continue }
            pendingDiscoveries.append(item)
        }
    }

    private func presentIfNeeded() {
        guard presentedDiscovery != nil else { return }
        notifications.presentConfirmation()
    }

    private func persistIgnored(_ remoteID: String, subscriptionID: UUID) {
        guard let subscription = store.subscription(id: subscriptionID),
              !subscription.ignoredDiscoveredRepoIDs.contains(remoteID) else { return }
        var updated = subscription
        updated.ignoredDiscoveredRepoIDs.append(remoteID)
        store.update(updated)
    }

    private func joinAndSync(_ item: OrgPendingDiscoveryItem) async {
        guard let subscription = store.subscription(id: item.subscriptionID) else { return }
        guard let plan = await OrgSubscriptionAutoAdder.addRepo(
            repo: item.repo,
            subscription: subscription,
            store: store
        ) else {
            issues.report(String.loc("Could not add the repository from the subscription template."))
            return
        }
        onAddMirrors?([MirrorSnapshot(plan: plan)], true)
    }
}
