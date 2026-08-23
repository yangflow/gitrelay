import Foundation
import Observation

/// Stable main-window state. It survives view recreation (including language
/// changes) and owns navigation intent without owning persistence or engines.
@MainActor
@Observable
final class WorkspaceModel {
    let library: MirrorLibraryModel
    let operations: MirrorOperationsController
    let scheduling: MirrorSchedulingController
    let windowLayout: WindowLayoutStore

    private(set) var selectedSmartView: MirrorSmartView {
        didSet {
            guard selectedSmartView != oldValue else { return }
            windowLayout.selectedSmartView = selectedSmartView
        }
    }
    var settingsPane: SettingsPane = .general
    var searchText = ""
    var listFilter: MirrorListFilter = .all
    var sortOrder: MirrorListSortOrder = .priority

    var selectedMirrorID: UUID? {
        didSet {
            guard selectedMirrorID != oldValue else { return }
            windowLayout.selectedRepoID = selectedMirrorID
        }
    }

    private(set) var pendingMirrorSelectionID: UUID?
    private(set) var pendingEditCredentialsMirrorID: UUID?
    private(set) var pendingScrollToLogMirrorID: UUID?
    private(set) var pendingOpenAddMirror = false
    private(set) var addMirrorPrefill: RepoSourceDropPrefill?
    private(set) var addMirrorRequestID = UUID()
    private(set) var pendingFocusSearch = false

    init(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        scheduling: MirrorSchedulingController? = nil,
        windowLayout: WindowLayoutStore? = nil
    ) {
        self.library = library
        self.operations = operations
        let resolvedScheduling = scheduling ?? MirrorSchedulingController(
            library: library,
            operations: operations
        )
        self.scheduling = resolvedScheduling
        let windowLayout = windowLayout ?? WindowLayoutStore()
        self.windowLayout = windowLayout
        windowLayout.reconcileSelection(withExistingIDs: Set(library.mirrors.map(\.id)))
        self.selectedMirrorID = windowLayout.selectedRepoID
        let contexts = Self.makeSmartViewContexts(
            library: library,
            operations: operations,
            scheduling: resolvedScheduling
        )
        self.selectedSmartView = MirrorSmartViewQuery.reconciledSelection(
            windowLayout.selectedSmartView,
            in: contexts
        )
        windowLayout.selectedSmartView = selectedSmartView
    }

    var smartViewContexts: [MirrorSmartViewContext] {
        Self.makeSmartViewContexts(
            library: library,
            operations: operations,
            scheduling: scheduling
        )
    }

    var availableSmartViews: [MirrorSmartView] {
        MirrorSmartViewQuery.availableViews(in: smartViewContexts)
    }

    var labelSmartViews: [MirrorSmartView] {
        availableSmartViews.filter {
            if case .label = $0 { return true }
            return false
        }
    }

    func count(for smartView: MirrorSmartView) -> Int {
        MirrorSmartViewQuery.count(for: smartView, in: smartViewContexts)
    }

    var displayedMirrorRows: [MirrorListRow] {
        let includedIDs = MirrorSmartViewQuery.mirrorIDs(
            in: selectedSmartView,
            contexts: smartViewContexts
        )
        let rows = library.mirrors.compactMap { mirror -> MirrorListRow? in
            guard includedIDs.contains(mirror.id) else { return nil }
            return MirrorListProjection.row(
                for: mirror,
                activity: operations.activity(mirrorID: mirror.id),
                schedule: Self.scheduleState(for: mirror, scheduling: scheduling)
            )
        }
        let filtered = MirrorListProjection.filter(
            rows,
            searchText: searchText,
            filter: listFilter
        )
        return MirrorListProjection.sort(filtered, order: sortOrder)
    }

    var displayedMirrors: [MirrorSnapshot] {
        displayedMirrorRows.compactMap { library.mirror(id: $0.id) }
    }

    func selectMirror(_ mirrorID: UUID?) {
        guard let mirrorID else {
            selectedMirrorID = nil
            return
        }
        guard library.mirror(id: mirrorID) != nil else { return }
        selectedMirrorID = mirrorID
    }

    func selectSmartView(_ smartView: MirrorSmartView) {
        guard availableSmartViews.contains(smartView) else { return }
        selectedSmartView = smartView
        reconcileSelectionForExplicitScopeChange()
    }

