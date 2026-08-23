import Foundation
import Testing
@testable import GitRelay

@MainActor
@Suite(.serialized)
struct MirrorOperationsControllerTests {
    private struct Fixture {
        let directory: URL
        let library: MirrorLibraryModel

        @MainActor
        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitrelay-operations-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            library = MirrorLibraryModel(
                planStore: MirrorPlanStore(fileURL: directory.appendingPathComponent("mirrors.json")),
                stateStore: MirrorStateStore(fileURL: directory.appendingPathComponent("mirror-state.json")),
                runStore: MirrorRunStore(directoryURL: directory.appendingPathComponent("logs")),
                credentialProbe: .alwaysPresent
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func mirror(name: String) -> MirrorSnapshot {
        MirrorSnapshot(
            name: name,
            srcURL: "git@github.com:acme/\(name).git",
            dstURL: "git@gitlab.com:acme/\(name).git"
        )
    }

    @Test func controllerOwnsFIFOAdmissionAndPromotion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let mirrors = [mirror(name: "one"), mirror(name: "two"), mirror(name: "three")]
        try fixture.library.add(contentsOf: mirrors)
        let controller = MirrorOperationsController(
            library: fixture.library,
            maxConcurrentSyncs: 1,
            credentialProbe: .alwaysPresent
        )
        controller.suspendSyncEngineForTesting = true

        mirrors.forEach { controller.triggerSync(mirrorID: $0.id) }

        #expect(controller.inProgressSyncIDs == [mirrors[0].id])
        #expect(controller.statuses[mirrors[1].id] == .queued)
        #expect(controller.statuses[mirrors[2].id] == .queued)
        controller.cancelSync(mirrorID: mirrors[0].id)
        #expect(controller.inProgressSyncIDs == [mirrors[1].id])
        controller.cancelSync(mirrorID: mirrors[1].id)
        #expect(controller.inProgressSyncIDs == [mirrors[2].id])
    }

    @Test func duplicateTriggerCannotAcquireAnotherSlot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let value = mirror(name: "single")
        try fixture.library.add(value)
        let controller = MirrorOperationsController(
            library: fixture.library,
            maxConcurrentSyncs: 1,
            credentialProbe: .alwaysPresent
        )
        controller.suspendSyncEngineForTesting = true

        controller.triggerSync(mirrorID: value.id)
        controller.triggerSync(mirrorID: value.id)

        #expect(controller.inProgressSyncIDs == [value.id])
        #expect(controller.queueEntries.count == 1)
    }

    @Test func credentialGateBlocksBeforeOperationAdmission() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let id = UUID()
        let plan = MirrorPlan(
            id: id,
            name: "private",
            source: GitEndpoint(
                url: "https://github.com/acme/private.git",
                auth: .httpsToken(keychainTag: "missing-source-token")
            ),
            destinations: [
                .git(url: "git@gitlab.com:acme/private.git")
            ]
        )
        try fixture.library.add(MirrorSnapshot(plan: plan))
        let controller = MirrorOperationsController(
            library: fixture.library,
            credentialProbe: .alwaysMissing
        )
        var reportedMessage: String?
        controller.onCredentialsRequired = { _, message in reportedMessage = message }

        controller.triggerSync(mirrorID: id)

        #expect(controller.inProgressSyncIDs.isEmpty)
        #expect(controller.queueEntries.isEmpty)
        #expect(controller.statuses[id] == .failed(MirrorCredentialGate.missingCredentialsMessage))
        #expect(reportedMessage == MirrorCredentialGate.missingCredentialsMessage)
        #expect(fixture.library.mirror(id: id)?.needsCredentials == true)
    }

    @Test func libraryReplacementInvalidatesRuntimeGeneration() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = mirror(name: "old")
        try fixture.library.add(old)
        let controller = MirrorOperationsController(
            library: fixture.library,
            maxConcurrentSyncs: 1,
            credentialProbe: .alwaysPresent
        )
        controller.suspendSyncEngineForTesting = true
        controller.triggerSync(mirrorID: old.id)
        let replacement = mirror(name: "replacement")
        try fixture.library.replace(with: [replacement], preservePersistedHealth: false)

        let cleared = controller.resetForCurrentLibrary()

        #expect(cleared.contains(old.id))
        #expect(controller.inProgressSyncIDs.isEmpty)
        #expect(controller.statuses[old.id] == nil)
        #expect(controller.statuses[replacement.id] == .unknown)
    }
}
