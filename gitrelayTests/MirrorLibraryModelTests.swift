import Foundation
import Testing
@testable import GitRelay

@MainActor
@Suite(.serialized)
struct MirrorLibraryModelTests {
    private struct Fixture {
        let directory: URL
        let planStore: MirrorPlanStore
        let stateStore: MirrorStateStore
        let runStore: MirrorRunStore

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitrelay-library-tests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            planStore = MirrorPlanStore(fileURL: directory.appendingPathComponent("mirrors.json"))
            stateStore = MirrorStateStore(fileURL: directory.appendingPathComponent("mirror-state.json"))
            runStore = MirrorRunStore(directoryURL: directory.appendingPathComponent("logs", isDirectory: true))
        }

        @MainActor
        func model() -> MirrorLibraryModel {
            MirrorLibraryModel(
                planStore: planStore,
                stateStore: stateStore,
                runStore: runStore,
                credentialProbe: .alwaysPresent
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func mirror(id: UUID = UUID(), name: String) -> MirrorSnapshot {
        MirrorSnapshot(
            id: id,
            name: name,
            srcURL: "git@github.com:acme/\(name).git",
            dstURL: "git@gitlab.com:acme/\(name).git"
        )
    }

    @Test func crudPersistsThroughOneLibraryOwner() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let model = fixture.model()
        let id = UUID()

        try model.add(mirror(id: id, name: "docs"))
        #expect(model.plans.map(\.name) == ["docs"])
        #expect(try fixture.planStore.load().map(\.name) == ["docs"])

        var updated = try #require(model.mirror(id: id))
        updated.name = "handbook"
        try model.update(updated)
        #expect(model.mirrors.map(\.name) == ["handbook"])
        #expect(try fixture.planStore.load().map(\.name) == ["handbook"])

        try model.remove(id: id)
        #expect(model.mirrors.isEmpty)
        #expect(try fixture.planStore.load().isEmpty)
        #expect(try fixture.stateStore.load().isEmpty)
    }

    @Test func corruptHealthNeverHidesValidPlans() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let plan = mirror(name: "visible").plan
        try fixture.planStore.save([plan])
        try Data("not-json".utf8).write(to: fixture.stateStore.fileURL)

        let model = fixture.model()

        #expect(model.plans.map(\.id) == [plan.id])
        #expect(model.mirrors.map(\.id) == [plan.id])
        #expect(model.healthSnapshots.isEmpty)
        #expect(model.lastErrorMessage != nil)
    }

    @Test func failedCommitLeavesMemoryAndPlanFileUnchanged() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let original = mirror(name: "original")
        try fixture.planStore.save([original.plan])
        let blockedParent = fixture.directory.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockedParent)
        let model = MirrorLibraryModel(
            planStore: fixture.planStore,
            stateStore: MirrorStateStore(
                fileURL: blockedParent.appendingPathComponent("mirror-state.json")
            ),
            runStore: fixture.runStore,
            credentialProbe: .alwaysPresent
        )
        var changed = try #require(model.mirror(id: original.id))
        changed.name = "changed"

        #expect(throws: Error.self) {
            try model.update(changed)
        }
        #expect(model.mirrors.map(\.name) == ["original"])
        #expect(try fixture.planStore.load().map(\.name) == ["original"])
        #expect(model.lastErrorMessage != nil)
    }

    @Test func replaceCanDiscardHealthForReusedIdentifiers() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let id = UUID()
        let old = mirror(id: id, name: "old")
        try fixture.planStore.save([old.plan])
        try fixture.stateStore.save([
            id: MirrorHealthSnapshot(
                mirrorID: id,
                lastFailure: MirrorFailureSummary(kind: .network, message: "old failure"),
                consecutiveFailures: 3
            )
        ])
        let model = fixture.model()
        let replacement = mirror(id: id, name: "replacement")

        try model.replace(with: [replacement], preservePersistedHealth: false)

        #expect(model.mirror(id: id)?.name == "replacement")
        #expect(model.mirror(id: id)?.lastSyncError == nil)
        #expect(try fixture.stateStore.load()[id]?.lastFailure == nil)
    }
}
