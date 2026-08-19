import Foundation

nonisolated struct ReleaseAssetInfo: Equatable, Sendable, Codable {
    let name: String
    let downloadURL: URL
    let size: Int?
    let contentType: String?
}

nonisolated struct ReleaseInfo: Equatable, Sendable, Codable {
    let tagName: String
    let title: String
    let body: String
    let assets: [ReleaseAssetInfo]
}

nonisolated struct ReleaseMirrorPlan: Equatable, Sendable {
    let release: ReleaseInfo
    let missingAssetNames: [String]

    var needsCreate: Bool { missingAssetNames.count == release.assets.count }
}

nonisolated enum ReleaseTagSyncState: String, Codable, Sendable {
    case pending
    case syncing
    case synced
    case partial
    case failed
}

nonisolated struct ReleaseTagStatus: Equatable, Sendable, Codable {
    var tagName: String
    var state: ReleaseTagSyncState
    var completedAssetNames: [String]
    var totalAssets: Int
    var error: String?

    var completedCount: Int { completedAssetNames.count }
}

nonisolated struct ReleaseTargetMirrorStatus: Equatable, Sendable, Codable {
    var targetID: UUID
    var targetURL: String
    var lastSyncedAt: Date?
    var lastError: String?
    var tags: [ReleaseTagStatus]
    var isSyncing: Bool

    init(
        targetID: UUID,
        targetURL: String,
        lastSyncedAt: Date? = nil,
        lastError: String? = nil,
        tags: [ReleaseTagStatus] = [],
        isSyncing: Bool = false
    ) {
        self.targetID = targetID
        self.targetURL = targetURL
        self.lastSyncedAt = lastSyncedAt
        self.lastError = lastError
        self.tags = tags
        self.isSyncing = isSyncing
    }
}

nonisolated struct ReleaseMirrorResumeState: Codable, Equatable, Sendable {
    var completedAssetsByTag: [String: [String]]
    var lastUpdatedAt: Date

    init(completedAssetsByTag: [String: [String]] = [:], lastUpdatedAt: Date = .now) {
        self.completedAssetsByTag = completedAssetsByTag
        self.lastUpdatedAt = lastUpdatedAt
    }

    mutating func markAssetCompleted(tag: String, assetName: String) {
        var names = Set(completedAssetsByTag[tag] ?? [])
        names.insert(assetName)
        completedAssetsByTag[tag] = names.sorted()
        lastUpdatedAt = .now
    }

    func completedAssets(for tag: String) -> Set<String> {
        Set(completedAssetsByTag[tag] ?? [])
    }
}

enum ReleaseMirrorDiff {
    nonisolated static func plans(
        source: [ReleaseInfo],
        target: [ReleaseInfo],
        resume: ReleaseMirrorResumeState
    ) -> [ReleaseMirrorPlan] {
        let targetByTag = Dictionary(uniqueKeysWithValues: target.map { ($0.tagName, $0) })
        var plans: [ReleaseMirrorPlan] = []

        for release in source.sorted(by: { $0.tagName < $1.tagName }) {
            let completed = resume.completedAssets(for: release.tagName)
            let targetRelease = targetByTag[release.tagName]

            guard let targetRelease else {
                let missing = release.assets.map(\.name).filter { !completed.contains($0) }
                plans.append(ReleaseMirrorPlan(release: release, missingAssetNames: missing))
                continue
            }

            let targetAssetNames = Set(targetRelease.assets.map(\.name))

            let missing = release.assets.map(\.name).filter { name in
                !targetAssetNames.contains(name) && !completed.contains(name)
            }

            guard !missing.isEmpty else { continue }
            plans.append(ReleaseMirrorPlan(release: release, missingAssetNames: missing))
        }

        return plans
    }
}
