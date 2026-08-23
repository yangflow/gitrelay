import Foundation

/// Persisted main-window chrome state stored only in UserDefaults, never in Mirror plans.
///
/// Sidebar width bounds mirror ``DesignTokens.Layout`` (180…240, ideal 200).
/// Literals are used here so `gitrelayctl` can compile without DesignTokens.
struct WindowLayout: Equatable, Sendable {
    /// Matches `DesignTokens.Layout.sidebarMinWidth`.
    static let sidebarMinWidth: Double = 180
    /// Matches `DesignTokens.Layout.sidebarIdealWidth`.
    static let sidebarIdealWidth: Double = 200
    /// Matches `DesignTokens.Layout.sidebarMaxWidth`.
    static let sidebarMaxWidth: Double = 240

    var selectedRepoID: UUID?
    var selectedSmartView: MirrorSmartView?
    var detailTab: RepoDetailTab
    /// Sidebar column width in points; clamped to ``sidebarMinWidth``…``sidebarMaxWidth``.
    var sidebarWidth: Double
    static let `default` = WindowLayout(
        selectedRepoID: nil,
        selectedSmartView: nil,
        detailTab: .overview,
        sidebarWidth: sidebarIdealWidth
    )

    init(
        selectedRepoID: UUID?,
        selectedSmartView: MirrorSmartView? = nil,
        detailTab: RepoDetailTab,
        sidebarWidth: Double
    ) {
        self.selectedRepoID = selectedRepoID
        self.selectedSmartView = selectedSmartView
        self.detailTab = detailTab
        self.sidebarWidth = sidebarWidth
    }

    /// Clamps sidebar width into the allowed column range.
    static func clampedSidebarWidth(_ width: Double) -> Double {
        min(max(width, sidebarMinWidth), sidebarMaxWidth)
    }

    /// Returns a copy with selection cleared when `selectedRepoID` is absent from `existingIDs`.
    func reconciled(withExistingIDs existingIDs: Set<UUID>) -> WindowLayout {
        guard let id = selectedRepoID else { return self }
        guard existingIDs.contains(id) else {
            var copy = self
            copy.selectedRepoID = nil
            return copy
        }
        return self
    }
}
