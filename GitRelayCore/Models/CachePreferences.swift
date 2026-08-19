import Foundation

/// User-adjustable limits for on-disk bare mirror storage.
struct CachePreferences: Equatable, Sendable {
    /// Hard cap in gigabytes; `nil` means unlimited.
    var cacheQuotaGB: Int?

    static let `default` = CachePreferences(cacheQuotaGB: nil)

    private enum Keys {
        static let cacheQuotaGB = "CachePreferences.cacheQuotaGB"
    }

    static func load(from defaults: UserDefaults = .standard) -> CachePreferences {
        guard defaults.object(forKey: Keys.cacheQuotaGB) != nil else {
            return .default
        }
        let quota = defaults.integer(forKey: Keys.cacheQuotaGB)
        return CachePreferences(cacheQuotaGB: quota > 0 ? quota : nil)
    }

    func save(to defaults: UserDefaults = .standard) {
        if let quota = cacheQuotaGB {
            defaults.set(quota, forKey: Keys.cacheQuotaGB)
        } else {
            defaults.removeObject(forKey: Keys.cacheQuotaGB)
        }
    }
}
