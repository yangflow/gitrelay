import Foundation
import UserNotifications
import Intents
import Observation

/// Queued failure while Focus / Do Not Disturb is active.
struct PendingFailureAlert: Equatable, Sendable {
    var repoID: UUID
    var repoName: String
    var message: String
    var consecutiveFailureCount: Int
}

/// User-facing routes from a sync-failure notification action (or body tap).
nonisolated enum SyncFailureNotificationAction: Equatable, Sendable {
    case syncAgain
    case open
}

/// Builds and reads the failure-notification `userInfo` payload (repo id only).
nonisolated enum SyncFailureNotificationPayload {
    nonisolated static func userInfo(repoID: UUID) -> [AnyHashable: Any] {
        [SyncFailureNotifier.repoIDKey: repoID.uuidString]
    }

    nonisolated static func repoID(from userInfo: [AnyHashable: Any]) -> UUID? {
        guard let raw = userInfo[SyncFailureNotifier.repoIDKey] as? String else { return nil }
        return UUID(uuidString: raw)
    }
}

/// Maps `UNNotificationResponse.actionIdentifier` values to failure-notification actions.
nonisolated enum SyncFailureNotificationRouting {
    nonisolated static func action(for identifier: String) -> SyncFailureNotificationAction? {
        switch identifier {
        case SyncFailureNotifier.syncAgainActionIdentifier:
            return .syncAgain
        case SyncFailureNotifier.openActionIdentifier,
             UNNotificationDefaultActionIdentifier:
            return .open
        default:
            return nil
        }
    }
}

/// Posts sync-failure alerts via `UNUserNotificationCenter`, with Sync again / Open actions,
/// Focus-aware deferral, and an aggregated summary when Focus ends.
@MainActor
@Observable
final class SyncFailureNotifier: NSObject {
    nonisolated static let categoryIdentifier = "GITRELAY_SYNC_FAILURE"
    /// Kept as the historical identifier so already-delivered notifications still route.
    nonisolated static let syncAgainActionIdentifier = "GITRELAY_RETRY_SYNC"
    nonisolated static let retryActionIdentifier = syncAgainActionIdentifier
    nonisolated static let openActionIdentifier = "GITRELAY_OPEN_REPO"
    nonisolated static let aggregatedCategoryIdentifier = "GITRELAY_SYNC_FAILURE_SUMMARY"
    nonisolated static let repoIDKey = "repoID"

    private let center: UNUserNotificationCenter
    private let focusStatusProvider: () -> Bool?
    private var authorizationRequested = false

    /// Failures deferred while Focus was active (deduped by repo ID, latest wins).
    private(set) var pendingDuringFocus: [UUID: PendingFailureAlert] = [:]

    /// Called when the user chooses Sync again on a failure notification.
    var onSyncAgain: ((UUID) -> Void)?

    /// Called when the user chooses Open (or taps the banner body) on a failure notification.
    var onOpen: ((UUID) -> Void)?

    /// Forwards org-discovery notification responses when this notifier owns the center delegate.
    var onOrgDiscoveryView: ((UUID) -> Void)?

    init(
        center: UNUserNotificationCenter = .current(),
        focusStatusProvider: (() -> Bool?)? = nil
    ) {
        self.center = center
        self.focusStatusProvider = focusStatusProvider ?? SyncFailureNotifier.readFocusStatus
        super.init()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        INFocusStatusCenter.default.requestAuthorization { _ in }
    }

    /// Evaluate policy and either post immediately or queue for after Focus.
    func handleSyncFailure(
        repoID: UUID,
        repoName: String,
        message: String,
        consecutiveFailureCount: Int,
        preferences: NotificationPreferences
    ) {
        // User-initiated cancel is not an alert-worthy failure.
        guard message != "Cancelled" else { return }
        guard preferences.failurePolicy.shouldNotify(consecutiveFailureCount: consecutiveFailureCount) else {
            return
        }

        requestAuthorizationIfNeeded()

        let alert = PendingFailureAlert(
            repoID: repoID,
            repoName: repoName,
            message: SyncEngine.redactCredentials(message),
            consecutiveFailureCount: consecutiveFailureCount
        )

        if isFocused {
            pendingDuringFocus[repoID] = alert
            return
        }

        postSingleFailure(alert, level: preferences.interruptionLevel)
    }

    /// Drop queued alerts for a repo after a successful sync.
    func clearPending(for repoID: UUID) {
        pendingDuringFocus.removeValue(forKey: repoID)
    }

