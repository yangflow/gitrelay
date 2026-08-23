import Foundation
import Testing
@testable import GitRelay

@MainActor
@Suite(.serialized)
struct WorkspaceModelTests {
    private struct Fixture {
        let directory: URL
        let suiteName: String
        let defaults: UserDefaults
        let library: MirrorLibraryModel
        let operations: MirrorOperationsController
        let layout: WindowLayoutStore

        @MainActor
        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("gitrelay-workspace-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            suiteName = "gitrelay.workspace.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suiteName)!
            library = MirrorLibraryModel(
                planStore: MirrorPlanStore(fileURL: directory.appendingPathComponent("mirrors.json")),
                stateStore: MirrorStateStore(fileURL: directory.appendingPathComponent("mirror-state.json")),
                runStore: MirrorRunStore(directoryURL: directory.appendingPathComponent("logs")),
                credentialProbe: .alwaysPresent
            )
            operations = MirrorOperationsController(
                library: library,
                credentialProbe: .alwaysPresent
            )
            layout = WindowLayoutStore(defaults: defaults)
        }

        @MainActor
        func add(_ mirrors: [MirrorSnapshot]) throws {
            try library.add(contentsOf: mirrors)
            mirrors.forEach(operations.register)
        }

        @MainActor
        func makeWorkspace() -> WorkspaceModel {
            WorkspaceModel(
                library: library,
                operations: operations,
                windowLayout: layout
            )
        }

        func remove() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func mirror(
        name: String,
        lastSyncedAt: Date? = nil,
        error: String? = nil,
        tags: [String] = []
    ) -> MirrorSnapshot {
        MirrorSnapshot(
            name: name,
            srcURL: "git@github.com:acme/\(name).git",
            dstURL: "git@gitlab.com:acme/\(name).git",
            lastSyncedAt: lastSyncedAt,
            lastSuccessfulSyncedAt: error == nil ? lastSyncedAt : nil,
            lastSyncError: error,
            tags: tags
        )
    }

    @Test func selectionRestoresFromAndPersistsToWindowLayout() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = mirror(name: "first")
        let second = mirror(name: "second")
        try fixture.add([first, second])
        fixture.layout.selectedRepoID = second.id

        let workspace = fixture.makeWorkspace()
        #expect(workspace.selectedMirrorID == second.id)

