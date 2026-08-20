import Foundation
import Observation

/// Persists notification / pause preferences in UserDefaults (no secrets).
@MainActor
@Observable
final class NotificationPreferencesStore {
    private enum Keys {
        static let notificationsEnabled = "NotificationPreferences.notificationsEnabled"
        static let notifyOnFirstFailure = "NotificationPreferences.notifyOnFirstFailure"
        static let consecutiveFailureThreshold = "NotificationPreferences.consecutiveFailureThreshold"
        static let transientGitMaxAttempts = NotificationPreferences.DefaultsKey.transientGitMaxAttempts
        static let interruptionLevel = "NotificationPreferences.interruptionLevel"
        static let pauseOnLowPowerMode = "NotificationPreferences.pauseOnLowPowerMode"
        static let pauseOnExpensiveNetwork = "NotificationPreferences.pauseOnExpensiveNetwork"
        static let quietHoursEnabled = "NotificationPreferences.quietHoursEnabled"
        static let quietHoursStartMinutes = "NotificationPreferences.quietHoursStartMinutes"
        static let quietHoursEndMinutes = "NotificationPreferences.quietHoursEndMinutes"
    }

    private let defaults: UserDefaults
    private var storage: NotificationPreferences

    var preferences: NotificationPreferences {
        get { storage }
        set {
            storage = Self.normalized(newValue)
            persist(storage)
            onPreferencesChange?(storage)
        }
    }

    /// Fired after preferences are persisted (including reset).
    var onPreferencesChange: ((NotificationPreferences) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storage = Self.normalized(Self.load(from: defaults))
    }

    func resetToDefaults() {
        preferences = .default
    }

    private func persist(_ value: NotificationPreferences) {
        defaults.set(value.notificationsEnabled, forKey: Keys.notificationsEnabled)
        defaults.set(value.notifyOnFirstFailure, forKey: Keys.notifyOnFirstFailure)
        defaults.set(value.consecutiveFailureThreshold, forKey: Keys.consecutiveFailureThreshold)
        defaults.set(value.transientGitMaxAttempts, forKey: Keys.transientGitMaxAttempts)
        defaults.set(value.interruptionLevel.rawValue, forKey: Keys.interruptionLevel)
        defaults.set(value.pauseOnLowPowerMode, forKey: Keys.pauseOnLowPowerMode)
        defaults.set(value.pauseOnExpensiveNetwork, forKey: Keys.pauseOnExpensiveNetwork)
        defaults.set(value.quietHours.isEnabled, forKey: Keys.quietHoursEnabled)
        defaults.set(value.quietHours.startMinutes, forKey: Keys.quietHoursStartMinutes)
        defaults.set(value.quietHours.endMinutes, forKey: Keys.quietHoursEndMinutes)
    }

    private static func normalized(_ value: NotificationPreferences) -> NotificationPreferences {
        var copy = value
        copy.consecutiveFailureThreshold = max(1, copy.consecutiveFailureThreshold)
        copy.transientGitMaxAttempts = GitRetryPolicy.clampedMaxAttempts(copy.transientGitMaxAttempts)
        copy.quietHours = QuietHoursSettings(
            isEnabled: copy.quietHours.isEnabled,
            startMinutes: copy.quietHours.startMinutes,
            endMinutes: copy.quietHours.endMinutes
        )
        return copy
    }

    private static func load(from defaults: UserDefaults) -> NotificationPreferences {
        let fallback = NotificationPreferences.default
        let levelRaw = defaults.string(forKey: Keys.interruptionLevel)
        let level = levelRaw.flatMap(NotificationInterruptionPreference.init(rawValue:)) ?? fallback.interruptionLevel

        let threshold: Int
        if defaults.object(forKey: Keys.consecutiveFailureThreshold) == nil {
            threshold = fallback.consecutiveFailureThreshold
        } else {
            threshold = max(1, defaults.integer(forKey: Keys.consecutiveFailureThreshold))
        }

        let retryAttempts: Int
        if defaults.object(forKey: Keys.transientGitMaxAttempts) == nil {
            retryAttempts = fallback.transientGitMaxAttempts
        } else {
            retryAttempts = GitRetryPolicy.clampedMaxAttempts(defaults.integer(forKey: Keys.transientGitMaxAttempts))
        }

        func bool(forKey key: String, default defaultValue: Bool) -> Bool {
            if defaults.object(forKey: key) == nil { return defaultValue }
            return defaults.bool(forKey: key)
        }

        let quietHours: QuietHoursSettings
        if defaults.object(forKey: Keys.quietHoursEnabled) == nil
            && defaults.object(forKey: Keys.quietHoursStartMinutes) == nil
            && defaults.object(forKey: Keys.quietHoursEndMinutes) == nil
        {
            quietHours = fallback.quietHours
        } else {
            let start: Int
            if defaults.object(forKey: Keys.quietHoursStartMinutes) == nil {
                start = fallback.quietHours.startMinutes
            } else {
                start = defaults.integer(forKey: Keys.quietHoursStartMinutes)
            }
            let end: Int
            if defaults.object(forKey: Keys.quietHoursEndMinutes) == nil {
                end = fallback.quietHours.endMinutes
            } else {
                end = defaults.integer(forKey: Keys.quietHoursEndMinutes)
            }
            quietHours = QuietHoursSettings(
                isEnabled: bool(forKey: Keys.quietHoursEnabled, default: fallback.quietHours.isEnabled),
                startMinutes: start,
                endMinutes: end
            )
        }

        return NotificationPreferences(
            notificationsEnabled: bool(forKey: Keys.notificationsEnabled, default: fallback.notificationsEnabled),
            notifyOnFirstFailure: bool(forKey: Keys.notifyOnFirstFailure, default: fallback.notifyOnFirstFailure),
            consecutiveFailureThreshold: threshold,
            transientGitMaxAttempts: retryAttempts,
            interruptionLevel: level,
            pauseOnLowPowerMode: bool(forKey: Keys.pauseOnLowPowerMode, default: fallback.pauseOnLowPowerMode),
            pauseOnExpensiveNetwork: bool(forKey: Keys.pauseOnExpensiveNetwork, default: fallback.pauseOnExpensiveNetwork),
            quietHours: quietHours
        )
    }
}