    /// If Focus has ended, flush any deferred failures as one summary (or a single alert).
    func flushPendingIfFocusEnded(level: NotificationInterruptionPreference) {
        guard !pendingDuringFocus.isEmpty else { return }
        guard !isFocused else { return }

        let items = Array(pendingDuringFocus.values).sorted { $0.repoName < $1.repoName }
        pendingDuringFocus.removeAll()

        if items.count == 1, let only = items.first {
            postSingleFailure(only, level: level)
        } else {
            postAggregatedSummary(items, level: level)
        }
    }

    /// Applies a failure-notification action using the same mapping as the system delegate.
    /// Exposed for unit tests; production paths go through `UNUserNotificationCenterDelegate`.
    func handleAction(identifier: String, userInfo: [AnyHashable: Any]) {
        guard let repoID = SyncFailureNotificationPayload.repoID(from: userInfo),
              let action = SyncFailureNotificationRouting.action(for: identifier) else {
            return
        }

        switch action {
        case .syncAgain:
            onSyncAgain?(repoID)
        case .open:
            onOpen?(repoID)
        }
    }

    // MARK: - Categories

    /// Failure + summary categories shared with ``OrgDiscoveryNotifier`` registration.
    static func makeFailureCategories() -> Set<UNNotificationCategory> {
        let syncAgain = UNNotificationAction(
            identifier: syncAgainActionIdentifier,
            title: String.loc("Sync again"),
            options: [.foreground]
        )
        let open = UNNotificationAction(
            identifier: openActionIdentifier,
            title: String.loc("Open"),
            options: [.foreground]
        )
        let failure = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [syncAgain, open],
            intentIdentifiers: [],
            options: []
        )
        let summary = UNNotificationCategory(
            identifier: aggregatedCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        return [failure, summary]
    }

    // MARK: - Private

    private var isFocused: Bool {
        focusStatusProvider() == true
    }

    private static func readFocusStatus() -> Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }

    private func registerCategories() {
        center.setNotificationCategories(Self.makeFailureCategories())
    }

    private func postSingleFailure(_ alert: PendingFailureAlert, level: NotificationInterruptionPreference) {
        let content = UNMutableNotificationContent()
        content.title = FailureNotificationCopy.title(repoName: alert.repoName)
        content.body = FailureNotificationCopy.body(
            message: SyncEngine.redactCredentials(alert.message),
            consecutiveFailureCount: alert.consecutiveFailureCount
        )
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = SyncFailureNotificationPayload.userInfo(repoID: alert.repoID)
        applyInterruptionLevel(level, to: content)

        let request = UNNotificationRequest(
            identifier: "sync-failure-\(alert.repoID.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func postAggregatedSummary(
        _ items: [PendingFailureAlert],
        level: NotificationInterruptionPreference
    ) {
        let content = UNMutableNotificationContent()
        content.title = FailureNotificationCopy.aggregatedTitle(failureCount: items.count)
        content.body = FailureNotificationCopy.aggregatedBody(
            items: items.map {
                ($0.repoName, SyncEngine.redactCredentials($0.message), $0.consecutiveFailureCount)
            }
        )
        content.sound = .default
        content.categoryIdentifier = Self.aggregatedCategoryIdentifier
        applyInterruptionLevel(level, to: content)

        let request = UNNotificationRequest(
            identifier: "sync-failure-summary-\(UUID().uuidString)",
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

    private func handleOrgDiscoveryAction(identifier: String, userInfo: [AnyHashable: Any]) {
        let subscriptionIDString = userInfo[OrgDiscoveryNotifier.subscriptionIDKey] as? String
        let subscriptionID = subscriptionIDString.flatMap(UUID.init(uuidString:))
        guard let subscriptionID else { return }
        if identifier == OrgDiscoveryNotifier.viewActionIdentifier
            || identifier == UNNotificationDefaultActionIdentifier {
            onOrgDiscoveryView?(subscriptionID)
        }
    }
}

extension SyncFailureNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let userInfo = response.notification.request.content.userInfo
        let repoID = (userInfo[SyncFailureNotifier.repoIDKey] as? String)
            .flatMap(UUID.init(uuidString:))
        let subscriptionID = (userInfo[OrgDiscoveryNotifier.subscriptionIDKey] as? String)
            .flatMap(UUID.init(uuidString:))

        Task { @MainActor in
            if category == OrgDiscoveryNotifier.categoryIdentifier {
                if let subscriptionID,
                   action == OrgDiscoveryNotifier.viewActionIdentifier
                    || action == UNNotificationDefaultActionIdentifier {
                    onOrgDiscoveryView?(subscriptionID)
                }
            } else if category == SyncFailureNotifier.categoryIdentifier {
                if let repoID,
                   let routed = SyncFailureNotificationRouting.action(for: action) {
                    switch routed {
                    case .syncAgain:
                        onSyncAgain?(repoID)
                    case .open:
                        onOpen?(repoID)
                    }
                }
            }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
