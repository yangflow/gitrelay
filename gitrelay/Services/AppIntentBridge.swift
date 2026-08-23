import Foundation

enum AppIntentBridgeError: LocalizedError, Equatable {
    case appNotReady
    case mirrorNotFound(String)

    var errorDescription: String? {
        switch self {
        case .appNotReady:
            return "GitRelay is not ready yet."
        case .mirrorNotFound(let name):
            return "No mirror named \"\(name)\" was found."
        }
    }
}

@MainActor
enum AppIntentBridge {
    private(set) static weak var library: MirrorLibraryModel?
    private(set) static weak var operations: MirrorOperationsController?
    private(set) static weak var management: MirrorManagementController?

    static func register(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        management: MirrorManagementController
    ) {
        self.library = library
        self.operations = operations
        self.management = management
    }

    static func triggerSync(mirrorName: String) throws {
        guard let library, let operations else { throw AppIntentBridgeError.appNotReady }
        let plan = try findMirror(mirrorName, in: library.plans)
        operations.triggerSync(mirrorID: plan.id)
    }

    static func triggerSync(mirrorID: UUID) throws {
        guard let library, let operations else { throw AppIntentBridgeError.appNotReady }
        guard library.mirror(id: mirrorID) != nil else {
            throw AppIntentBridgeError.mirrorNotFound(mirrorID.uuidString)
        }
        operations.triggerSync(mirrorID: mirrorID)
    }

    static func triggerSyncAll() throws {
        guard let operations else { throw AppIntentBridgeError.appNotReady }
        operations.triggerSyncAll()
    }

    static func mirrorStatusSnapshot(mirrorID: UUID) throws -> MirrorSurfaceSnapshot {
        if let snapshot = management?.surfaceSnapshot(mirrorID: mirrorID) {
            return snapshot
        }
        let plans = try loadPlans()
        guard let plan = plans.first(where: { $0.id == mirrorID }) else {
            throw AppIntentBridgeError.mirrorNotFound(mirrorID.uuidString)
        }
        let health = try loadHealth()
        return MirrorSurfaceSupport.snapshot(plan: plan, health: health[plan.id])
    }

    static func allMirrorStatusSnapshots() throws -> [MirrorSurfaceSnapshot] {
        if let library, let management {
            return library.mirrors.compactMap {
                management.surfaceSnapshot(mirrorID: $0.id)
            }
        }
        let plans = try loadPlans()
        let health = try loadHealth()
        return plans.map { MirrorSurfaceSupport.snapshot(plan: $0, health: health[$0.id]) }
    }

    private static func loadPlans() throws -> [MirrorPlan] {
        do {
            return try MirrorPlanStore().load()
        } catch {
            throw AppIntentBridgeError.appNotReady
        }
    }

    private static func loadHealth() throws -> [UUID: MirrorHealthSnapshot] {
        do {
            return try MirrorStateStore().load()
        } catch {
            throw AppIntentBridgeError.appNotReady
        }
    }

    private static func findMirror(_ query: String, in plans: [MirrorPlan]) throws -> MirrorPlan {
        do {
            return try MirrorSurfaceSupport.mirror(matching: query, in: plans)
        } catch {
            throw AppIntentBridgeError.mirrorNotFound(query)
        }
    }
}
