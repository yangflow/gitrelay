import CryptoKit
import Foundation

nonisolated enum ProviderTokenScopeCache {
    private static let storageKey = "ProviderTokenScopeCache.entries"
    private static let defaults = UserDefaults.standard

    private struct Entry: Codable {
        let scopes: [String]
        let fetchedAt: Date
    }

    static func cacheKey(provider: GitProvider, token: String, baseURL: URL? = nil) -> String {
        var material = "\(provider.rawValue)|\(token)"
        if let baseURL {
            material += "|\(baseURL.absoluteString)"
        }
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func load(key: String, now: Date = Date()) -> Set<String>? {
        guard let entry = allEntries()[key] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) < ProviderTokenScope.cacheLifetime else {
            remove(key: key)
            return nil
        }
        return Set(entry.scopes)
    }

    static func save(key: String, scopes: Set<String>, fetchedAt: Date = Date()) {
        var entries = allEntries()
        entries[key] = Entry(scopes: scopes.sorted(), fetchedAt: fetchedAt)
        persist(entries)
    }

    static func remove(key: String) {
        var entries = allEntries()
        entries.removeValue(forKey: key)
        persist(entries)
    }

    private static func allEntries() -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func persist(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
