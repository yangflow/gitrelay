import Foundation
import Testing
@testable import GitRelay

@Suite("GitRelay verification and scheduling")
@MainActor
struct MirrorVerificationSchedulingTests {
    @Test func successfulVerificationPersistsIntegrityWithoutChangingSyncHealth() async throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let lastSync = Date(timeIntervalSince1970: 1_800_100_000)
        let verifiedAt = lastSync.addingTimeInterval(300)
        let priorFailure = MirrorFailureSummary(
            kind: .network,
            message: "Previous sync failed",
            failedAt: lastSync
        )
        try fixture.stateStore.save([
            plan.id: MirrorHealthSnapshot(
                mirrorID: plan.id,
                lastAttemptAt: lastSync,
                lastSuccessfulAt: lastSync.addingTimeInterval(-60),
                lastFailure: priorFailure,
                consecutiveFailures: 2
            )
        ])
        let record = verificationRecord(
            plan: plan,
            finishedAt: verifiedAt,
            outcome: .succeeded,
            integrities: [.verified, .verified]
        )
        let driver = FakeMirrorVerificationDriver(events: [.started, .finished(record)])
        let operation = fixture.operation(plan: plan, driver: driver)

        let returned = try await operation.run()

        #expect(returned == record)
        let snapshot = try #require(fixture.stateStore.load()[plan.id])
        #expect(snapshot.lastVerifiedAt == verifiedAt)
        #expect(snapshot.integrity == .verified)
        #expect(snapshot.destinations.map(\.integrity) == [.verified, .verified])
        #expect(snapshot.destinations.allSatisfy { $0.lastVerifiedAt == verifiedAt })
        #expect(snapshot.lastAttemptAt == lastSync)
        #expect(snapshot.lastFailure == priorFailure)
        #expect(snapshot.consecutiveFailures == 2)
        #expect(try fixture.runStore.load(mirrorID: plan.id) == [record])
    }

    @Test func divergenceIsAttributedToOnlyTheAffectedDestination() async throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let verifiedAt = Date(timeIntervalSince1970: 1_800_100_100)
        let divergence = "main differs between source and backup"
        let record = verificationRecord(
            plan: plan,
            finishedAt: verifiedAt,
            outcome: .partiallySucceeded,
            integrities: [.verified, .diverged(divergence)]
        )
        let driver = FakeMirrorVerificationDriver(events: [.started, .finished(record)])

        _ = try await fixture.operation(plan: plan, driver: driver).run()

        let snapshot = try #require(fixture.stateStore.load()[plan.id])
        #expect(snapshot.integrity == .diverged(divergence))
        #expect(snapshot.destinations[0].integrity == .verified)
        #expect(snapshot.destinations[1].integrity == .diverged(divergence))
        #expect(snapshot.lastFailure == nil)
    }

    @Test func cancelledVerificationPreservesPreviousIntegrityAndReachesDriver() async throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let previousDate = Date(timeIntervalSince1970: 1_800_100_200)
        try fixture.stateStore.save([
            plan.id: MirrorHealthSnapshot(
                mirrorID: plan.id,
                lastVerifiedAt: previousDate,
                integrity: .verified
            )
        ])
        let cancelledAt = previousDate.addingTimeInterval(60)
        let cancelledRecord = MirrorRunRecord(
            mirrorID: plan.id,
            kind: .verification,
            startedAt: cancelledAt.addingTimeInterval(-5),
            finishedAt: cancelledAt,
            outcome: .cancelled,
            failure: MirrorFailureSummary(
                kind: .cancelled,
                message: "Cancelled",
                failedAt: cancelledAt
            )
        )
        let driver = FakeMirrorVerificationDriver(waitingForCancellationWith: cancelledRecord)
        let operation = fixture.operation(plan: plan, driver: driver)
        let task = Task { try await operation.run() }

        while !driver.isWaitingForCancellation {
            await Task.yield()
        }
        operation.cancel()
        let returned = try await task.value

        #expect(returned.outcome == .cancelled)
        #expect(driver.cancelCallCount == 1)
        let snapshot = try #require(fixture.stateStore.load()[plan.id])
        #expect(snapshot.lastVerifiedAt == previousDate)
        #expect(snapshot.integrity == .verified)
    }

    @Test func archiveOnlyDriverProducesARecordedInconclusiveFailure() async throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let plan = MirrorPlan(
            name: "Archive only",
            source: GitEndpoint(url: "git@github.com:acme/source.git"),
            destinations: [
                .archive(directoryPath: fixture.directory.appendingPathComponent("archive").path)
            ]
        )
        let driver = GitMirrorVerificationDriver(
            plan: plan,
            mirrorRootDirectory: fixture.directory.appendingPathComponent("mirrors"),
            scratchRootDirectory: fixture.directory.appendingPathComponent("verify-scratch")
        )
        var finished: MirrorRunRecord?
        driver.onEvent = { event in
            if case .finished(let record) = event {
                finished = record
            }
        }

        await driver.run()

        let record = try #require(finished)
        #expect(record.kind == .verification)
        #expect(record.outcome == .failed)
        #expect(record.verificationResults.isEmpty)
        #expect(record.failure?.message == "No enabled Git destinations are available for verification.")
    }

    @Test func gitVerificationDriverVerifiesMatchingLocalRepositories() async throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let work = fixture.directory.appendingPathComponent("work")
        let source = fixture.directory.appendingPathComponent("source.git")
        let destination = fixture.directory.appendingPathComponent("destination.git")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try runGit(["init", "--initial-branch=main", work.path])
        try runGit(["-C", work.path, "config", "user.email", "tests@gitrelay.local"])
        try runGit(["-C", work.path, "config", "user.name", "GitRelay Tests"])
        try Data("verified\n".utf8).write(to: work.appendingPathComponent("README.md"))
        try runGit(["-C", work.path, "add", "README.md"])
        try runGit(["-C", work.path, "commit", "-m", "initial"])
        try runGit(["clone", "--bare", work.path, source.path])
        try runGit(["clone", "--bare", work.path, destination.path])

        let plan = MirrorPlan(
            name: "Local verification",
            source: GitEndpoint(url: source.path),
            destinations: [.git(url: destination.path)],
            policy: MirrorPolicy(
                verification: MirrorVerificationPolicy(frequency: .manual, branch: "main")
            )
        )
        let driver = GitMirrorVerificationDriver(
            plan: plan,
            mirrorRootDirectory: fixture.directory.appendingPathComponent("mirrors"),
            scratchRootDirectory: fixture.directory.appendingPathComponent("verify-scratch")
        )
        var finished: MirrorRunRecord?
        driver.onEvent = { event in
            if case .finished(let record) = event {
                finished = record
            }
        }

        await driver.run()

        let record = try #require(finished)
        #expect(record.kind == .verification)
        #expect(record.outcome == .succeeded)
        #expect(record.failure == nil)
        #expect(record.verificationResults.count == 1)
        #expect(record.verificationResults[0].integrity == .verified)
    }

    @Test func verificationRunStoreRedactsCredentialsFromIntegrityResults() throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let secret = "super-secret-token"
        let unsafeURL = "https://\(secret)@example.com/acme/repo.git"
        let completedAt = Date(timeIntervalSince1970: 1_800_100_500)
        let record = MirrorRunRecord(
            mirrorID: plan.id,
            kind: .verification,
            startedAt: completedAt.addingTimeInterval(-1),
            finishedAt: completedAt,
            outcome: .failed,
            failure: MirrorFailureSummary(
                kind: .network,
                message: unsafeURL,
                failedAt: completedAt
            ),
            logLines: [unsafeURL],
            verificationResults: [
                MirrorDestinationVerificationResult(
                    destinationID: plan.destinations[0].id,
                    completedAt: completedAt,
                    integrity: .inconclusive(unsafeURL),
                    failure: MirrorFailureSummary(
                        kind: .network,
                        message: unsafeURL,
                        failedAt: completedAt,
                        destinationID: plan.destinations[0].id
                    )
                )
            ]
        )

        try fixture.runStore.append(record)

        let raw = try String(
            contentsOf: fixture.runStore.fileURL(for: plan.id),
            encoding: .utf8
        )
        #expect(!raw.contains(secret))
        let loaded = try #require(fixture.runStore.load(mirrorID: plan.id).first)
        guard case .inconclusive(let message) = loaded.verificationResults[0].integrity else {
            Issue.record("Expected an inconclusive verification result")
            return
        }
        #expect(!message.contains(secret))
    }

    @Test func verificationDriverMustProduceFinalRecord() async throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        let plan = fixture.plan()
        let driver = FakeMirrorVerificationDriver(events: [.started])
        let operation = fixture.operation(plan: plan, driver: driver)

        await #expect(throws: MirrorVerificationOperationError.driverFinishedWithoutRecord) {
            try await operation.run()
        }
        #expect(try fixture.stateStore.load().isEmpty)
        #expect(try fixture.runStore.load(mirrorID: plan.id).isEmpty)
    }

    @Test func syncAndVerificationSchedulesUseIndependentHealthAnchors() throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        var plan = fixture.plan()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        plan.createdAt = createdAt
        plan.policy.frequency = .hour1
        plan.policy.verification.frequency = .day1
        let snapshot = MirrorHealthSnapshot(
            mirrorID: plan.id,
            lastAttemptAt: createdAt.addingTimeInterval(7_200),
            lastVerifiedAt: createdAt
        )
        let now = createdAt.addingTimeInterval(10_800)

        let evaluation = MirrorSchedulePlanner.evaluate(
            plan: plan,
            snapshot: snapshot,
            environment: MirrorSchedulingEnvironment(),
            now: now
        )

        #expect(evaluation.sync == .due(scheduledAt: now, missedRunCount: 1))
        #expect(
            evaluation.verification
                == .scheduled(nextRunAt: createdAt.addingTimeInterval(86_400))
        )
    }

    @Test func schedulingExplainsMirrorGlobalAndEnvironmentalPauses() throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        var plan = fixture.plan()
        plan.policy.frequency = .hour1
        let now = plan.createdAt.addingTimeInterval(7_200)
        let dueAt = plan.createdAt.addingTimeInterval(3_600)

        plan.isSchedulePaused = true
        #expect(
            MirrorSchedulePlanner.evaluate(
                operation: .sync,
                plan: plan,
                snapshot: nil,
                environment: MirrorSchedulingEnvironment(globalPauseReason: .manual),
                now: now
            ) == .mirrorPaused(nextRunAt: dueAt)
        )

        plan.isSchedulePaused = false
        #expect(
            MirrorSchedulePlanner.evaluate(
                operation: .sync,
                plan: plan,
                snapshot: nil,
                environment: MirrorSchedulingEnvironment(globalPauseReason: .manual),
                now: now
            ) == .globallyPaused(.manual, nextRunAt: dueAt)
        )

        #expect(
            MirrorSchedulePlanner.evaluate(
                operation: .sync,
                plan: plan,
                snapshot: nil,
                environment: MirrorSchedulingEnvironment(
                    pauseOnLowPower: true,
                    isLowPowerMode: true,
                    pauseOnExpensiveNetwork: true,
                    isExpensiveNetwork: true
                ),
                now: now
            ) == .deferred(.lowPowerAndExpensiveNetwork, nextRunAt: dueAt)
        )
    }

    @Test func longOverdueScheduleCapsMissedRunCount() throws {
        let fixture = try TemporaryMirrorVerificationFixture()
        defer { fixture.remove() }
        var plan = fixture.plan()
        plan.policy.frequency = .min15
        let now = plan.createdAt.addingTimeInterval(900 * 500)

        let evaluation = MirrorSchedulePlanner.evaluate(
            operation: .sync,
            plan: plan,
            snapshot: nil,
            environment: MirrorSchedulingEnvironment(),
            now: now
        )

        guard case .due(_, let missedRunCount) = evaluation else {
            Issue.record("Expected the schedule to be due")
            return
        }
        #expect(missedRunCount == MirrorSchedulePlanner.maximumMissedRuns)
        #expect(evaluation.shouldStartNow)
    }

    private func verificationRecord(
        plan: MirrorPlan,
        finishedAt: Date,
        outcome: MirrorRunOutcome,
        integrities: [MirrorIntegrityState]
    ) -> MirrorRunRecord {
        MirrorRunRecord(
            mirrorID: plan.id,
            kind: .verification,
            startedAt: finishedAt.addingTimeInterval(-10),
            finishedAt: finishedAt,
            outcome: outcome,
            verificationResults: zip(plan.destinations, integrities).map { destination, integrity in
                MirrorDestinationVerificationResult(
                    destinationID: destination.id,
                    completedAt: finishedAt,
                    integrity: integrity,
                    failure: nil
                )
            }
        )
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "git failed"
            throw LocalGitTestError.commandFailed(message)
        }
    }
}

