import AppIntents
import Foundation

struct RepoSyncStatusEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sync Status")

    static var defaultQuery = RepoSyncStatusEntityQuery()

    var id: String { repoName }

    @Property(title: "Repository")
    var repoName: String

    @Property(title: "Status")
    var status: RepoSyncStatusKindEntity

    @Property(title: "Last Synced At")
    var lastSyncedAt: Date?

    @Property(title: "Message")
    var message: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(repoName): \(status.rawValue)")
    }

    init(snapshot: RepoSyncStatusSnapshot) {
        repoName = snapshot.repoName
        status = RepoSyncStatusKindEntity(snapshot.status)
        lastSyncedAt = snapshot.lastSyncedAt
        message = snapshot.message
    }
}

enum RepoSyncStatusKindEntity: String, AppEnum {
    case success
    case failure
    case syncing
    case diverged
    case unknown

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sync Status Kind")

    static var caseDisplayRepresentations: [RepoSyncStatusKindEntity: DisplayRepresentation] = [
        .success: "Success",
        .failure: "Failure",
        .syncing: "Syncing",
        .diverged: "Diverged",
        .unknown: "Unknown",
    ]

    init(_ kind: RepoSyncStatusKind) {
        switch kind {
        case .success: self = .success
        case .failure: self = .failure
        case .syncing: self = .syncing
        case .diverged: self = .diverged
        case .unknown: self = .unknown
        }
    }
}

struct RepoSyncStatusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RepoSyncStatusEntity] {
        try await MainActor.run {
            try identifiers.compactMap { identifier in
                guard let snapshot = try? AppIntentBridge.syncStatusSnapshot(repoName: identifier) else {
                    return nil
                }
                return RepoSyncStatusEntity(snapshot: snapshot)
            }
        }
    }

    func suggestedEntities() async throws -> [RepoSyncStatusEntity] {
        try await MainActor.run {
            guard let viewModel = AppIntentBridge.viewModel else { return [] }
            return viewModel.repos.map { repo in
                RepoSyncStatusEntity(
                    snapshot: RepoIntentSupport.makeSnapshot(
                        repo: repo,
                        runtimeStatus: viewModel.statuses[repo.id],
                        isSyncInProgress: viewModel.inProgressSyncIDs.contains(repo.id)
                    )
                )
            }
        }
    }
}
