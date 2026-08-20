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
    }

    private let defaults: UserDefaults
    private var storage: NotificationPreferences

    var preferences: NotificationPreferences {
        get { storage }
        set {
            storage = Self.normalized(newValue)
            persist(storage)
        }
    }

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
    }

    private static func normalized(_ value: NotificationPreferences) -> NotificationPreferences {
        var copy = value
        copy.consecutiveFailureThreshold = max(1, copy.consecutiveFailureThreshold)
        copy.transientGitMaxAttempts = GitRetryPolicy.clampedMaxAttempts(copy.transientGitMaxAttempts)
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

        return NotificationPreferences(
            notificationsEnabled: bool(forKey: Keys.notificationsEnabled, default: fallback.notificationsEnabled),
            notifyOnFirstFailure: bool(forKey: Keys.notifyOnFirstFailure, default: fallback.notifyOnFirstFailure),
            consecutiveFailureThreshold: threshold,
            transientGitMaxAttempts: retryAttempts,
            interruptionLevel: level,
            pauseOnLowPowerMode: bool(forKey: Keys.pauseOnLowPowerMode, default: fallback.pauseOnLowPowerMode),
            pauseOnExpensiveNetwork: bool(forKey: Keys.pauseOnExpensiveNetwork, default: fallback.pauseOnExpensiveNetwork)
        )
    }
}
