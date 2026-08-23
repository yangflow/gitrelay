import Foundation
import Testing
@testable import GitRelay

@Suite("GitRelay secondary surfaces")
struct MirrorSecondarySurfaceTests {
    @Test func lookupUsesStableIdentifierAndRejectsAmbiguousNames() throws {
        let first = makePlan(name: "Backup")
        let second = makePlan(name: "backup")

        #expect(try MirrorSurfaceSupport.mirror(
            matching: first.id.uuidString,
            in: [first, second]
        ).id == first.id)

        do {
            _ = try MirrorSurfaceSupport.mirror(matching: "Backup", in: [first, second])
            Issue.record("Expected an ambiguous-name error")
        } catch MirrorSurfaceLookupError.ambiguousName(let name) {
            #expect(name == "Backup")
        }
    }

    @Test func surfaceProjectionPrioritizesActivityAndRedactsFailures() {
        let plan = makePlan(name: "Critical")
        let failure = MirrorFailureSummary(
            kind: .network,
            message: "https://alice:secret@example.com/acme/repo.git failed",
            failedAt: Date(timeIntervalSince1970: 2_000)
        )
        let health = MirrorHealthSnapshot(
            mirrorID: plan.id,
            lastFailure: failure,
            consecutiveFailures: 1
        )

        let failed = MirrorSurfaceSupport.snapshot(plan: plan, health: health)
        #expect(failed.status == .failed)
        #expect(failed.message?.contains("secret") == false)

        let running = MirrorSurfaceSupport.snapshot(
            plan: plan,
            health: health,
            activity: .synchronizing(
                phase: SyncPhase(.pushingTarget("origin")),
                progress: 0.5
            )
        )
        #expect(running.status == .syncing)
        #expect(running.message == nil)
    }

    @Test @MainActor func headlessRunnerLoadsPlanAndPersistsRun() async throws {
        let fixture = try SecondarySurfaceFixture()
        defer { fixture.remove() }
        let plan = makePlan(name: "Headless")
        try fixture.planStore.save([plan])
        let finishedAt = Date(timeIntervalSince1970: 3_000)

        let record = try await MirrorHeadlessSyncRunner.sync(
            query: plan.id.uuidString,
            planStore: fixture.planStore,
            stateStore: fixture.stateStore,
            runStore: fixture.runStore,
            operationFactory: { plan, stateStore, runStore in
                let record = MirrorRunRecord(
                    mirrorID: plan.id,
                    startedAt: finishedAt.addingTimeInterval(-1),
                    finishedAt: finishedAt,
                    outcome: .succeeded,
                    logLines: ["Headless sync"],
                    destinationResults: plan.destinations.map {
                        MirrorDestinationRunResult(
                            destinationID: $0.id,
                            succeeded: true,
                            completedAt: finishedAt,
                            failure: nil
                        )
                    }
                )
                return MirrorSyncOperation(
                    plan: plan,
                    stateStore: stateStore,
                    runStore: runStore,
                    driverFactory: { _ in ImmediateMirrorSyncDriver(record: record) }
                )
            }
        )

        #expect(record.mirrorID == plan.id)
        #expect(try fixture.stateStore.load()[plan.id]?.lastSuccessfulAt == finishedAt)
        #expect(try fixture.runStore.load(mirrorID: plan.id).count == 1)
    }

    @Test @MainActor func headlessRunnerRejectsMissingCredentialsBeforeStartingGit() async throws {
        let fixture = try SecondarySurfaceFixture()
        defer { fixture.remove() }
        var plan = makePlan(name: "Needs credentials")
        plan.source.auth = .sshKey(
            privateKeyPath: "/tmp/gitrelay-missing-\(UUID().uuidString)"
        )
        try fixture.planStore.save([plan])
        var madeOperation = false

        do {
            _ = try await MirrorHeadlessSyncRunner.sync(
                mirrorID: plan.id,
                planStore: fixture.planStore,
                stateStore: fixture.stateStore,
                runStore: fixture.runStore,
                operationFactory: { plan, stateStore, runStore in
                    madeOperation = true
                    return MirrorSyncOperation(
                        plan: plan,
                        stateStore: stateStore,
                        runStore: runStore
                    )
                }
            )
            Issue.record("expected missing credentials")
        } catch let error as MirrorHeadlessSyncError {
            #expect(error == .missingCredentials(plan.name))
        }

        #expect(!madeOperation)
    }

    @Test @MainActor func mirrorLeaseRejectsASecondOperationForTheSameMirror() async throws {
        let fixture = try SecondarySurfaceFixture()
        defer { fixture.remove() }
        let plan = makePlan(name: "Single flight")
        let lease = try MirrorOperationLease(mirrorID: plan.id)
        defer { lease.release() }
        let operation = MirrorSyncOperation(
            plan: plan,
            stateStore: fixture.stateStore,
            runStore: fixture.runStore,
            driverFactory: { _ in
                ImmediateMirrorSyncDriver(record: MirrorRunRecord(
                    mirrorID: plan.id,
                    outcome: .succeeded
                ))
            }
        )

        do {
            _ = try await operation.run()
            Issue.record("expected an operation lease error")
        } catch let error as MirrorOperationLeaseError {
            #expect(error == .alreadyRunning(plan.id))
        }
    }

    @Test @MainActor func headlessLogsTailAndRedactCredentials() throws {
        let fixture = try SecondarySurfaceFixture()
        defer { fixture.remove() }
        let plan = makePlan(name: "Logs")
        try fixture.runStore.append(MirrorRunRecord(
            mirrorID: plan.id,
            startedAt: Date(timeIntervalSince1970: 4_000),
            finishedAt: Date(timeIntervalSince1970: 4_001),
            outcome: .succeeded,
            logLines: [
                "first",
                "fetch https://alice:secret@example.com/acme/repo.git",
                "last"
            ]
        ))

        let lines = try MirrorHeadlessSyncRunner.logLines(
            mirrorID: plan.id,
            tail: 2,
            runStore: fixture.runStore
        )
        #expect(lines.count == 2)
        #expect(lines.joined().contains("secret") == false)
        #expect(lines.last == "last")
    }

    @Test @MainActor func syncAllContinuesAfterRecordedMirrorFailure() async throws {
        let fixture = try SecondarySurfaceFixture()
        defer { fixture.remove() }
        let first = makePlan(name: "First")
        let second = makePlan(name: "Second")
        try fixture.planStore.save([first, second])

        let records = try await MirrorHeadlessSyncRunner.syncAll(
            planStore: fixture.planStore,
            stateStore: fixture.stateStore,
            runStore: fixture.runStore,
            operationFactory: { plan, stateStore, runStore in
                let outcome: MirrorRunOutcome = plan.id == first.id ? .failed : .succeeded
                let record = MirrorRunRecord(
                    mirrorID: plan.id,
                    startedAt: Date(timeIntervalSince1970: 4_100),
                    finishedAt: Date(timeIntervalSince1970: 4_101),
                    outcome: outcome,
                    failure: outcome == .failed
                        ? MirrorFailureSummary(kind: .network, message: "offline")
                        : nil
                )
                return MirrorSyncOperation(
                    plan: plan,
                    stateStore: stateStore,
                    runStore: runStore,
                    driverFactory: { _ in ImmediateMirrorSyncDriver(record: record) }
                )
            }
        )

        #expect(records.map(\.mirrorID) == [first.id, second.id])
        #expect(records.map(\.outcome) == [.failed, .succeeded])
    }

    @Test func widgetSnapshotUsesDailyHealthAndAttention() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dayKey = SyncHistorySparkline.dayKey(for: now, calendar: calendar)
        let healthy = makePlan(name: "Healthy")
        let failed = makePlan(name: "Failed")
        let untouched = makePlan(name: "Untouched")
        let failure = MirrorFailureSummary(
            kind: .network,
            message: "network unavailable",
            failedAt: now
        )
        let health: [UUID: MirrorHealthSnapshot] = [
            healthy.id: MirrorHealthSnapshot(
                mirrorID: healthy.id,
                lastSuccessfulAt: now,
                dailyOutcomes: [dayKey: SyncDayOutcome(successes: 1)]
            ),
            failed.id: MirrorHealthSnapshot(
                mirrorID: failed.id,
                lastAttemptAt: now,
                lastFailure: failure,
                consecutiveFailures: 1,
                dailyOutcomes: [dayKey: SyncDayOutcome(failures: 1)]
            )
        ]

        let snapshot = WidgetHealthSnapshotBuilder.make(
            plans: [healthy, failed, untouched],
            health: health,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.summary.succeededToday == 1)
        #expect(snapshot.summary.failedToday == 1)
        #expect(snapshot.summary.notRunToday == 1)
        #expect(snapshot.attentionMirrors.map(\.id).contains(failed.id))
        #expect(snapshot.attentionMirrors.map(\.id).contains(untouched.id))
        #expect(!snapshot.attentionMirrors.map(\.id).contains(healthy.id))
    }

    @Test func webhookRoutingUsesPolicyAndStableMirrorID() {
        let secret = "webhook-secret"
        let body = Data("{\"ref\":\"refs/heads/main\"}".utf8)
        var enabled = makePlan(name: "Enabled")
        enabled.policy.triggers.webhookEnabled = true
        let disabled = makePlan(name: "Disabled")

        func request(for plan: MirrorPlan) -> WebhookHTTPRequest {
            WebhookHTTPRequest(
                method: "POST",
                path: "/hook/\(WebhookPushMapper.pathID(for: plan.id))",
                headers: [
                    "X-GitHub-Event": "push",
                    "X-Hub-Signature-256": WebhookHMACVerifier.githubSignatureHeader(
                        payload: body,
                        secret: secret
                    )
                ],
                body: body
            )
        }

        let accepted = MirrorWebhookRouter.decide(
            request: request(for: enabled),
            plans: [enabled, disabled],
            secretForMirror: { _ in secret }
        )
        #expect(accepted.syncRepoID == enabled.id)

        let ignored = MirrorWebhookRouter.decide(
            request: request(for: disabled),
            plans: [enabled, disabled],
            secretForMirror: { _ in secret }
        )
        #expect(ignored == .ignored(reason: "webhook disabled for repo"))
    }

    @Test @MainActor func cliProjectionIncludesStableIDAndRedactsMessage() throws {
        let plan = makePlan(name: "CLI")
        let snapshot = MirrorSurfaceSnapshot(
            mirrorID: plan.id,
            mirrorName: plan.name,
            status: .failed,
            lastSuccessfulAt: nil,
            message: "https://alice:secret@example.com/acme/repo.git failed"
        )

        let json = try GitRelayCLIFormatter.jsonString(
            GitRelayCLIFormatter.statusEntry(from: snapshot)
        )
        #expect(json.lowercased().contains(plan.id.uuidString.lowercased()))
        #expect(json.contains("secret") == false)
        #expect(GitRelayCLIParser.usage.contains("mirrors.json"))
    }

    @Test @MainActor func appIntentEntityIdentityUsesMirrorUUID() {
        let plan = makePlan(name: "Shortcut")
        let entity = MirrorStatusEntity(snapshot: MirrorSurfaceSnapshot(
            mirrorID: plan.id,
            mirrorName: plan.name,
            status: .healthy,
            lastSuccessfulAt: Date(timeIntervalSince1970: 5_000),
            message: nil
        ))

        #expect(entity.id == plan.id.uuidString.lowercased())
        #expect(entity.mirrorUUID == plan.id)
        #expect(entity.mirrorName == plan.name)
    }

    private func makePlan(name: String) -> MirrorPlan {
        MirrorPlan(
            name: name,
            source: GitEndpoint(url: "git@github.com:acme/\(UUID().uuidString).git"),
            destinations: [
                .git(url: "git@gitlab.com:acme/\(UUID().uuidString).git")
            ],
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
    }
}

@MainActor
private final class ImmediateMirrorSyncDriver: MirrorSyncDriving {
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

    private let record: MirrorRunRecord

    init(record: MirrorRunRecord) {
        self.record = record
    }

    func run() async {
        onEvent?(.started)
        onEvent?(.finished(record))
    }

    func cancel() {}
}

private struct SecondarySurfaceFixture {
    let directory: URL
    let planStore: MirrorPlanStore
    let stateStore: MirrorStateStore
    let runStore: MirrorRunStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-secondary-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        planStore = MirrorPlanStore(fileURL: directory.appendingPathComponent("mirrors.json"))
        stateStore = MirrorStateStore(fileURL: directory.appendingPathComponent("mirror-state.json"))
        runStore = MirrorRunStore(directoryURL: directory.appendingPathComponent("logs"))
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
