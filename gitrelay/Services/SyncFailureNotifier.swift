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

/// Posts sync-failure alerts via `UNUserNotificationCenter`, with a Retry action,
/// Focus-aware deferral, and an aggregated summary when Focus ends.
@MainActor
@Observable
final class SyncFailureNotifier: NSObject {
    static let categoryIdentifier = "GITRELAY_SYNC_FAILURE"
    static let retryActionIdentifier = "GITRELAY_RETRY_SYNC"
    static let aggregatedCategoryIdentifier = "GITRELAY_SYNC_FAILURE_SUMMARY"
    static let repoIDKey = "repoID"

    private let center: UNUserNotificationCenter
    private let focusStatusProvider: () -> Bool?
    private var authorizationRequested = false

    /// Failures deferred while Focus was active (deduped by repo ID, latest wins).
    private(set) var pendingDuringFocus: [UUID: PendingFailureAlert] = [:]

    /// Called when the user taps Retry on a notification.
    var onRetry: ((UUID) -> Void)?

    init(
        center: UNUserNotificationCenter = .current(),
        focusStatusProvider: @escaping () -> Bool? = SyncFailureNotifier.readFocusStatus
    ) {
        self.center = center
        self.focusStatusProvider = focusStatusProvider
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
            message: message,
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

    // MARK: - Private

    private var isFocused: Bool {
        focusStatusProvider() == true
    }

    private static func readFocusStatus() -> Bool? {
        INFocusStatusCenter.default.focusStatus.isFocused
    }

    private func registerCategories() {
        let retry = UNNotificationAction(
            identifier: Self.retryActionIdentifier,
            title: String(localized: "Retry"),
            options: [.foreground]
        )
        let failure = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [retry],
            intentIdentifiers: [],
            options: []
        )
        let summary = UNNotificationCategory(
            identifier: Self.aggregatedCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([failure, summary])
    }

    private func postSingleFailure(_ alert: PendingFailureAlert, level: NotificationInterruptionPreference) {
        let content = UNMutableNotificationContent()
        content.title = FailureNotificationCopy.title(repoName: alert.repoName)
        content.body = FailureNotificationCopy.body(
            message: alert.message,
            consecutiveFailureCount: alert.consecutiveFailureCount
        )
        content.sound = .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.userInfo = [Self.repoIDKey: alert.repoID.uuidString]
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
            items: items.map { ($0.repoName, $0.message, $0.consecutiveFailureCount) }
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
}

extension SyncFailureNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let repoIDString = response.notification.request.content.userInfo[SyncFailureNotifier.repoIDKey] as? String
        let repoID = repoIDString.flatMap(UUID.init(uuidString:))

        Task { @MainActor in
            if action == SyncFailureNotifier.retryActionIdentifier, let repoID {
                onRetry?(repoID)
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
