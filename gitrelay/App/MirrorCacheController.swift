import Foundation
import Observation

@MainActor
@Observable
final class MirrorCacheController {
    let preferences: CachePreferencesStore
    private let library: MirrorLibraryModel
    private let operations: MirrorOperationsController
    private let issues: AppIssueModel
    private let garbageCollection: (UUID) async throws -> Void
    private let mirrorDeletion: (UUID) throws -> Void

    private(set) var usageBytes: Int64 = 0
    private(set) var mirrorUsages: [MirrorCacheRepoUsage] = []
    private(set) var isCleaning = false

    init(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        preferences: CachePreferencesStore,
        issues: AppIssueModel,
        garbageCollection: @escaping (UUID) async throws -> Void = { mirrorID in
            let runner = GitRunner()
            let path = MirrorStore.mirrorPath(
                for: mirrorID,
                rootDirectory: Constants.mirrorCacheDirectory
            ).path
            try await runner.gcAggressive(mirrorPath: path)
        },
        mirrorDeletion: @escaping (UUID) throws -> Void = { mirrorID in
            try MirrorStore.deleteMirror(
                for: mirrorID,
                rootDirectory: Constants.mirrorCacheDirectory
            )
        }
    ) {
        self.library = library
        self.operations = operations
        self.preferences = preferences
        self.issues = issues
        self.garbageCollection = garbageCollection
        self.mirrorDeletion = mirrorDeletion
        do {
            try MirrorStore.ensureBaseDirectoryExists(at: Constants.mirrorCacheDirectory)
        } catch {
            issues.report(error.localizedDescription)
        }
        refreshUsage()
    }

    func refreshUsage() {
        usageBytes = MirrorCacheService.currentUsageBytes(
            plans: library.plans,
            mirrorsDirectory: Constants.mirrorCacheDirectory
        )
        mirrorUsages = MirrorCacheService.repoUsages(
            plans: library.plans,
            mirrorsDirectory: Constants.mirrorCacheDirectory
        )
    }

    func cleanAll() async {
        guard !isCleaning else { return }
        isCleaning = true
        defer {
            isCleaning = false
            refreshUsage()
        }
        _ = await MirrorCacheService.evictAllMirrors(
            plans: library.plans,
            excluding: operations.inProgressSyncIDs,
            mirrorsDirectory: Constants.mirrorCacheDirectory,
            runGarbageCollection: garbageCollection,
            deleteMirror: mirrorDeletion
        )
    }

    func clean(mirrorID: UUID) async {
        guard !isCleaning, !operations.inProgressSyncIDs.contains(mirrorID) else { return }
        isCleaning = true
        defer {
            isCleaning = false
            refreshUsage()
        }
        _ = await MirrorCacheService.freeMirrorSpace(
            for: mirrorID,
            mirrorsDirectory: Constants.mirrorCacheDirectory,
            runGarbageCollection: garbageCollection,
            deleteMirror: mirrorDeletion
        )
    }

    func enforceQuota(excluding mirrorIDs: Set<UUID> = []) async {
        refreshUsage()
        guard MirrorCacheManager.isOverQuota(
            usageBytes: usageBytes,
            quotaGB: preferences.preferences.cacheQuotaGB
        ) else { return }

        _ = await MirrorCacheService.performCleanup(
            plans: library.plans,
            healthByMirrorID: library.healthSnapshots,
            quotaGB: preferences.preferences.cacheQuotaGB,
            excluding: operations.inProgressSyncIDs.union(mirrorIDs),
            mirrorsDirectory: Constants.mirrorCacheDirectory,
            runGarbageCollection: garbageCollection,
            deleteMirror: mirrorDeletion
        )
        refreshUsage()
    }

    func removeArtifacts(mirrorID: UUID) {
        try? mirrorDeletion(mirrorID)
        let scratch = Constants.verificationScratchDirectory
            .appendingPathComponent(mirrorID.uuidString)
        try? FileManager.default.removeItem(at: scratch)
        refreshUsage()
    }
}