    func reconcileLibrary() {
        let existingIDs = Set(library.mirrors.map(\.id))
        windowLayout.reconcileSelection(withExistingIDs: existingIDs)
        if let selectedMirrorID, !existingIDs.contains(selectedMirrorID) {
            self.selectedMirrorID = nil
        }
        if let pendingMirrorSelectionID, !existingIDs.contains(pendingMirrorSelectionID) {
            self.pendingMirrorSelectionID = nil
        }
        if let pendingEditCredentialsMirrorID,
           !existingIDs.contains(pendingEditCredentialsMirrorID) {
            self.pendingEditCredentialsMirrorID = nil
        }
        if let pendingScrollToLogMirrorID,
           !existingIDs.contains(pendingScrollToLogMirrorID) {
            self.pendingScrollToLogMirrorID = nil
        }
        selectedSmartView = MirrorSmartViewQuery.reconciledSelection(
            selectedSmartView,
            in: smartViewContexts
        )
    }

    func requestMirrorSelection(_ mirrorID: UUID?) {
        guard let mirrorID else {
            pendingMirrorSelectionID = nil
            return
        }
        guard library.mirror(id: mirrorID) != nil else { return }
        let visibleIDs = MirrorSmartViewQuery.mirrorIDs(
            in: selectedSmartView,
            contexts: smartViewContexts
        )
        if !visibleIDs.contains(mirrorID) {
            selectedSmartView = .allMirrors
        }
        pendingMirrorSelectionID = mirrorID
    }

    func consumePendingMirrorSelection() -> UUID? {
        defer { pendingMirrorSelectionID = nil }
        return pendingMirrorSelectionID
    }

    func requestEditCredentials(mirrorID: UUID) {
        guard library.mirror(id: mirrorID) != nil else { return }
        pendingEditCredentialsMirrorID = mirrorID
        pendingMirrorSelectionID = mirrorID
    }

    func consumePendingEditCredentialsMirrorID() -> UUID? {
        defer { pendingEditCredentialsMirrorID = nil }
        return pendingEditCredentialsMirrorID
    }

    func requestOpenSyncLog(mirrorID: UUID) {
        guard library.mirror(id: mirrorID) != nil else { return }
        pendingScrollToLogMirrorID = mirrorID
        pendingMirrorSelectionID = mirrorID
    }

    func consumePendingScrollToLogMirrorID() -> UUID? {
        defer { pendingScrollToLogMirrorID = nil }
        return pendingScrollToLogMirrorID
    }

    func requestOpenAddMirror(prefill: RepoSourceDropPrefill? = nil) {
        addMirrorPrefill = prefill
        addMirrorRequestID = UUID()
        pendingOpenAddMirror = true
    }

    func consumePendingOpenAddMirror() -> Bool {
        guard pendingOpenAddMirror else { return false }
        pendingOpenAddMirror = false
        return true
    }

    func requestFocusSearch() {
        pendingFocusSearch = true
    }

    func consumePendingFocusSearch() -> Bool {
        guard pendingFocusSearch else { return false }
        pendingFocusSearch = false
        return true
    }

    private static func makeSmartViewContexts(
        library: MirrorLibraryModel,
        operations: MirrorOperationsController,
        scheduling: MirrorSchedulingController
    ) -> [MirrorSmartViewContext] {
        library.mirrors.map { mirror in
            MirrorSmartViewContext(
                mirrorID: mirror.id,
                labels: mirror.tags,
                health: MirrorHealth.derive(
                    plan: mirror.plan,
                    snapshot: mirror.health,
                    staleAfter: Date().addingTimeInterval(-MirrorListProjection.staleInterval)
                ),
                activity: operations.activity(mirrorID: mirror.id),
                schedule: scheduleState(for: mirror, scheduling: scheduling),
                needsCredentials: mirror.needsCredentials
            )
        }
    }

    private func reconcileSelectionForExplicitScopeChange() {
        let scopedIDs = MirrorSmartViewQuery.mirrorIDs(
            in: selectedSmartView,
            contexts: smartViewContexts
        )
        if let selectedMirrorID, scopedIDs.contains(selectedMirrorID) {
            return
        }
        selectedMirrorID = displayedMirrorRows.first?.id
    }

    private static func scheduleState(
        for mirror: MirrorSnapshot,
        scheduling: MirrorSchedulingController
    ) -> MirrorScheduleState {
        if mirror.scheduledSyncPaused {
            return .mirrorPaused
        }
        guard mirror.frequency != .manual,
              let pauseReason = scheduling.pauseReason else {
            return .active(nextRunAt: scheduling.nextFireDate(mirrorID: mirror.id))
        }
        let reason = globalPauseReason(pauseReason)
        return pauseReason == .manual
            ? .globallyPaused(reason)
            : .deferred(reason)
    }

    private static func globalPauseReason(
        _ reason: SyncPauseReason
    ) -> MirrorGlobalPauseReason {
        switch reason {
        case .manual:
            .manual
        case .quietHours:
            .quietHours
        case .lowPowerMode:
            .lowPower
        case .expensiveNetwork:
            .expensiveNetwork
        case .lowPowerAndExpensiveNetwork:
            .lowPowerAndExpensiveNetwork
        }
    }
}
