import Foundation
import UserNotifications
import Intents
import Observation

/// Posts notifications when org/group subscriptions discover unmirrored repositories.
@MainActor
@Observable
final class OrgDiscoveryNotifier: NSObject {
    static let categoryIdentifier = "GITRELAY_ORG_DISCOVERY"
    static let viewActionIdentifier = "GITRELAY_ORG_DISCOVERY_VIEW"
    static let subscriptionIDKey = "subscriptionID"
    static let newRepoCountKey = "newRepoCount"

    private let center: UNUserNotificationCenter
    private let focusStatusProvider: () -> Bool?
    private var authorizationRequested = false

    private(set) var pendingDuringFocus: [UUID: OrgSubscriptionCheckResult] = [:]

    var onView: ((UUID) -> Void)?

    init(
        center: UNUserNotificationCenter = .current(),
        focusStatusProvider: (() -> Bool?)? = nil
    ) {
        self.center = center
        self.focusStatusProvider = focusStatusProvider ?? OrgDiscoveryNotifier.readFocusStatus
        super.init()
        // Do not claim `UNUserNotificationCenter.delegate` — ``SyncFailureNotifier`` owns it
        // and forwards org-discovery responses via `onOrgDiscoveryView`.
        registerCategories()
    }

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        INFocusStatusCenter.default.requestAuthorization { _ in }
    }

    func handleDiscovery(
        _ result: OrgSubscriptionCheckResult,
        notificationsEnabled: Bool,
        interruptionLevel: NotificationInterruptionPreference
    ) {
        guard notificationsEnabled, !result.newRepos.isEmpty else { return }
        requestAuthorizationIfNeeded()

        if isFocused {
            pendingDuringFocus[result.subscription.id] = result
            return
        }

        postDiscovery(result, level: interruptionLevel)
    }

    func flushPendingIfFocusEnded(level: NotificationInterruptionPreference) {
        guard !pendingDuringFocus.isEmpty, !isFocused else { return }
        let items = Array(pendingDuringFocus.values)
        pendingDuringFocus.removeAll()
        for result in items {
            postDiscovery(result, level: level)
        }
    }

    private var isFocused: Bool {
        focusStatusProvider() == true
    }

    private static func readFocusStatus() -> Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }

    private func registerCategories() {
        let view = UNNotificationAction(
            identifier: Self.viewActionIdentifier,
            title: String(localized: "View"),
            options: [.foreground]
        )
        let discovery = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [view],
            intentIdentifiers: [],
            options: []
        )
        // Preserve failure categories when re-registering so Sync again / Open stay available.
        var categories = SyncFailureNotifier.makeFailureCategories()
        categories.insert(discovery)
        center.setNotificationCategories(categories)
    }

    private func postDiscovery(
        _ result: OrgSubscriptionCheckResult,
        level: NotificationInterruptionPreference
    ) {
        let count = result.newRepos.count
        let org = result.subscription.organizationName
        let previewNames = result.newRepos.map(\.name)

        let content = UNMutableNotificationContent()
        content.title = OrgDiscoveryNotificationCopy.title(newRepoCount: count, organizationName: org)
        content.body = OrgDiscoveryNotificationCopy.body(newRepoCount: count, previewNames: previewNames)
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [
            Self.subscriptionIDKey: result.subscription.id.uuidString,
            Self.newRepoCountKey: count
        ]
        applyInterruptionLevel(level, to: content)

        let request = UNNotificationRequest(
            identifier: "org-discovery-\(result.subscription.id.uuidString)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func applyInterruptionLevel(
        _ level: NotificationInterruptionPreference,
        to content: UNMutableNotificationContent
    ) {
        switch level {
        case .passive:
            content.interruptionLevel = .passive
        case .active:
            content.interruptionLevel = .active
        case .timeSensitive:
            content.interruptionLevel = .timeSensitive
        }
    }
}
