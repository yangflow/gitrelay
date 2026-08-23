import Foundation

nonisolated enum MirrorHeadlessSyncError: Error, Equatable, LocalizedError, Sendable {
    case mirrorNotFound(String)
    case ambiguousMirrorName(String)
    case loadFailed(String)
    case missingCredentials(String)
    case alreadyRunning(String)
    case operationFinishedWithoutSuccess(String)

    var errorDescription: String? {
        switch self {
        case .mirrorNotFound(let query):
            "No mirror matching \"\(query)\" was found."
        case .ambiguousMirrorName(let name):
            "More than one mirror is named \"\(name)\". Use its identifier instead."
        case .loadFailed(let message):
            "Failed to load mirrors: \(SyncEngine.redactCredentials(message))"
        case .missingCredentials(let name):
            "Mirror \"\(name)\" needs credentials before it can sync."
        case .alreadyRunning(let name):
            "Mirror \"\(name)\" is already running."
        case .operationFinishedWithoutSuccess(let name):
            "Mirror \"\(name)\" did not complete successfully."
        }
    }
}

@MainActor
enum MirrorHeadlessSyncRunner {
    typealias OperationFactory = @MainActor (
        MirrorPlan,
        MirrorStateStore,
        MirrorRunStore
    ) -> MirrorSyncOperation

    static func loadPlans(store: MirrorPlanStore = MirrorPlanStore()) throws -> [MirrorPlan] {
        do {
            return try store.load()
        } catch {
            throw MirrorHeadlessSyncError.loadFailed(error.localizedDescription)
        }
    }

    static func loadHealth(
        store: MirrorStateStore = MirrorStateStore()
    ) throws -> [UUID: MirrorHealthSnapshot] {
        do {
            return try store.load()
        } catch {
            throw MirrorHeadlessSyncError.loadFailed(error.localizedDescription)
        }
    }

    @discardableResult
    static func sync(
        query: String,
        planStore: MirrorPlanStore = MirrorPlanStore(),
        stateStore: MirrorStateStore = MirrorStateStore(),
        runStore: MirrorRunStore = MirrorRunStore(),
        operationFactory: @escaping OperationFactory = { plan, stateStore, runStore in
            MirrorSyncOperation(plan: plan, stateStore: stateStore, runStore: runStore)
        }
    ) async throws -> MirrorRunRecord {
        let plans = try loadPlans(store: planStore)
        let plan: MirrorPlan
        do {
            plan = try MirrorSurfaceSupport.mirror(matching: query, in: plans)
        } catch MirrorSurfaceLookupError.notFound {
            throw MirrorHeadlessSyncError.mirrorNotFound(query)
        } catch MirrorSurfaceLookupError.ambiguousName {
            throw MirrorHeadlessSyncError.ambiguousMirrorName(query)
        } catch {
            throw MirrorHeadlessSyncError.mirrorNotFound(query)
        }
        return try await sync(
            plan: plan,
            stateStore: stateStore,
            runStore: runStore,
            operationFactory: operationFactory
        )
    }

    @discardableResult
    static func sync(
        mirrorID: UUID,
        planStore: MirrorPlanStore = MirrorPlanStore(),
        stateStore: MirrorStateStore = MirrorStateStore(),
        runStore: MirrorRunStore = MirrorRunStore(),
        operationFactory: @escaping OperationFactory = { plan, stateStore, runStore in
            MirrorSyncOperation(plan: plan, stateStore: stateStore, runStore: runStore)
        }
    ) async throws -> MirrorRunRecord {
        try await sync(
            query: mirrorID.uuidString,
            planStore: planStore,
            stateStore: stateStore,
            runStore: runStore,
            operationFactory: operationFactory
        )
    }

    static func syncAll(
        planStore: MirrorPlanStore = MirrorPlanStore(),
        stateStore: MirrorStateStore = MirrorStateStore(),
        runStore: MirrorRunStore = MirrorRunStore(),
        operationFactory: @escaping OperationFactory = { plan, stateStore, runStore in
            MirrorSyncOperation(plan: plan, stateStore: stateStore, runStore: runStore)
        }
    ) async throws -> [MirrorRunRecord] {
        let plans = try loadPlans(store: planStore)
        var records: [MirrorRunRecord] = []
        records.reserveCapacity(plans.count)
        for plan in plans {
            let record = try await execute(
                plan: plan,
                stateStore: stateStore,
                runStore: runStore,
                operationFactory: operationFactory
            )
            records.append(record)
        }
        return records
    }

    static func logLines(
        mirrorID: UUID,
        tail: Int?,
        runStore: MirrorRunStore = MirrorRunStore()
    ) throws -> [String] {
        let lines = try runStore.load(mirrorID: mirrorID)
            .sorted { $0.startedAt < $1.startedAt }
            .flatMap(\.logLines)
            .map(SyncEngine.redactCredentials)
        guard let tail else { return lines }
        return Array(lines.suffix(max(0, tail)))
    }

    private static func sync(
        plan: MirrorPlan,
        stateStore: MirrorStateStore,
        runStore: MirrorRunStore,
        operationFactory: @escaping OperationFactory
    ) async throws -> MirrorRunRecord {
        let record = try await execute(
            plan: plan,
            stateStore: stateStore,
            runStore: runStore,
            operationFactory: operationFactory
        )
        guard record.outcome == .succeeded else {
            throw MirrorHeadlessSyncError.operationFinishedWithoutSuccess(plan.name)
        }
        return record
    }

    private static func execute(
        plan: MirrorPlan,
        stateStore: MirrorStateStore,
        runStore: MirrorRunStore,
        operationFactory: @escaping OperationFactory
    ) async throws -> MirrorRunRecord {
        guard !MirrorCredentialGate.needsCredentials(for: plan) else {
            throw MirrorHeadlessSyncError.missingCredentials(plan.name)
        }
        let operation = operationFactory(plan, stateStore, runStore)
        let record: MirrorRunRecord
        do {
            record = try await operation.run()
        } catch is MirrorOperationLeaseError {
            throw MirrorHeadlessSyncError.alreadyRunning(plan.name)
        }
        return record
    }
}
