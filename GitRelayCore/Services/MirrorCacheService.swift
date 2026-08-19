import Foundation

struct MirrorCacheCleanupResult: Equatable, Sendable {
    let steps: [MirrorCacheEvictionStep]
    let initialUsageBytes: Int64
    let finalUsageBytes: Int64

    var bytesFreed: Int64 {
        max(0, initialUsageBytes - finalUsageBytes)
    }
}

enum MirrorCacheService {
    static func currentUsageBytes(
        repos: [RepoConfig],
        mirrorsDirectory: URL = Constants.mirrorsDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider
    ) -> Int64 {
        MirrorDirectorySizer.mirrorsUsage(
            repos: repos,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )
    }

    static func mirrorEntries(
        repos: [RepoConfig],
        mirrorsDirectory: URL = Constants.mirrorsDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider
    ) -> [MirrorCacheEntry] {
        MirrorDirectorySizer.mirrorEntries(
            repos: repos,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )
    }

    @MainActor
    static func performCleanup(
        repos: [RepoConfig],
        quotaGB: Int?,
        excluding repoIDs: Set<UUID> = [],
        mirrorsDirectory: URL = Constants.mirrorsDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider,
        runGarbageCollection: (UUID) async throws -> Void = defaultGarbageCollection,
        deleteMirror: (UUID) throws -> Void = MirrorStore.deleteMirror(for:)
    ) async -> MirrorCacheCleanupResult {
        let initialUsage = currentUsageBytes(
            repos: repos,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )

        guard MirrorCacheManager.isOverQuota(usageBytes: initialUsage, quotaGB: quotaGB) else {
            return MirrorCacheCleanupResult(
                steps: [],
                initialUsageBytes: initialUsage,
                finalUsageBytes: initialUsage
            )
        }

        var usage = initialUsage
        var steps: [MirrorCacheEvictionStep] = []
        var entries = mirrorEntries(
            repos: repos,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        ).filter { !repoIDs.contains($0.repoID) }

        while MirrorCacheManager.isOverQuota(usageBytes: usage, quotaGB: quotaGB) {
            let ordered = MirrorCacheManager.lruSorted(entries.filter { $0.sizeBytes > 0 })
            guard let candidate = ordered.first else { break }

            let beforeGC = candidate.sizeBytes
            steps.append(.garbageCollect(repoID: candidate.repoID))

            if beforeGC > 0 {
                try? await runGarbageCollection(candidate.repoID)
            }

            let mirrorURL = mirrorsDirectory.appendingPathComponent(candidate.repoID.uuidString)
            let afterGC = sizeOf(mirrorURL)
            usage = usage - beforeGC + afterGC
            entries = updateEntrySize(entries, repoID: candidate.repoID, sizeBytes: afterGC)

            guard MirrorCacheManager.isOverQuota(usageBytes: usage, quotaGB: quotaGB) else { break }
            guard afterGC > 0 else { continue }

            steps.append(.deleteMirror(repoID: candidate.repoID))
            try? deleteMirror(candidate.repoID)
            usage -= afterGC
            entries = updateEntrySize(entries, repoID: candidate.repoID, sizeBytes: 0)
        }

        return MirrorCacheCleanupResult(
            steps: steps,
            initialUsageBytes: initialUsage,
            finalUsageBytes: max(0, usage)
        )
    }

    @MainActor
    static func freeMirrorSpace(
        for repoID: UUID,
        mirrorsDirectory: URL = Constants.mirrorsDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider,
        runGarbageCollection: (UUID) async throws -> Void = defaultGarbageCollection,
        deleteMirror: (UUID) throws -> Void = MirrorStore.deleteMirror(for:)
    ) async -> Int64 {
        let mirrorURL = mirrorsDirectory.appendingPathComponent(repoID.uuidString)
        let before = sizeOf(mirrorURL)
        guard before > 0 else { return 0 }

        try? await runGarbageCollection(repoID)
        try? deleteMirror(repoID)
        return before
    }

    @MainActor
    private static func defaultGarbageCollection(for repoID: UUID) async throws {
        let runner = GitRunner()
        let mirrorPath = MirrorStore.mirrorPath(for: repoID).path
        try await runner.gcAggressive(mirrorPath: mirrorPath)
    }

    private static func updateEntrySize(
        _ entries: [MirrorCacheEntry],
        repoID: UUID,
        sizeBytes: Int64
    ) -> [MirrorCacheEntry] {
        entries.map { entry in
            guard entry.repoID == repoID else { return entry }
            return MirrorCacheEntry(
                repoID: entry.repoID,
                lastAccessedAt: entry.lastAccessedAt,
                sizeBytes: sizeBytes
            )
        }
    }
}
