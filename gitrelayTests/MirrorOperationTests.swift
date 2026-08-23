import Foundation
import Testing
@testable import GitRelay

@Suite("GitRelay mirror operation")
@MainActor
struct MirrorOperationTests {
    @Test func successfulMultiDestinationRunPersistsRunAndPerDestinationHealth() async throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let completedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let record = MirrorRunRecord(
            mirrorID: plan.id,
            startedAt: completedAt.addingTimeInterval(-10),
            finishedAt: completedAt,
            outcome: .succeeded,
            logLines: ["All destinations synchronized"],
            destinationResults: plan.destinations.map {
                MirrorDestinationRunResult(
                    destinationID: $0.id,
                    succeeded: true,
                    completedAt: completedAt,
                    failure: nil
                )
            }
        )
        let driver = FakeMirrorSyncDriver(events: [
            .started,
            .phase(SyncPhase(.fetchingSource)),
            .finished(record)
        ])
        let operation = fixture.operation(plan: plan, driver: driver)

        let returned = try await operation.run()

        #expect(returned == record)
        let runs = try fixture.runStore.load(mirrorID: plan.id)
        #expect(runs == [record])
        let snapshot = try #require(fixture.stateStore.load()[plan.id])
        #expect(snapshot.lastAttemptAt == completedAt)
        #expect(snapshot.lastSuccessfulAt == completedAt)
        #expect(snapshot.lastFailure == nil)
        #expect(snapshot.consecutiveFailures == 0)
        #expect(snapshot.destinations.count == 2)
        #expect(snapshot.destinations.allSatisfy { $0.lastSuccessfulAt == completedAt })
    }

    @Test func partialFailurePreservesSuccessfulDestinationAndMarksOnlyFailedDestination() async throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let completedAt = Date(timeIntervalSince1970: 1_800_000_200)
        let failedDestination = plan.destinations[1]
        let destinationFailure = MirrorFailureSummary(
            kind: .destinationAuthentication,
            message: "Authentication failed — check credentials",
            failedAt: completedAt,
            destinationID: failedDestination.id
        )
        let overallFailure = MirrorFailureSummary(
            kind: .destinationAuthentication,
            message: "1/2 destinations failed",
            failedAt: completedAt
        )
        let record = MirrorRunRecord(
            mirrorID: plan.id,
            startedAt: completedAt.addingTimeInterval(-10),
            finishedAt: completedAt,
            outcome: .partiallySucceeded,
            failure: overallFailure,
            destinationResults: [
                MirrorDestinationRunResult(
                    destinationID: plan.destinations[0].id,
                    succeeded: true,
                    completedAt: completedAt,
                    failure: nil
                ),
                MirrorDestinationRunResult(
                    destinationID: failedDestination.id,
                    succeeded: false,
                    completedAt: completedAt,
                    failure: destinationFailure
                )
            ]
        )
        try fixture.stateStore.save([
            plan.id: MirrorHealthSnapshot(mirrorID: plan.id, consecutiveFailures: 1)
        ])
        let driver = FakeMirrorSyncDriver(events: [.started, .finished(record)])

        _ = try await fixture.operation(plan: plan, driver: driver).run()

        let snapshot = try #require(fixture.stateStore.load()[plan.id])
        #expect(snapshot.lastSuccessfulAt == nil)
        #expect(snapshot.lastFailure == overallFailure)
        #expect(snapshot.consecutiveFailures == 2)
        #expect(snapshot.destinations[0].lastSuccessfulAt == completedAt)
        #expect(snapshot.destinations[0].lastFailure == nil)
        #expect(snapshot.destinations[1].lastSuccessfulAt == nil)
        #expect(snapshot.destinations[1].lastFailure == destinationFailure)
        #expect(MirrorHealth.derive(plan: plan, snapshot: snapshot) == .failed(overallFailure))
    }

    @Test func sourceFailureUpdatesMirrorWithoutInventingDestinationAttempts() async throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let failedAt = Date(timeIntervalSince1970: 1_800_000_300)
        let failure = MirrorFailureSummary(
            kind: .sourceAuthentication,
            message: "Authentication failed — check credentials",
            failedAt: failedAt
        )
        let record = MirrorRunRecord(
            mirrorID: plan.id,
            startedAt: failedAt.addingTimeInterval(-2),
            finishedAt: failedAt,
            outcome: .failed,
            failure: failure
        )
        let driver = FakeMirrorSyncDriver(events: [.started, .finished(record)])

        _ = try await fixture.operation(plan: plan, driver: driver).run()

        let snapshot = try #require(fixture.stateStore.load()[plan.id])
        #expect(snapshot.lastAttemptAt == failedAt)
        #expect(snapshot.lastFailure == failure)
        #expect(snapshot.destinations.isEmpty)
    }

    @Test func cancellationReachesDriverAndPersistsCancelledRun() async throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let failedAt = Date(timeIntervalSince1970: 1_800_000_400)
        let failure = MirrorFailureSummary(
            kind: .cancelled,
            message: "Cancelled",
            failedAt: failedAt
        )
        let record = MirrorRunRecord(
            mirrorID: plan.id,
            startedAt: failedAt.addingTimeInterval(-3),
            finishedAt: failedAt,
            outcome: .cancelled,
            failure: failure
        )
        let driver = FakeMirrorSyncDriver(waitingForCancellationWith: record)
        let operation = fixture.operation(plan: plan, driver: driver)
        let task = Task { try await operation.run() }

        while !driver.isWaitingForCancellation {
            await Task.yield()
        }
        operation.cancel()
        let returned = try await task.value

        #expect(driver.cancelCallCount == 1)
        #expect(returned.outcome == .cancelled)
        #expect(try fixture.runStore.load(mirrorID: plan.id).first?.outcome == .cancelled)
        #expect(try fixture.stateStore.load()[plan.id]?.lastFailure?.kind == .cancelled)
    }

    @Test func operationRejectsInvalidPlanBeforeStartingDriver() async {
        let fixture: TemporaryMirrorOperationFixture
        do {
            fixture = try TemporaryMirrorOperationFixture()
        } catch {
            Issue.record("Failed to create fixture: \(error)")
            return
        }
        defer { fixture.remove() }
        let invalidPlan = MirrorPlan(
            name: "Invalid",
            source: GitEndpoint(url: "git@github.com:acme/source.git"),
            destinations: []
        )
        let driver = FakeMirrorSyncDriver(events: [])
        let operation = fixture.operation(plan: invalidPlan, driver: driver)

        await #expect(throws: MirrorDomainError.noDestinations) {
            try await operation.run()
        }
        #expect(driver.runCallCount == 0)
    }

    @Test func driverMustProduceOneFinalRecord() async throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let driver = FakeMirrorSyncDriver(events: [.started])
        let operation = fixture.operation(plan: plan, driver: driver)

        await #expect(throws: MirrorSyncOperationError.driverFinishedWithoutRecord) {
            try await operation.run()
        }
        #expect(try fixture.runStore.load(mirrorID: plan.id).isEmpty)
        #expect(try fixture.stateStore.load().isEmpty)
    }

    @Test func mirrorCacheSupportsAnExplicitRootDirectory() throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let mirrorID = UUID()
        let root = fixture.directory.appendingPathComponent("custom-mirrors")
        let mirror = MirrorStore.mirrorPath(for: mirrorID, rootDirectory: root)
        try FileManager.default.createDirectory(at: mirror, withIntermediateDirectories: true)
        try Data("ref: refs/heads/main\n".utf8).write(to: mirror.appendingPathComponent("HEAD"))

        #expect(MirrorStore.mirrorExists(for: mirrorID, rootDirectory: root))
        #expect(MirrorStore.mirrorPath(for: mirrorID, rootDirectory: root) != MirrorStore.mirrorPath(for: mirrorID))
    }

    @Test func nativeDriverKeepsDestinationFailureSemanticsForPartialRuns() throws {
        let fixture = try TemporaryMirrorOperationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let finishedAt = Date(timeIntervalSince1970: 1_800_000_500)
        var syncRecord = SyncRecord(
            repoID: plan.id,
            startedAt: finishedAt.addingTimeInterval(-5),
            finishedAt: finishedAt
        )
        syncRecord.targetResults = [
            TargetSyncResult(
                targetID: plan.destinations[0].id,
                targetURL: "git@gitlab.com:acme/backup.git",
                succeeded: true
            ),
            TargetSyncResult(
                targetID: plan.destinations[1].id,
                targetURL: fixture.directory.path,
                succeeded: false,
                error: "Authentication failed — check credentials"
            )
        ]

        let mapped = MirrorSyncDriver.makeRunRecord(
            from: syncRecord,
            failureMessage: "1/2 targets failed (1 succeeded)"
        )

        #expect(mapped.outcome == .partiallySucceeded)
        #expect(mapped.destinationResults.count == 2)
        #expect(mapped.failure?.kind == .destinationAuthentication)
        #expect(mapped.failure?.destinationID == plan.destinations[1].id)
        #expect(mapped.destinationResults[1].failure?.kind == .destinationAuthentication)
    }
}

