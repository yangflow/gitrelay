import Foundation

/// Remembers the last auth mode chosen in the add/edit repository sheet (no secrets).
nonisolated enum LastUsedAuthMode {
    private static let defaultsKey = "AddEditRepo.lastUsedAuthMode"

    static func load(from defaults: UserDefaults = .standard) -> AuthMode? {
        guard let raw = defaults.string(forKey: defaultsKey) else { return nil }
        return AuthMode(rawValue: raw)
    }

    static func save(_ mode: AuthMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}
