import AppIntents
import Foundation

struct MirrorStatusEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sync Status")

    static var defaultQuery = MirrorStatusEntityQuery()

    var id: String { mirrorID }

    @Property(title: "Mirror ID")
    var mirrorID: String

    @Property(title: "Mirror")
    var mirrorName: String

    @Property(title: "Status")
    var status: MirrorStatusKindEntity

    @Property(title: "Last Synced At")
    var lastSyncedAt: Date?

    @Property(title: "Message")
    var message: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(mirrorName): \(status.rawValue)")
    }

    init(snapshot: MirrorSurfaceSnapshot) {
        mirrorID = snapshot.mirrorID.uuidString.lowercased()
        mirrorName = snapshot.mirrorName
        status = MirrorStatusKindEntity(snapshot.status)
        lastSyncedAt = snapshot.lastSuccessfulAt
        message = snapshot.message
    }

    var mirrorUUID: UUID? { UUID(uuidString: mirrorID) }
}

enum MirrorStatusKindEntity: String, AppEnum {
    case success
    case failure
    case syncing
    case queued
    case diverged
    case unknown

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sync Status Kind")

    static var caseDisplayRepresentations: [MirrorStatusKindEntity: DisplayRepresentation] = [
        .success: "Success",
        .failure: "Failure",
        .syncing: "Syncing",
        .queued: "Queued",
        .diverged: "Diverged",
        .unknown: "Unknown",
    ]

    init(_ status: MirrorSurfaceStatus) {
        switch status {
        case .healthy: self = .success
        case .failed: self = .failure
        case .syncing, .verifying: self = .syncing
        case .queued: self = .queued
        case .diverged: self = .diverged
        case .needsSetup, .notRun, .stale, .paused: self = .unknown
        }
    }
}

struct MirrorStatusEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [MirrorStatusEntity] {
        await MainActor.run {
            identifiers.compactMap { identifier in
                guard let mirrorID = UUID(uuidString: identifier),
                      let snapshot = try? AppIntentBridge.mirrorStatusSnapshot(mirrorID: mirrorID) else {
                    return nil
                }
                return MirrorStatusEntity(snapshot: snapshot)
            }
        }
    }

    func suggestedEntities() async throws -> [MirrorStatusEntity] {
        await MainActor.run {
            let snapshots = (try? AppIntentBridge.allMirrorStatusSnapshots()) ?? []
            return snapshots.map(MirrorStatusEntity.init(snapshot:))
        }
    }
}
