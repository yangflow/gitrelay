import Foundation
import Observation

/// Persists security preferences in UserDefaults (no secrets).
@MainActor
@Observable
final class SecurityPreferencesStore {
    private enum Keys {
        static let requireBiometricForSensitive = "SecurityPreferences.requireBiometricForSensitive"
    }

    private let defaults: UserDefaults
    private var storage: SecurityPreferences

    var preferences: SecurityPreferences {
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

    private func persist(_ value: SecurityPreferences) {
        defaults.set(value.requireBiometricForSensitive, forKey: Keys.requireBiometricForSensitive)
    }

    private static func load(from defaults: UserDefaults) -> SecurityPreferences {
        let fallback = SecurityPreferences.default
        let requireBiometric: Bool
        if defaults.object(forKey: Keys.requireBiometricForSensitive) == nil {
            requireBiometric = fallback.requireBiometricForSensitive
        } else {
            requireBiometric = defaults.bool(forKey: Keys.requireBiometricForSensitive)
        }
        return SecurityPreferences(requireBiometricForSensitive: requireBiometric)
    }
}
