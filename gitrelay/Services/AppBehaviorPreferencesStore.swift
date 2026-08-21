import Foundation
import Observation

/// Persists app lifecycle preferences in UserDefaults (no secrets).
@MainActor
@Observable
final class AppBehaviorPreferencesStore {
    private enum Keys {
        static let keepInMenuBarWhenMainWindowCloses =
            "AppBehaviorPreferences.keepInMenuBarWhenMainWindowCloses"
    }

    private let defaults: UserDefaults
    private var storage: AppBehaviorPreferences

    var preferences: AppBehaviorPreferences {
        get { storage }
        set {
            storage = newValue
            persist(storage)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storage = Self.load(from: defaults)
    }

    func resetToDefaults() {
        preferences = .default
    }

    private func persist(_ value: AppBehaviorPreferences) {
        defaults.set(
            value.keepInMenuBarWhenMainWindowCloses,
            forKey: Keys.keepInMenuBarWhenMainWindowCloses
        )
    }

    private static func load(from defaults: UserDefaults) -> AppBehaviorPreferences {
        let fallback = AppBehaviorPreferences.default
        let keepInMenuBar: Bool
        if defaults.object(forKey: Keys.keepInMenuBarWhenMainWindowCloses) == nil {
            keepInMenuBar = fallback.keepInMenuBarWhenMainWindowCloses
        } else {
            keepInMenuBar = defaults.bool(forKey: Keys.keepInMenuBarWhenMainWindowCloses)
        }
        return AppBehaviorPreferences(keepInMenuBarWhenMainWindowCloses: keepInMenuBar)
    }
}
