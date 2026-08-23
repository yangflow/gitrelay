import Foundation
import Observation

/// Persists the policy template used only when creating new mirrors.
@MainActor
@Observable
final class MirrorDefaultPolicyStore {
    private enum Keys {
        static let preferences = "GitRelay.defaultMirrorPolicy"
    }

    private let defaults: UserDefaults

    var preferences: MirrorDefaultPolicyPreferences {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Keys.preferences),
           let decoded = try? JSONDecoder().decode(MirrorDefaultPolicyPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
    }

    func resetToDefaults() {
        preferences = .default
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Keys.preferences)
    }
}