        workspace.selectMirror(first.id)
        #expect(workspace.selectedMirrorID == first.id)
        #expect(fixture.layout.selectedRepoID == first.id)
    }

    @Test func navigationAndSearchStateSurviveViewRecreation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let value = mirror(name: "mirror")
        try fixture.add([value])
        let workspace = fixture.makeWorkspace()
        workspace.selectMirror(value.id)
        workspace.settingsPane = .storageMaintenance
        workspace.searchText = "production"
        workspace.listFilter = .multipleDestinations
        workspace.sortOrder = .name

        // SwiftUI may recreate ContentView after a locale change; the composed
        // workspace owner remains the same object and therefore keeps state.
        let recreatedViewWorkspace = workspace
        #expect(recreatedViewWorkspace.selectedMirrorID == value.id)
        #expect(recreatedViewWorkspace.settingsPane == .storageMaintenance)
        #expect(recreatedViewWorkspace.searchText == "production")
        #expect(recreatedViewWorkspace.listFilter == .multipleDestinations)
        #expect(recreatedViewWorkspace.sortOrder == .name)
    }

    @Test func filteringAndSortingAreWorkspaceQueries() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let older = mirror(
            name: "Zulu",
            lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tags: ["production"]
        )
        let failed = mirror(
            name: "Alpha",
            lastSyncedAt: Date(timeIntervalSince1970: 1_800_000_000),
            error: "failed",
            tags: ["production"]
        )
        let unrelated = mirror(name: "Beta", tags: ["sandbox"])
        try fixture.add([older, failed, unrelated])
        let workspace = fixture.makeWorkspace()
        workspace.searchText = "production"
        workspace.listFilter = .all
        workspace.selectSmartView(.allMirrors)

        workspace.sortOrder = .name
        #expect(workspace.displayedMirrors.map(\.id) == [failed.id, older.id])

        workspace.sortOrder = .lastSuccess
        #expect(workspace.displayedMirrors.map(\.id) == [older.id, failed.id])
    }

    @Test func smartViewSelectionAndCountsUseLiveFeatureState() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let paused = mirror(name: "paused", tags: ["production"])
        let running = mirror(name: "running", tags: ["production"])
        try fixture.add([paused, running])
        try fixture.library.mutateMirror(id: paused.id) { $0.scheduledSyncPaused = true }
        fixture.operations.suspendSyncEngineForTesting = true
        fixture.operations.triggerSync(mirrorID: running.id)
        let workspace = fixture.makeWorkspace()

        #expect(workspace.count(for: .running) == 1)
        #expect(workspace.count(for: .paused) == 1)
        #expect(workspace.count(for: .label("production")) == 2)

        workspace.selectSmartView(.running)
        #expect(workspace.displayedMirrors.map(\.id) == [running.id])
        #expect(fixture.layout.selectedSmartView == .running)
    }

    @Test func deepLinkRequestsAreValidatedAndConsumedOnce() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let value = mirror(name: "mirror")
        try fixture.add([value])
        let workspace = fixture.makeWorkspace()

        workspace.requestMirrorSelection(UUID())
        #expect(workspace.consumePendingMirrorSelection() == nil)

        workspace.requestEditCredentials(mirrorID: value.id)
        #expect(workspace.pendingMirrorSelectionID == value.id)
        #expect(workspace.consumePendingEditCredentialsMirrorID() == value.id)
        #expect(workspace.consumePendingEditCredentialsMirrorID() == nil)

        workspace.requestOpenSyncLog(mirrorID: value.id)
        #expect(workspace.consumePendingScrollToLogMirrorID() == value.id)
        #expect(workspace.consumePendingMirrorSelection() == value.id)
        #expect(workspace.consumePendingMirrorSelection() == nil)
    }

    @Test func explicitScopeChangesReconcileSelectionButLiveQueriesDoNot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let healthy = mirror(name: "healthy", lastSyncedAt: .now)
        let paused = mirror(name: "paused", lastSyncedAt: .now)
        try fixture.add([healthy, paused])
        try fixture.library.mutateMirror(id: paused.id) { $0.scheduledSyncPaused = true }
        let workspace = fixture.makeWorkspace()
        workspace.selectSmartView(.allMirrors)
        workspace.selectMirror(healthy.id)

        workspace.selectSmartView(.paused)
        #expect(workspace.selectedMirrorID == paused.id)

        workspace.searchText = "missing"
        #expect(workspace.displayedMirrors.isEmpty)
        #expect(workspace.selectedMirrorID == paused.id)
    }

    @Test func deepLinkOutsideCurrentScopeOpensAllMirrorsWithoutLosingIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = mirror(name: "first", lastSyncedAt: .now)
        let paused = mirror(name: "paused", lastSyncedAt: .now)
        try fixture.add([first, paused])
        try fixture.library.mutateMirror(id: paused.id) { $0.scheduledSyncPaused = true }
        let workspace = fixture.makeWorkspace()
        workspace.selectSmartView(.paused)

        workspace.requestMirrorSelection(first.id)

        #expect(workspace.selectedSmartView == .allMirrors)
        #expect(workspace.consumePendingMirrorSelection() == first.id)
    }

    @Test func libraryReconciliationClearsGhostSelectionAndCommandsAreConsumable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let value = mirror(name: "mirror")
        try fixture.add([value])
        let workspace = fixture.makeWorkspace()
        workspace.selectMirror(value.id)
        workspace.requestOpenSyncLog(mirrorID: value.id)
        _ = try fixture.library.remove(id: value.id)

        workspace.reconcileLibrary()
        #expect(workspace.selectedMirrorID == nil)
        #expect(workspace.pendingMirrorSelectionID == nil)
        #expect(workspace.pendingScrollToLogMirrorID == nil)

        workspace.requestOpenAddMirror()
        workspace.requestFocusSearch()
        #expect(workspace.consumePendingOpenAddMirror())
        #expect(!workspace.consumePendingOpenAddMirror())
        #expect(workspace.consumePendingFocusSearch())
        #expect(!workspace.consumePendingFocusSearch())
    }
}
