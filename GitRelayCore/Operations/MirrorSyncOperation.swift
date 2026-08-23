import Foundation
import Darwin

nonisolated enum MirrorOperationLeaseError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning(UUID)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Another process is already operating on this mirror."
        }
    }
}

/// A non-blocking mirror-scoped lease shared by the app, intents, webhooks,
/// and command-line processes. It prevents concurrent Git processes from
/// mutating the same bare repository.
nonisolated final class MirrorOperationLease: @unchecked Sendable {
    private let descriptor: Int32

    init(mirrorID: UUID) throws {
        let directory = Constants.mirrorPlansFile
            .deletingLastPathComponent()
            .appendingPathComponent("operation-locks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(mirrorID.uuidString).lock")
        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            throw MirrorOperationLeaseError.alreadyRunning(mirrorID)
        }
        self.descriptor = descriptor
    }

    func release() {
        _ = flock(descriptor, LOCK_UN)
    }

    deinit {
        release()
        Darwin.close(descriptor)
    }
}

nonisolated enum MirrorSyncOperationEvent: Sendable {
    case activityChanged(MirrorActivityState)
    case log(String)
    case persisted(MirrorRunRecord, MirrorHealthSnapshot)
}

nonisolated enum MirrorSyncOperationError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case driverFinishedWithoutRecord

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "This mirror operation is already running."
        case .driverFinishedWithoutRecord:
            "The mirror driver finished without a run record."
        }
    }
}

@MainActor
final class MirrorSyncOperation {
    typealias DriverFactory = @MainActor (MirrorPlan) -> any MirrorSyncDriving

    var onEvent: ((MirrorSyncOperationEvent) -> Void)?
    var confirmDestructivePush: (
        (DestructivePushPlan, MirrorDestination) async -> DestructivePushDecision
    )?
    var mirrorReleases: (
        (
            MirrorPlan,
            MirrorDestination,
            @escaping @Sendable (String) -> Void
        ) async throws -> Void
    )?

    private let plan: MirrorPlan
    private let stateStore: MirrorStateStore
    private let runStore: MirrorRunStore
    private let driverFactory: DriverFactory
    private var activeDriver: (any MirrorSyncDriving)?
    private var finalRecord: MirrorRunRecord?

    init(
        plan: MirrorPlan,
        stateStore: MirrorStateStore = MirrorStateStore(),
        runStore: MirrorRunStore = MirrorRunStore(),
        driverFactory: @escaping DriverFactory = { MirrorSyncDriver(plan: $0) }
    ) {
        self.plan = plan
        self.stateStore = stateStore
        self.runStore = runStore
        self.driverFactory = driverFactory
    }

    @discardableResult
    func run() async throws -> MirrorRunRecord {
        guard activeDriver == nil else {
            throw MirrorSyncOperationError.alreadyRunning
        }
        let validatedPlan = try plan.validated()
        let operationLease = try MirrorOperationLease(mirrorID: validatedPlan.id)
        defer { operationLease.release() }
        finalRecord = nil

        let driver = driverFactory(validatedPlan)
        activeDriver = driver
        driver.confirmDestructivePush = confirmDestructivePush
        driver.mirrorReleases = mirrorReleases
        driver.onEvent = { [weak self] event in
            self?.handle(event)
        }
        defer {
            activeDriver = nil
            onEvent?(.activityChanged(.idle))
        }

        await driver.run()
        guard let finalRecord else {
            throw MirrorSyncOperationError.driverFinishedWithoutRecord
        }

        // The run log is authoritative detail; the compact health index can be
        // rebuilt from it if the second write is interrupted.
        try runStore.append(finalRecord)
        let snapshot = try stateStore.update(mirrorID: validatedPlan.id) { previous in
            MirrorHealthReducer.applying(finalRecord, to: previous, plan: validatedPlan)
        }
        onEvent?(.persisted(finalRecord, snapshot))
        return finalRecord
    }

    func cancel() {
        activeDriver?.cancel()
    }

    private func handle(_ event: MirrorSyncDriverEvent) {
        switch event {
        case .started:
            onEvent?(.activityChanged(.synchronizing(phase: SyncPhase(.cloningSource), progress: nil)))
        case .phase(let phase):
            onEvent?(.activityChanged(.synchronizing(phase: phase, progress: nil)))
        case .log(let line):
            onEvent?(.log(SyncEngine.redactCredentials(line)))
        case .finished(let record):
            finalRecord = record
        }
    }
}
