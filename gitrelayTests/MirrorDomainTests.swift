import Foundation
import Testing
@testable import GitRelay

@Suite("GitRelay mirror domain")
struct MirrorDomainTests {
    @Test func planNormalizesUserFacingMetadataAndRoundTrips() throws {
        let mirrorID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let plan = MirrorPlan(
            id: mirrorID,
            name: "  Production backup  ",
            source: GitEndpoint(
                url: "  git@github.com:acme/source.git  ",
                provider: .github,
                accountLabel: "  work  "
            ),
            destinations: [
                .git(url: "git@gitlab.com:acme/backup.git", provider: .gitlab),
                .archive(directoryPath: "/Volumes/Backup/Git", retentionCount: 7)
            ],
            labels: ["Critical", " critical ", "Offsite", "  "],
            createdAt: createdAt
        )

        let validated = try plan.validated()
        #expect(validated.name == "Production backup")
        #expect(validated.source.url == "git@github.com:acme/source.git")
        #expect(validated.source.accountLabel == "work")
        #expect(validated.labels == ["Critical", "Offsite"])

        let data = try MirrorPersistenceCoding.encoder.encode(validated)
        let decoded = try MirrorPersistenceCoding.decoder.decode(MirrorPlan.self, from: data)
        #expect(decoded == validated)
    }

