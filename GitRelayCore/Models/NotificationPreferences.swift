import Foundation

/// User-adjustable alert preferences for sync failures and scheduled-sync pausing.
struct NotificationPreferences: Equatable, Sendable {
    enum DefaultsKey {
        static let transientGitMaxAttempts = "NotificationPreferences.transientGitMaxAttempts"
    }

    /// Master switch for failure notifications.
    var notificationsEnabled: Bool

    /// Notify on the first consecutive failure of a streak.
    var notifyOnFirstFailure: Bool

    /// Also notify when consecutive failures reach this count (and multiples thereof).
    var consecutiveFailureThreshold: Int

    /// Max git attempts per sync run for transient network errors (clamped by `GitRetryPolicy`).
    var transientGitMaxAttempts: Int

    /// Delivery urgency for posted notifications.
    var interruptionLevel: NotificationInterruptionPreference

    /// Pause scheduled syncs while Low Power Mode is on.
    var pauseOnLowPowerMode: Bool

    /// Pause scheduled syncs on expensive / hotspot paths.
    var pauseOnExpensiveNetwork: Bool

    /// Global quiet-hours window (local timezone). Off by default.
    var quietHours: QuietHoursSettings

    /// Max concurrent clone/fetch/push jobs (manual, webhook, and scheduled share this cap).
    var maxConcurrentSyncs: Int

    /// Explicit pause of frequency-driven syncs, toggled from the sidebar footer.
    /// Manual sync and instant webhook sync stay unaffected.
    var scheduledSyncManuallyPaused: Bool = false

    static let maxConcurrentSyncsRange = SyncConcurrencyGate.allowedRange

    static let `default` = NotificationPreferences(
        notificationsEnabled: true,
        notifyOnFirstFailure: true,
        consecutiveFailureThreshold: 3,
        transientGitMaxAttempts: GitRetryPolicy.defaultMaxAttempts,
        interruptionLevel: .active,
        pauseOnLowPowerMode: true,
        pauseOnExpensiveNetwork: true,
        quietHours: .default,
        maxConcurrentSyncs: SyncConcurrencyGate.defaultMaxConcurrent,
        scheduledSyncManuallyPaused: false
    )

    static func clampedMaxConcurrentSyncs(_ value: Int) -> Int {
        SyncConcurrencyGate.clamped(value)
    }

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
            pauseOnExpensiveNetwork: pauseOnExpensiveNetwork,
            quietHours: quietHours,
            manualPause: scheduledSyncManuallyPaused
        )
    }

    var gitRetryPolicy: GitRetryPolicy {
        GitRetryPolicy(maxAttempts: transientGitMaxAttempts)
    }

    /// Load the in-run git retry budget from UserDefaults (shared by app + CLI).
    static func gitRetryPolicy(from defaults: UserDefaults = .standard) -> GitRetryPolicy {
        if defaults.object(forKey: DefaultsKey.transientGitMaxAttempts) == nil {
            return .default
        }
        return GitRetryPolicy(
            maxAttempts: defaults.integer(forKey: DefaultsKey.transientGitMaxAttempts)
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
        case .passive: return String.loc("Passive (Does Not Interrupt Focus)")
        case .active: return String.loc("Standard")
        case .timeSensitive: return String.loc("Time Sensitive")
        }
    }

    var helpText: String {
        switch self {
        case .passive:
            return String.loc("Show only in Notification Center without interrupting the current Focus.")
        case .active:
            return String.loc("Use the system's default notification behavior; notifications usually do not interrupt while Focus is on.")
        case .timeSensitive:
            return String.loc("Allow time-sensitive notifications to interrupt Focus, subject to system settings.")
        }
    }
}
