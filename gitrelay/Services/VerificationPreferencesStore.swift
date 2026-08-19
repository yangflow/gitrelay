import Foundation

@MainActor
final class VerificationPreferencesStore {
    private let defaults: UserDefaults
    private let key = "verificationPreferences"

    var preferences: VerificationPreferences {
        didSet {
            guard preferences != oldValue else { return }
            persist()
            onPreferencesChange?(preferences)
        }
    }

    var onPreferencesChange: ((VerificationPreferences) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(VerificationPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: key)
    }
}
