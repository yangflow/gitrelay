import Foundation
import Observation

/// Persists the language choice, mirrors it into `AppleLanguages` for the next
/// launch, points ``AppLocalization`` at the chosen catalog for strings built in
/// code, and exposes a SwiftUI `Locale` so open windows relabel themselves.
@MainActor
@Observable
final class AppLanguageStore {
    static let preferenceKey = "gitrelay.appLanguage"

    private let defaults: UserDefaults

    var preference: AppLanguagePreference {
        didSet {
            guard oldValue != preference else { return }
            defaults.set(preference.rawValue, forKey: Self.preferenceKey)
            Self.applyAppleLanguages(preference, defaults: defaults)
            AppLocalization.apply(preference)
        }
    }

    var locale: Locale { preference.locale }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = Self.storedPreference(defaults: defaults)
        self.preference = stored
    }

    /// Call once at process start so strings built in code match the saved
    /// choice, whether or not `AppleLanguages` landed in time for `Bundle.main`.
    static func bootstrapAppleLanguages(defaults: UserDefaults = .standard) {
        let preference = storedPreference(defaults: defaults)
        applyAppleLanguages(preference, defaults: defaults)
        AppLocalization.apply(preference)
    }

    static func storedPreference(defaults: UserDefaults = .standard) -> AppLanguagePreference {
        guard let raw = defaults.string(forKey: preferenceKey),
              let stored = AppLanguagePreference(rawValue: raw) else {
            return .system
        }
        return stored
    }

    static func applyAppleLanguages(
        _ preference: AppLanguagePreference,
        defaults: UserDefaults = .standard
    ) {
        if let code = preference.appleLanguageCode {
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }
}
