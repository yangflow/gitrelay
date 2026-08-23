import Foundation
import Testing
@testable import GitRelay

@Suite("GitRelay execution acceptance")
@MainActor
struct MirrorExecutionAcceptanceTests {
    @Test func nativeDriverMirrorsGitArchiveLFSAndReleasesFromPlan() async throws {
        let fixture = try NativeMirrorFixture()
        defer { fixture.remove() }
        try fixture.createSourceRepository()
        try fixture.createBareRepository(at: fixture.primaryDestination)

        let gitDestinationID = UUID()
        let archiveDestinationID = UUID()
        let plan = MirrorPlan(
            name: "Native backup",
            source: GitEndpoint(url: fixture.source.path),
            destinations: [
                .git(id: gitDestinationID, url: fixture.primaryDestination.path),
                .archive(
                    id: archiveDestinationID,
                    directoryPath: fixture.archiveDirectory.path,
                    format: .tarGz,
                    filenameTemplate: "native-{{date}}.tar.gz",
                    retentionCount: 2
                ),
            ],
            policy: MirrorPolicy(
                destructivePush: .auto,
                content: MirrorContentPolicy(
                    lfsMode: .auto,
                    mirrorsReleases: true
                )
            )
        )
        let lfs = RecordingLFSRunner()
        let releaseProbe = ReleaseProbe()
        let driver = MirrorSyncDriver(
            plan: plan,
            mirrorRootDirectory: fixture.mirrorRoot,
            lfsCommandRunner: lfs
        )
        let operation = fixture.operation(plan: plan, driver: driver)
        operation.mirrorReleases = { mirroredPlan, destination, _ in
            releaseProbe.record(plan: mirroredPlan, destination: destination)
        }

        let record = try await operation.run()

        #expect(record.outcome == .succeeded)
        #expect(record.destinationResults.count == 2)
        #expect(record.destinationResults.allSatisfy { $0.succeeded })
        #expect(try fixture.gitOutput([
            "--git-dir", fixture.primaryDestination.path,
            "rev-parse", "--verify", "refs/heads/main",
        ]).isEmpty == false)
        let archives = try FileManager.default.contentsOfDirectory(
            at: fixture.archiveDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(archives.count == 1)
        #expect(archives[0].pathExtension == "gz")
        #expect(releaseProbe.mirrorID == plan.id)
        #expect(releaseProbe.destinationIDs == [gitDestinationID])
        let lfsCalls = await lfs.calls()
        #expect(lfsCalls.fetchCount == 1)
        #expect(lfsCalls.pushURLs == [fixture.primaryDestination.path])
    }

    @Test func strictPolicyBlocksDestructiveDeletionAndPreservesDestinationRef() async throws {
        let fixture = try NativeMirrorFixture()
        defer { fixture.remove() }
        try fixture.createSourceRepository()
        try fixture.createBareRepository(at: fixture.primaryDestination)

        let destination = MirrorDestination.git(url: fixture.primaryDestination.path)
        var plan = MirrorPlan(
            name: "Protected mirror",
            source: GitEndpoint(url: fixture.source.path),
            destinations: [destination],
            policy: MirrorPolicy(
                destructivePush: .auto,
                content: MirrorContentPolicy(lfsMode: .off)
            )
        )
        let firstRun = try await fixture.operation(
            plan: plan,
            driver: MirrorSyncDriver(plan: plan, mirrorRootDirectory: fixture.mirrorRoot)
        ).run()
        #expect(firstRun.outcome == .succeeded)

        let mainSHA = try fixture.gitOutput([
            "--git-dir", fixture.primaryDestination.path,
            "rev-parse", "refs/heads/main",
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        try fixture.runGit([
            "--git-dir", fixture.primaryDestination.path,
            "update-ref", "refs/heads/target-only", mainSHA,
        ])

        plan.policy.destructivePush = .strict
        let destructiveProbe = DestructiveProbe()
        let operation = fixture.operation(
            plan: plan,
            driver: MirrorSyncDriver(plan: plan, mirrorRootDirectory: fixture.mirrorRoot)
        )
        operation.confirmDestructivePush = { impact, destination in
            destructiveProbe.record(impact: impact, destination: destination)
            return .cancel
        }

        let blocked = try await operation.run()

        #expect(blocked.outcome == .failed)
        #expect(blocked.failure?.kind == .destructiveChangeBlocked)
        #expect(blocked.destinationResults.first?.failure?.kind == .destructiveChangeBlocked)
        #expect(destructiveProbe.destinationID == destination.id)
        #expect(destructiveProbe.deletedRefs.contains("target-only"))
        #expect(try fixture.gitOutput([
            "--git-dir", fixture.primaryDestination.path,
            "show-ref", "--verify", "refs/heads/target-only",
        ]).isEmpty == false)
    }

    @Test func realMultiTargetRunPersistsPartialSuccessWithoutRollingBackHealthyTarget() async throws {
        let fixture = try NativeMirrorFixture()
        defer { fixture.remove() }
        try fixture.createSourceRepository()
        try fixture.createBareRepository(at: fixture.primaryDestination)
        try Data("not a directory".utf8).write(to: fixture.blockingFile)
        let invalidDestination = fixture.blockingFile.appendingPathComponent("unreachable.git")

        let healthyID = UUID()
        let failedID = UUID()
        let plan = MirrorPlan(
            name: "Partial mirror",
            source: GitEndpoint(url: fixture.source.path),
            destinations: [
                .git(id: healthyID, url: fixture.primaryDestination.path),
                .git(id: failedID, url: invalidDestination.path),
            ],
            policy: MirrorPolicy(
                destructivePush: .auto,
                content: MirrorContentPolicy(lfsMode: .off)
            )
        )

        let record = try await fixture.operation(
            plan: plan,
            driver: MirrorSyncDriver(plan: plan, mirrorRootDirectory: fixture.mirrorRoot)
        ).run()

        #expect(record.outcome == .partiallySucceeded)
        #expect(record.destinationResults.first(where: { $0.destinationID == healthyID })?.succeeded == true)
        #expect(record.destinationResults.first(where: { $0.destinationID == failedID })?.succeeded == false)
        let health = try #require(fixture.stateStore.load()[plan.id])
        #expect(health.destinations.first(where: { $0.destinationID == healthyID })?.lastSuccessfulAt != nil)
        #expect(health.destinations.first(where: { $0.destinationID == failedID })?.lastFailure != nil)
        #expect(try fixture.gitOutput([
            "--git-dir", fixture.primaryDestination.path,
            "rev-parse", "--verify", "refs/heads/main",
        ]).isEmpty == false)
    }

    @Test func mainApplicationLaunchAndCRUDPersistMirrorLibrary() throws {
        let fixture = try NativeMirrorFixture()
        defer { fixture.remove() }
        Constants.setBaseDirectoryForTesting(fixture.directory)
        defer { Constants.setBaseDirectoryForTesting(nil) }

        let planStore = MirrorPlanStore(
            fileURL: fixture.directory.appendingPathComponent("mirrors.json")
        )
        let stateStore = MirrorStateStore(
            fileURL: fixture.directory.appendingPathComponent("mirror-state.json")
        )
        let suiteName = "gitrelay-app-launch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let app = makeAppModel(
            defaults: defaults,
            planStore: planStore,
            stateStore: stateStore,
            runStore: fixture.runStore
        )
        #expect(app.repos.isEmpty)
        #expect(app.mirrorPlans.isEmpty)

        let mirror = MirrorSnapshot(
            name: "Application mirror",
            srcURL: "git@github.com:acme/source.git",
            dstURL: "git@gitlab.com:acme/destination.git"
        )
        app.addRepo(mirror)

        #expect(app.repos.map(\.id) == [mirror.id])
        #expect(try planStore.load().map(\.id) == [mirror.id])
        let relaunched = makeAppModel(
            defaults: defaults,
            planStore: planStore,
            stateStore: stateStore,
            runStore: fixture.runStore
        )
        #expect(relaunched.repos.map(\.id) == [mirror.id])
        #expect(relaunched.repos.first?.name == mirror.name)
    }

    private func makeAppModel(
        defaults: UserDefaults,
        planStore: MirrorPlanStore,
        stateStore: MirrorStateStore,
        runStore: MirrorRunStore
    ) -> GitRelayAppModel {
        GitRelayAppModel(
            verificationPreferencesStore: VerificationPreferencesStore(defaults: defaults),
            orgSubscriptionStore: OrgSubscriptionStore(defaults: defaults),
            webhookPreferencesStore: WebhookPreferencesStore(defaults: defaults),
            securityPreferencesStore: SecurityPreferencesStore(defaults: defaults),
            cachePreferencesStore: CachePreferencesStore(defaults: defaults),
            notificationPreferencesStore: NotificationPreferencesStore(defaults: defaults),
            appBehaviorPreferencesStore: AppBehaviorPreferencesStore(defaults: defaults),
            windowLayoutStore: WindowLayoutStore(defaults: defaults),
            biometricAuthenticator: PermissiveBiometricAuthenticator(),
            mirrorPlanStore: planStore,
            mirrorStateStore: stateStore,
            mirrorRunStore: runStore
        )
    }
}

