import Foundation
import Observation

/// Persists mirror cache quota preferences in UserDefaults.
@MainActor
@Observable
final class CachePreferencesStore {
    private let defaults: UserDefaults
    private var storage: CachePreferences

    var preferences: CachePreferences {
        get { storage }
        set {
            storage = newValue
            storage.save(to: defaults)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storage = CachePreferences.load(from: defaults)
    }

    func resetToDefaults() {
        preferences = .default
    }
}
