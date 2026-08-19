import Foundation

/// User-adjustable alert preferences for sync failures and scheduled-sync pausing.
struct NotificationPreferences: Equatable, Sendable {
    /// Master switch for failure notifications.
    var notificationsEnabled: Bool

    /// Notify on the first consecutive failure of a streak.
    var notifyOnFirstFailure: Bool

    /// Also notify when consecutive failures reach this count (and multiples thereof).
    var consecutiveFailureThreshold: Int

    /// Delivery urgency for posted notifications.
    var interruptionLevel: NotificationInterruptionPreference

    /// Pause scheduled syncs while Low Power Mode is on.
    var pauseOnLowPowerMode: Bool

    /// Pause scheduled syncs on expensive / hotspot paths.
    var pauseOnExpensiveNetwork: Bool

    static let `default` = NotificationPreferences(
        notificationsEnabled: true,
        notifyOnFirstFailure: true,
        consecutiveFailureThreshold: 3,
        interruptionLevel: .active,
        pauseOnLowPowerMode: true,
        pauseOnExpensiveNetwork: true
    )

    var failurePolicy: FailureNotificationPolicy {
        FailureNotificationPolicy(
            isEnabled: notificationsEnabled,
            notifyOnFirstFailure: notifyOnFirstFailure,
            consecutiveFailureThreshold: consecutiveFailureThreshold
        )
    }

    var pausePolicy: SyncPausePolicy {
        SyncPausePolicy(
            pauseOnLowPowerMode: pauseOnLowPowerMode,
            pauseOnExpensiveNetwork: pauseOnExpensiveNetwork
        )
    }
}

enum NotificationInterruptionPreference: String, CaseIterable, Identifiable, Sendable {
    /// Does not break through Focus / Do Not Disturb.
    case passive
    /// Default banner / alert behavior.
    case active
    /// Time-sensitive; may break through Focus when allowed by the system.
    case timeSensitive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .passive: return String(localized: "Passive (Does Not Interrupt Focus)")
        case .active: return String(localized: "Standard")
        case .timeSensitive: return String(localized: "Time Sensitive")
        }
    }

    var helpText: String {
        switch self {
        case .passive:
            return String(localized: "Show only in Notification Center without interrupting the current Focus.")
        case .active:
            return String(localized: "Use the system's default notification behavior; notifications usually do not interrupt while Focus is on.")
        case .timeSensitive:
            return String(localized: "Allow time-sensitive notifications to interrupt Focus, subject to system settings.")
        }
    }
}
