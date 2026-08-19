import Foundation

struct MirrorCacheEntry: Equatable, Sendable {
    let repoID: UUID
    let lastAccessedAt: Date
    let sizeBytes: Int64
}

enum MirrorCacheEvictionStep: Equatable, Sendable {
    case garbageCollect(repoID: UUID)
    case deleteMirror(repoID: UUID)
}

struct MirrorCacheCleanupPlan: Equatable, Sendable {
    let steps: [MirrorCacheEvictionStep]
    let finalUsageBytes: Int64
}

enum MirrorCacheManager {
    static let bytesPerGB: Int64 = 1_073_741_824

    static func quotaLimitBytes(for quotaGB: Int?) -> Int64? {
        guard let quotaGB else { return nil }
        guard quotaGB > 0 else { return 0 }
        return Int64(quotaGB) * bytesPerGB
    }

    static func isOverQuota(usageBytes: Int64, quotaGB: Int?) -> Bool {
        guard let limit = quotaLimitBytes(for: quotaGB) else { return false }
        return usageBytes > limit
    }

    static func lastAccessedAt(for repo: RepoConfig, mirrorModificationDate: Date?) -> Date {
        repo.lastSuccessfulSyncedAt ?? mirrorModificationDate ?? .distantPast
    }

    static func lruSorted(_ entries: [MirrorCacheEntry]) -> [MirrorCacheEntry] {
        entries.sorted { lhs, rhs in
            if lhs.lastAccessedAt != rhs.lastAccessedAt {
                return lhs.lastAccessedAt < rhs.lastAccessedAt
            }
            return lhs.repoID.uuidString < rhs.repoID.uuidString
        }
    }

    /// Builds an eviction plan using simulated post-GC sizes (for unit tests and dry runs).
    static func cleanupPlan(
        entries: [MirrorCacheEntry],
        quotaGB: Int?,
        totalUsageBytes: Int64,
        sizeAfterGC: (UUID) -> Int64
    ) -> MirrorCacheCleanupPlan {
        guard isOverQuota(usageBytes: totalUsageBytes, quotaGB: quotaGB) else {
            return MirrorCacheCleanupPlan(steps: [], finalUsageBytes: totalUsageBytes)
        }

        var usage = totalUsageBytes
        var steps: [MirrorCacheEvictionStep] = []
        var sizes = Dictionary(uniqueKeysWithValues: entries.map { ($0.repoID, $0.sizeBytes) })
        let ordered = lruSorted(entries.filter { sizes[$0.repoID, default: 0] > 0 })

        for entry in ordered {
            guard isOverQuota(usageBytes: usage, quotaGB: quotaGB) else { break }

            let beforeGC = sizes[entry.repoID, default: 0]
            guard beforeGC > 0 else { continue }

            steps.append(.garbageCollect(entry.repoID))
            let afterGC = min(beforeGC, max(0, sizeAfterGC(entry.repoID)))
            usage = usage - beforeGC + afterGC
            sizes[entry.repoID] = afterGC

            guard isOverQuota(usageBytes: usage, quotaGB: quotaGB) else { break }

            steps.append(.deleteMirror(entry.repoID))
            usage -= afterGC
            sizes[entry.repoID] = 0
        }

        return MirrorCacheCleanupPlan(steps: steps, finalUsageBytes: max(0, usage))
    }
}

enum MirrorDirectorySizer {
    static func directorySize(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }

        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }

    static let defaultSizeProvider: (URL) -> Int64 = { directorySize(at: $0) }

    static func mirrorsUsage(
        repos: [RepoConfig],
        mirrorsDirectory: URL = Constants.mirrorsDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = { directorySize(at: $0) }
    ) -> Int64 {
        var total: Int64 = 0
        var seen = Set<String>()

        for repo in repos {
            let path = mirrorsDirectory.appendingPathComponent(repo.id.uuidString)
            seen.insert(repo.id.uuidString)
            total += sizeOf(path)
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: mirrorsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return total
        }

        for entry in entries where !seen.contains(entry.lastPathComponent) {
            total += sizeOf(entry)
        }

        return total
    }

    static func mirrorEntries(
        repos: [RepoConfig],
        mirrorsDirectory: URL = Constants.mirrorsDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = { directorySize(at: $0) },
        modificationDate: (URL) -> Date? = { url in
            let keys: Set<URLResourceKey> = [.contentModificationDateKey]
            return try? url.resourceValues(forKeys: keys).contentModificationDate
        }
    ) -> [MirrorCacheEntry] {
        repos.compactMap { repo in
            let path = mirrorsDirectory.appendingPathComponent(repo.id.uuidString)
            let size = sizeOf(path)
            guard size > 0 else { return nil }
            let accessed = MirrorCacheManager.lastAccessedAt(
                for: repo,
                mirrorModificationDate: modificationDate(path)
            )
            return MirrorCacheEntry(repoID: repo.id, lastAccessedAt: accessed, sizeBytes: size)
        }
    }
}
