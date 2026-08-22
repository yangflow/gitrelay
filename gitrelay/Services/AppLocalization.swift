import Foundation

/// Catalog lookups for strings built in code, resolved against the language the
/// user picked *now* rather than the one the process launched with.
///
/// SwiftUI `Text` re-resolves through `\.locale`, which every scene already
/// carries, so those labels follow a language change on their own.
/// `String(localized:)` does not: it goes through `Bundle.main`, whose
/// preferred localization is fixed for the life of the process.
enum AppLocalization {
    private struct Override: Sendable {
        let locale: Locale
        let bundle: Bundle
    }

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var activeOverride: Override?

    nonisolated static func apply(_ preference: AppLanguagePreference, in bundle: Bundle = .main) {
        let resolved = resolveOverride(preference, in: bundle)
        lock.lock()
        activeOverride = resolved
        lock.unlock()
    }

    nonisolated static func string(for key: String.LocalizationValue) -> String {
        lock.lock()
        let active = activeOverride
        lock.unlock()
        guard let active else { return String(localized: key) }
        return String(localized: key, bundle: active.bundle, locale: active.locale)
    }

    private nonisolated static func resolveOverride(
        _ preference: AppLanguagePreference,
        in bundle: Bundle
    ) -> Override? {
        guard let target = targetLocalization(preference, in: bundle) else { return nil }
        if let current = bundle.preferredLocalizations.first,
           current.caseInsensitiveCompare(target) == .orderedSame {
            return nil
        }
        guard let path = bundle.path(forResource: target, ofType: "lproj"),
              let languageBundle = Bundle(path: path)
        else {
            return nil
        }
        return Override(locale: preference.locale, bundle: languageBundle)
    }

    private nonisolated static func targetLocalization(
        _ preference: AppLanguagePreference,
        in bundle: Bundle
    ) -> String? {
        if let code = preference.appleLanguageCode {
            return localizationName(for: code, available: bundle.localizations)
        }
        return Bundle.preferredLocalizations(
            from: bundle.localizations,
            forPreferences: nil
        ).first
    }

    nonisolated static func localizationName(for code: String?, available: [String]) -> String? {
        guard let code, !code.isEmpty else { return nil }
        if let exact = available.first(where: { $0.caseInsensitiveCompare(code) == .orderedSame }) {
            return exact
        }
        let language = code.split(separator: "-").first.map(String.init) ?? code
        if let bare = available.first(where: {
            $0.caseInsensitiveCompare(language) == .orderedSame
        }) {
            return bare
        }
        let prefix = language.lowercased() + "-"
        return available.first { $0.lowercased().hasPrefix(prefix) }
    }

    /// Clears any in-session catalog override. Unit tests should call this after
    /// exercising ``apply(_:)`` so later tests see the default catalog.
    nonisolated static func resetOverride() {
        lock.lock()
        activeOverride = nil
        lock.unlock()
    }
}

extension String {
    /// Catalog lookup that follows the in-app language choice.
    ///
    /// Prefer this over `String(localized:)` for anything a running window can
    /// show, so switching language in Settings does not leave the sentence in
    /// the previous language until the next launch.
    nonisolated static func loc(_ key: String.LocalizationValue) -> String {
        AppLocalization.string(for: key)
    }
}
