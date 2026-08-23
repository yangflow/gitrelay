import Foundation

nonisolated enum MirrorVerificationOperationEvent: Sendable {
    case activityChanged(MirrorActivityState)
    case log(String)
    case persisted(MirrorRunRecord, MirrorHealthSnapshot)
}

nonisolated enum MirrorVerificationOperationError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case driverFinishedWithoutRecord

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "This mirror verification is already running."
        case .driverFinishedWithoutRecord:
            "The verification driver finished without a run record."
        }
    }
}

@MainActor
final class MirrorVerificationOperation {
    typealias DriverFactory = @MainActor (MirrorPlan) -> any MirrorVerificationDriving

    var onEvent: ((MirrorVerificationOperationEvent) -> Void)?

    private let plan: MirrorPlan
    private let stateStore: MirrorStateStore
    private let runStore: MirrorRunStore
    private let driverFactory: DriverFactory
    private var activeDriver: (any MirrorVerificationDriving)?
    private var finalRecord: MirrorRunRecord?

    init(
        plan: MirrorPlan,
        stateStore: MirrorStateStore = MirrorStateStore(),
        runStore: MirrorRunStore = MirrorRunStore(),
        driverFactory: @escaping DriverFactory = { GitMirrorVerificationDriver(plan: $0) }
    ) {
        self.plan = plan
        self.stateStore = stateStore
        self.runStore = runStore
        self.driverFactory = driverFactory
    }

    @discardableResult
    func run() async throws -> MirrorRunRecord {
        guard activeDriver == nil else {
            throw MirrorVerificationOperationError.alreadyRunning
        }
        let validatedPlan = try plan.validated()
        let operationLease = try MirrorOperationLease(mirrorID: validatedPlan.id)
        defer { operationLease.release() }
        finalRecord = nil

        let driver = driverFactory(validatedPlan)
        activeDriver = driver
        driver.onEvent = { [weak self] event in
            self?.handle(event)
        }
        defer {
            activeDriver = nil
            onEvent?(.activityChanged(.idle))
        }

        await driver.run()
        guard let finalRecord else {
            throw MirrorVerificationOperationError.driverFinishedWithoutRecord
        }

        try runStore.append(finalRecord)
        let snapshot = try stateStore.update(mirrorID: validatedPlan.id) { previous in
            MirrorVerificationHealthReducer.applying(finalRecord, to: previous, plan: validatedPlan)
        }
        onEvent?(.persisted(finalRecord, snapshot))
        return finalRecord
    }

    func cancel() {
        activeDriver?.cancel()
    }

    private func handle(_ event: MirrorVerificationDriverEvent) {
        switch event {
        case .started:
            onEvent?(.activityChanged(.verifying(progress: nil)))
        case .log(let line):
            onEvent?(.log(SyncEngine.redactCredentials(line)))
        case .finished(let record):
            finalRecord = record
        }
    }
}