    @Test func planRequiresAUsableNameAndDestination() {
        let source = GitEndpoint(url: "git@github.com:acme/source.git")

        #expect(throws: MirrorDomainError.emptyName) {
            try MirrorPlan(name: " ", source: source, destinations: [
                .git(url: "git@gitlab.com:acme/backup.git")
            ]).validated()
        }
        #expect(throws: MirrorDomainError.noDestinations) {
            try MirrorPlan(name: "Backup", source: source, destinations: []).validated()
        }
        #expect(throws: MirrorDomainError.noEnabledDestinations) {
            try MirrorPlan(name: "Backup", source: source, destinations: [
                .git(url: "git@gitlab.com:acme/backup.git", isEnabled: false)
            ]).validated()
        }
    }

    @Test func persistenceCanRetainAPlanWaitingForAMachineLocalSSHKey() throws {
        let plan = MirrorPlan(
            name: "Needs key",
            source: GitEndpoint(
                url: "git@github.com:acme/source.git",
                auth: .sshKey(privateKeyPath: "")
            ),
            destinations: [
                .git(url: "git@gitlab.com:acme/backup.git")
            ]
        )

        #expect(throws: MirrorDomainError.emptySSHKeyPath(.source)) {
            try plan.validated()
        }
        #expect(
            try plan.validated(allowMissingCredentials: true) == plan
        )
        #expect(MirrorCredentialGate.needsCredentials(for: plan, probe: .alwaysMissing))
    }

    @Test func planRejectsAmbiguousDestinationTopology() {
        let sourceURL = "git@github.com:acme/source.git"
        let destinationID = UUID()

        #expect(throws: MirrorDomainError.sourceMatchesDestination) {
            try MirrorPlan(
                name: "Backup",
                source: GitEndpoint(url: sourceURL),
                destinations: [.git(url: "ssh://git@github.com/acme/source.git")]
            ).validated()
        }
        #expect(throws: MirrorDomainError.duplicateDestinationID(destinationID)) {
            try MirrorPlan(
                name: "Backup",
                source: GitEndpoint(url: sourceURL),
                destinations: [
                    .git(id: destinationID, url: "git@gitlab.com:acme/one.git"),
                    .git(id: destinationID, url: "git@gitlab.com:acme/two.git")
                ]
            ).validated()
        }
        #expect(throws: MirrorDomainError.duplicateDestination("gitlab.com/acme/backup")) {
            try MirrorPlan(
                name: "Backup",
                source: GitEndpoint(url: sourceURL),
                destinations: [
                    .git(url: "git@gitlab.com:acme/backup.git"),
                    .git(url: "https://gitlab.com/acme/backup.git")
                ]
            ).validated()
        }
    }

    @Test func archiveTemplateCannotEscapeItsSelectedDirectory() {
        let source = GitEndpoint(url: "git@github.com:acme/source.git")
        for template in ["../../Library/target.tar.gz", "nested/target.tar.gz", "..\\target.zip"] {
            #expect(throws: MirrorDomainError.unsafeArchiveFilenameTemplate) {
                try MirrorPlan(
                    name: "Archive",
                    source: source,
                    destinations: [
                        .archive(
                            directoryPath: "/Volumes/Backup",
                            filenameTemplate: template
                        )
                    ]
                ).validated()
            }
        }
    }

    @Test func healthDerivationKeepsActivityHealthAndScheduleConcernsSeparate() {
        let plan = validPlan()
        #expect(MirrorHealth.derive(plan: plan, snapshot: nil) == .neverRun)

        let successAt = Date(timeIntervalSince1970: 1_800_000_000)
        let healthy = MirrorHealthSnapshot(mirrorID: plan.id, lastSuccessfulAt: successAt)
        #expect(MirrorHealth.derive(plan: plan, snapshot: healthy) == .healthy)
        #expect(
            MirrorHealth.derive(
                plan: plan,
                snapshot: healthy,
                staleAfter: successAt.addingTimeInterval(1)
            ) == .stale(since: successAt)
        )

        let failure = MirrorFailureSummary(
            kind: .network,
            message: "Connection timed out",
            failedAt: successAt.addingTimeInterval(60)
        )
        let failed = MirrorHealthSnapshot(
            mirrorID: plan.id,
            lastSuccessfulAt: successAt,
            lastFailure: failure
        )
        #expect(MirrorHealth.derive(plan: plan, snapshot: failed) == .failed(failure))
    }

    @Test func applicationSnapshotKeepsPlanAndHealthSeparated() throws {
        let destinationID = UUID()
        let plan = MirrorPlan(
            name: "Provider-backed mirror",
            source: GitEndpoint(
                url: "git@github.com:acme/source.git",
                provider: .github,
                accountLabel: "work"
            ),
            destinations: [
                .git(
                    id: destinationID,
                    url: "git@gitlab.com:acme/backup.git",
                    provider: .gitlab,
                    accountLabel: "backup"
                )
            ],
            policy: MirrorPolicy(
                verification: MirrorVerificationPolicy(
                    frequency: .day1,
                    branch: "develop"
                )
            )
        )
        let verifiedAt = Date(timeIntervalSince1970: 1_900_000_000)
        let health = MirrorHealthSnapshot(
            mirrorID: plan.id,
            lastSuccessfulAt: verifiedAt.addingTimeInterval(-60),
            lastVerifiedAt: verifiedAt,
            integrity: .inconclusive("remote unavailable"),
            destinations: [
                MirrorDestinationHealthSnapshot(
                    destinationID: destinationID,
                    lastSuccessfulAt: verifiedAt.addingTimeInterval(-60),
                    lastVerifiedAt: verifiedAt,
                    integrity: .inconclusive("remote unavailable")
                )
            ]
        )

        var snapshot = MirrorSnapshot(plan: plan, health: health)
        snapshot.name = "Renamed mirror"
        snapshot.defaultBranch = "release"
        let projectedPlan = try snapshot.plan.validated()
        let projectedHealth = snapshot.health

        #expect(projectedPlan.name == "Renamed mirror")
        #expect(projectedPlan.source.provider == .github)
        #expect(projectedPlan.source.accountLabel == "work")
        if case .git(let endpoint) = projectedPlan.destinations[0].location {
            #expect(endpoint.provider == .gitlab)
            #expect(endpoint.accountLabel == "backup")
        } else {
            Issue.record("expected Git destination")
        }
        #expect(projectedPlan.policy.verification.frequency == .day1)
        #expect(projectedPlan.policy.verification.branch == "release")
        #expect(projectedHealth.integrity == .inconclusive("remote unavailable"))
        #expect(projectedHealth.destinations == health.destinations)
    }

    private func validPlan(id: UUID = UUID()) -> MirrorPlan {
        MirrorPlan(
            id: id,
            name: "Backup",
            source: GitEndpoint(url: "git@github.com:acme/source.git"),
            destinations: [.git(url: "git@gitlab.com:acme/backup.git")]
        )
    }
}