@MainActor
private final class ReleaseProbe {
    private(set) var mirrorID: UUID?
    private(set) var destinationIDs: [UUID] = []

    func record(plan: MirrorPlan, destination: MirrorDestination) {
        mirrorID = plan.id
        destinationIDs.append(destination.id)
    }
}

@MainActor
private final class DestructiveProbe {
    private(set) var destinationID: UUID?
    private(set) var deletedRefs: [String] = []

    func record(impact: DestructivePushPlan, destination: MirrorDestination) {
        destinationID = destination.id
        deletedRefs = impact.deletedRefs
    }
}

private actor RecordingLFSRunner: LFSCommandRunning {
    private var fetchCount = 0
    private var pushURLs: [String] = []

    func isGitLFSAvailable() async throws -> Bool { true }
    func repositoryUsesLFS(mirrorPath: String) async throws -> Bool { true }

    func lfsFetchAll(
        mirrorPath: String,
        env: [String: String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws {
        fetchCount += 1
    }

    func lfsPushAll(
        mirrorPath: String,
        remoteURL: String,
        env: [String: String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws {
        pushURLs.append(remoteURL)
    }

    func calls() -> (fetchCount: Int, pushURLs: [String]) {
        (fetchCount, pushURLs)
    }
}

@MainActor
private struct NativeMirrorFixture {
    let directory: URL
    let work: URL
    let source: URL
    let primaryDestination: URL
    let archiveDirectory: URL
    let blockingFile: URL
    let mirrorRoot: URL
    let stateStore: MirrorStateStore
    let runStore: MirrorRunStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-execution-acceptance")
            .appendingPathComponent(UUID().uuidString)
        work = directory.appendingPathComponent("work")
        source = directory.appendingPathComponent("source.git")
        primaryDestination = directory.appendingPathComponent("destination.git")
        archiveDirectory = directory.appendingPathComponent("archives")
        blockingFile = directory.appendingPathComponent("blocking-file")
        mirrorRoot = directory.appendingPathComponent("mirrors")
        stateStore = MirrorStateStore(
            fileURL: directory.appendingPathComponent("mirror-state.json")
        )
        runStore = MirrorRunStore(directoryURL: directory.appendingPathComponent("logs"))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func createSourceRepository() throws {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        try runGit(["init", "--initial-branch=main", work.path])
        try runGit(["-C", work.path, "config", "user.email", "tests@gitrelay.local"])
        try runGit(["-C", work.path, "config", "user.name", "GitRelay Tests"])
        try Data("native mirror\n".utf8).write(to: work.appendingPathComponent("README.md"))
        try runGit(["-C", work.path, "add", "README.md"])
        try runGit(["-C", work.path, "commit", "-m", "initial"])
        try runGit(["clone", "--bare", work.path, source.path])
    }

    func createBareRepository(at url: URL) throws {
        try runGit(["init", "--bare", url.path])
    }

    func operation(plan: MirrorPlan, driver: MirrorSyncDriver) -> MirrorSyncOperation {
        MirrorSyncOperation(
            plan: plan,
            stateStore: stateStore,
            runStore: runStore,
            driverFactory: { _ in driver }
        )
    }

    func runGit(_ arguments: [String]) throws {
        _ = try run(arguments)
    }

    func gitOutput(_ arguments: [String]) throws -> String {
        try run(arguments)
    }

    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NativeMirrorTestError.commandFailed(message)
        }
        return message
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum NativeMirrorTestError: Error {
    case commandFailed(String)
}
