import Foundation

nonisolated struct MirrorCacheCleanupResult: Equatable, Sendable {
    let steps: [MirrorCacheEvictionStep]
    let initialUsageBytes: Int64
    let finalUsageBytes: Int64

    var bytesFreed: Int64 {
        max(0, initialUsageBytes - finalUsageBytes)
    }
}

nonisolated enum MirrorCacheService {
    static func currentUsageBytes(
        plans: [MirrorPlan],
        mirrorsDirectory: URL = Constants.mirrorCacheDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider
    ) -> Int64 {
        MirrorDirectorySizer.mirrorsUsage(
            plans: plans,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )
    }

    static func mirrorEntries(
        plans: [MirrorPlan],
        healthByMirrorID: [UUID: MirrorHealthSnapshot] = [:],
        mirrorsDirectory: URL = Constants.mirrorCacheDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider
    ) -> [MirrorCacheEntry] {
        MirrorDirectorySizer.mirrorEntries(
            plans: plans,
            healthByMirrorID: healthByMirrorID,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )
    }

    static func repoUsages(
        plans: [MirrorPlan],
        mirrorsDirectory: URL = Constants.mirrorCacheDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider
    ) -> [MirrorCacheRepoUsage] {
        MirrorDirectorySizer.repoUsages(
            plans: plans,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )
    }

    @MainActor
    static func performCleanup(
        plans: [MirrorPlan],
        healthByMirrorID: [UUID: MirrorHealthSnapshot] = [:],
        quotaGB: Int?,
        excluding repoIDs: Set<UUID> = [],
        mirrorsDirectory: URL = Constants.mirrorCacheDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider,
        runGarbageCollection: (UUID) async throws -> Void = defaultGarbageCollection,
        deleteMirror: (UUID) throws -> Void = MirrorStore.deleteMirror(for:)
    ) async -> MirrorCacheCleanupResult {
        let initialUsage = currentUsageBytes(
            plans: plans,
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
            plans: plans,
            healthByMirrorID: healthByMirrorID,
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
        mirrorsDirectory: URL = Constants.mirrorCacheDirectory,
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

    /// Deletes every local mirror folder (configured pairs and orphan UUID dirs).
    /// Skips `excluding` IDs (typically in-progress syncs). Rebuilds on the next sync.
    @MainActor
    static func evictAllMirrors(
        plans: [MirrorPlan],
        excluding repoIDs: Set<UUID> = [],
        mirrorsDirectory: URL = Constants.mirrorCacheDirectory,
        fileManager: FileManager = .default,
        sizeOf: (URL) -> Int64 = MirrorDirectorySizer.defaultSizeProvider,
        runGarbageCollection: (UUID) async throws -> Void = defaultGarbageCollection,
        deleteMirror: (UUID) throws -> Void = MirrorStore.deleteMirror(for:)
    ) async -> MirrorCacheCleanupResult {
        let initialUsage = currentUsageBytes(
            plans: plans,
            mirrorsDirectory: mirrorsDirectory,
            fileManager: fileManager,
            sizeOf: sizeOf
        )

        var steps: [MirrorCacheEvictionStep] = []
        var usage = initialUsage
        var seen = Set<UUID>()

        for plan in plans where !repoIDs.contains(plan.id) {
            seen.insert(plan.id)
            let freed = await freeMirrorSpace(
                for: plan.id,
                mirrorsDirectory: mirrorsDirectory,
                fileManager: fileManager,
                sizeOf: sizeOf,
                runGarbageCollection: runGarbageCollection,
                deleteMirror: deleteMirror
            )
            guard freed > 0 else { continue }
            steps.append(.garbageCollect(repoID: plan.id))
            steps.append(.deleteMirror(repoID: plan.id))
            usage -= freed
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: mirrorsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return MirrorCacheCleanupResult(
                steps: steps,
                initialUsageBytes: initialUsage,
                finalUsageBytes: max(0, usage)
            )
        }

        for entry in entries {
            guard let repoID = UUID(uuidString: entry.lastPathComponent),
                  !seen.contains(repoID),
                  !repoIDs.contains(repoID) else { continue }
            let before = sizeOf(entry)
            guard before > 0 else { continue }
            steps.append(.garbageCollect(repoID: repoID))
            try? await runGarbageCollection(repoID)
            steps.append(.deleteMirror(repoID: repoID))
            try? deleteMirror(repoID)
            if fileManager.fileExists(atPath: entry.path) {
                try? fileManager.removeItem(at: entry)
            }
            usage -= before
        }

        return MirrorCacheCleanupResult(
            steps: steps,
            initialUsageBytes: initialUsage,
            finalUsageBytes: max(0, usage)
        )
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