@Suite("GitRelay persistence boundary")
struct MirrorPersistenceTests {
    @Test func planStoreIgnoresAnUnrelatedRepositoryListFile() throws {
        let fixture = try TemporaryMirrorStoreFixture()
        defer { fixture.remove() }

        let unrelatedURL = fixture.directory.appendingPathComponent("repos.json")
        try Data("{\"repos\":[{\"name\":\"sample\"}]}".utf8).write(to: unrelatedURL)
        let store = MirrorPlanStore(fileURL: fixture.directory.appendingPathComponent("mirrors.json"))
        #expect(try store.load().isEmpty)

        let plan = fixture.validPlan()
        try store.save([plan])
        #expect(try store.load() == [plan])
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    @Test func planStoreRejectsUnknownVersionsAndDuplicateIDs() throws {
        let fixture = try TemporaryMirrorStoreFixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("mirrors.json")
        let store = MirrorPlanStore(fileURL: url)

        let unknown = MirrorPlanDocument(version: 99, mirrors: [])
        try MirrorPersistenceCoding.atomicWrite(
            MirrorPersistenceCoding.encoder.encode(unknown),
            to: url
        )
        #expect(throws: MirrorPersistenceError.unsupportedVersion(99)) {
            try store.load()
        }

        let plan = fixture.validPlan()
        #expect(throws: MirrorPersistenceError.duplicateMirrorID(plan.id)) {
            try store.save([plan, plan])
        }
    }

    @Test func stateStoreRoundTripsAndRejectsDuplicateSnapshots() throws {
        let fixture = try TemporaryMirrorStoreFixture()
        defer { fixture.remove() }
        let url = fixture.directory.appendingPathComponent("mirror-state.json")
        let store = MirrorStateStore(fileURL: url)
        let mirrorID = UUID()
        let snapshot = MirrorHealthSnapshot(
            mirrorID: mirrorID,
            lastSuccessfulAt: Date(timeIntervalSince1970: 1_800_000_000),
            integrity: .verified,
            dailyOutcomes: ["2026-08-22": SyncDayOutcome(successes: 1)]
        )

        try store.save([mirrorID: snapshot])
        #expect(try store.load() == [mirrorID: snapshot])

        let duplicateDocument = MirrorStateDocument(snapshots: [snapshot, snapshot])
        try MirrorPersistenceCoding.atomicWrite(
            MirrorPersistenceCoding.encoder.encode(duplicateDocument),
            to: url
        )
        #expect(throws: MirrorPersistenceError.duplicateMirrorID(mirrorID)) {
            try store.load()
        }
    }

    @Test func concurrentPerMirrorUpdatesDoNotEraseOtherMirrors() async throws {
        let fixture = try TemporaryMirrorStoreFixture()
        defer { fixture.remove() }
        let store = MirrorStateStore(
            fileURL: fixture.directory.appendingPathComponent("concurrent-state.json")
        )
        let mirrorIDs = (0..<24).map { _ in UUID() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (offset, mirrorID) in mirrorIDs.enumerated() {
                group.addTask {
                    try store.update(mirrorID: mirrorID) { _ in
                        MirrorHealthSnapshot(
                            mirrorID: mirrorID,
                            lastSuccessfulAt: Date(timeIntervalSince1970: TimeInterval(offset))
                        )
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(Set(try store.load().keys) == Set(mirrorIDs))
    }

    @Test func runStorePersistsJsonLinesWithoutCredentials() throws {
        let fixture = try TemporaryMirrorStoreFixture()
        defer { fixture.remove() }
        let store = MirrorRunStore(directoryURL: fixture.directory.appendingPathComponent("logs"))
        let mirrorID = UUID()
        let destinationID = UUID()
        let token = "ghp_private_token"
        let failure = MirrorFailureSummary(
            kind: .destinationAuthentication,
            message: "https://\(token)@git.example.com/acme/backup.git rejected",
            destinationID: destinationID
        )
        let record = MirrorRunRecord(
            mirrorID: mirrorID,
            outcome: .failed,
            logLines: ["fetch https://\(token)@git.example.com/acme/source.git"],
            destinationResults: [
                MirrorDestinationRunResult(
                    destinationID: destinationID,
                    succeeded: false,
                    completedAt: Date(),
                    failure: failure
                )
            ]
        )

        try store.append(record)
        let persisted = try String(contentsOf: store.fileURL(for: mirrorID), encoding: .utf8)
        #expect(!persisted.contains(token))
        #expect(persisted.contains("****@"))

        let loaded = try store.load(mirrorID: mirrorID)
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == record.id)
        #expect(loaded.first?.logLines.first?.contains("****@") == true)
    }

    @Test func storagePathsUseProductDirectories() {
        #expect(Constants.mirrorPlansFile.lastPathComponent == "mirrors.json")
        #expect(Constants.mirrorStateFile.lastPathComponent == "mirror-state.json")
        #expect(Constants.mirrorLogsDirectory.lastPathComponent == "logs")
        #expect(Constants.mirrorCacheDirectory.lastPathComponent == "mirrors")
    }
}

private struct TemporaryMirrorStoreFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitrelay-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func validPlan(id: UUID = UUID()) -> MirrorPlan {
        MirrorPlan(
            id: id,
            name: "Backup",
            source: GitEndpoint(url: "git@github.com:acme/source.git"),
            destinations: [.git(url: "git@gitlab.com:acme/backup.git")],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