private enum LocalGitTestError: Error {
    case commandFailed(String)
}

@MainActor
private final class FakeMirrorVerificationDriver: MirrorVerificationDriving {
    var onEvent: ((MirrorVerificationDriverEvent) -> Void)?

    private let events: [MirrorVerificationDriverEvent]
    private let cancellationRecord: MirrorRunRecord?
    private var cancellationContinuation: CheckedContinuation<Void, Never>?
    private(set) var cancelCallCount = 0
    private(set) var isWaitingForCancellation = false

    init(events: [MirrorVerificationDriverEvent]) {
        self.events = events
        self.cancellationRecord = nil
    }

    init(waitingForCancellationWith record: MirrorRunRecord) {
        self.events = []
        self.cancellationRecord = record
    }

    func run() async {
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

private struct TemporaryMirrorVerificationFixture {
    let directory: URL
    let stateStore: MirrorStateStore
    let runStore: MirrorRunStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-verification-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateStore = MirrorStateStore(
            fileURL: directory.appendingPathComponent("mirror-state.json")
        )
        runStore = MirrorRunStore(directoryURL: directory.appendingPathComponent("logs"))
    }

    func plan() -> MirrorPlan {
        MirrorPlan(
            name: "Verification plan",
            source: GitEndpoint(url: "git@github.com:acme/source.git"),
            destinations: [
                .git(url: "git@gitlab.com:acme/backup.git"),
                .git(url: "git@gitea.example:acme/backup.git")
            ]
        )
    }

    @MainActor
    func operation(
        plan: MirrorPlan,
        driver: FakeMirrorVerificationDriver
    ) -> MirrorVerificationOperation {
        MirrorVerificationOperation(
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
