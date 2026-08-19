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
        case .passive: return "被动（不打断专注）"
        case .active: return "标准"
        case .timeSensitive: return "时效性"
        }
    }

    var helpText: String {
        switch self {
        case .passive:
            return "仅在通知中心展示，不会打断当前专注模式。"
        case .active:
            return "系统默认通知行为；专注模式开启时通常不会打断。"
        case .timeSensitive:
            return "允许在专注模式下以时效性通知打断（仍受系统设置约束）。"
        }
    }
}