@MainActor
private final class FakeMirrorSyncDriver: MirrorSyncDriving {
    var onEvent: ((MirrorSyncDriverEvent) -> Void)?
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

    private let events: [MirrorSyncDriverEvent]
    private let cancellationRecord: MirrorRunRecord?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private(set) var runCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var isWaitingForCancellation = false

    init(events: [MirrorSyncDriverEvent]) {
        self.events = events
        self.cancellationRecord = nil
    }

    init(waitingForCancellationWith record: MirrorRunRecord) {
        self.events = []
        self.cancellationRecord = record
    }

    func run() async {
        runCallCount += 1
        if cancellationRecord != nil {
            onEvent?(.started)
            isWaitingForCancellation = true
            await withCheckedContinuation { continuation in
                cancellationContinuation = continuation
            }
            return
        }
        events.forEach { onEvent?($0) }
    }

    func cancel() {
        cancelCallCount += 1
        if let cancellationRecord {
            onEvent?(.finished(cancellationRecord))
        }
        cancellationContinuation?.resume()
        cancellationContinuation = nil
        isWaitingForCancellation = false
    }
}

private struct TemporaryMirrorOperationFixture {
    let directory: URL
    let stateStore: MirrorStateStore
    let runStore: MirrorRunStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-operation-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = MirrorStateStore(
            fileURL: directory.appendingPathComponent("mirror-state.json")
        )
        runStore = MirrorRunStore(directoryURL: directory.appendingPathComponent("logs"))
    }

    func plan() -> MirrorPlan {
        MirrorPlan(
            name: "Production backup",
            source: GitEndpoint(url: "git@github.com:acme/source.git"),
            destinations: [
                .git(url: "git@gitlab.com:acme/backup.git"),
                .archive(directoryPath: directory.appendingPathComponent("archives").path)
            ],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    @MainActor
    func operation(plan: MirrorPlan, driver: FakeMirrorSyncDriver) -> MirrorSyncOperation {
        MirrorSyncOperation(
            plan: plan,
            stateStore: stateStore,
            runStore: runStore,
            driverFactory: { _ in driver }
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
