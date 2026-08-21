import Foundation

/// Persisted main-window chrome state (UserDefaults only — never `repos.json`).
///
/// Sidebar width bounds mirror ``DesignTokens.Layout`` (200…300, ideal 240).
/// Literals are used here so `gitrelayctl` can compile without DesignTokens.
struct WindowLayout: Equatable, Sendable {
    /// Matches `DesignTokens.Layout.sidebarMinWidth`.
    static let sidebarMinWidth: Double = 200
    /// Matches `DesignTokens.Layout.sidebarIdealWidth`.
    static let sidebarIdealWidth: Double = 240
    /// Matches `DesignTokens.Layout.sidebarMaxWidth`.
    static let sidebarMaxWidth: Double = 300

    var selectedRepoID: UUID?
    var detailTab: RepoDetailTab
    /// Sidebar column width in points; clamped to ``sidebarMinWidth``…``sidebarMaxWidth``.
    var sidebarWidth: Double

    static let `default` = WindowLayout(
        selectedRepoID: nil,
        detailTab: .overview,
        sidebarWidth: sidebarIdealWidth
    )

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
