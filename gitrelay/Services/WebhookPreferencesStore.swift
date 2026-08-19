import Foundation
import Observation

/// Persists webhook listener preferences in UserDefaults (no secrets).
@MainActor
@Observable
final class WebhookPreferencesStore {
    private enum Keys {
        static let listenerEnabled = "WebhookPreferences.listenerEnabled"
        static let exposureMode = "WebhookPreferences.exposureMode"
        static let publicBaseURL = "WebhookPreferences.publicBaseURL"
    }

    private let defaults: UserDefaults
    private var storage: WebhookPreferences

    /// Fired after preferences are persisted so the listener can restart.
    var onPreferencesChange: ((WebhookPreferences) -> Void)?

    var preferences: WebhookPreferences {
        get { storage }
        set {
            storage = Self.normalized(newValue)
            persist(storage)
            onPreferencesChange?(storage)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.storage = Self.normalized(Self.load(from: defaults))
    }

    func resetToDefaults() {
        preferences = .default
    }

    private func persist(_ value: WebhookPreferences) {
        defaults.set(value.listenerEnabled, forKey: Keys.listenerEnabled)
        defaults.set(value.exposureMode.rawValue, forKey: Keys.exposureMode)
        defaults.set(value.publicBaseURL, forKey: Keys.publicBaseURL)
    }

    private static func normalized(_ value: WebhookPreferences) -> WebhookPreferences {
        var copy = value
        copy.publicBaseURL = copy.normalizedPublicBaseURL
        return copy
    }

    private static func load(from defaults: UserDefaults) -> WebhookPreferences {
        let fallback = WebhookPreferences.default
        let modeRaw = defaults.string(forKey: Keys.exposureMode)
        let mode = modeRaw.flatMap(WebhookExposureMode.init(rawValue:)) ?? fallback.exposureMode

        func bool(forKey key: String, default defaultValue: Bool) -> Bool {
            if defaults.object(forKey: key) == nil { return defaultValue }
            return defaults.bool(forKey: key)
        }

        return WebhookPreferences(
            listenerEnabled: bool(forKey: Keys.listenerEnabled, default: fallback.listenerEnabled),
            exposureMode: mode,
            publicBaseURL: defaults.string(forKey: Keys.publicBaseURL) ?? fallback.publicBaseURL
        )
    }
}
