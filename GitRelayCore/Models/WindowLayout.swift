import Foundation

/// Persisted main-window chrome state (UserDefaults only — never `repos.json`).
struct WindowLayout: Equatable, Sendable {
    var selectedRepoID: UUID?
    var detailTab: RepoDetailTab
    /// Sidebar column width in points; clamped to ``DesignTokens.Layout`` sidebar range.
    var sidebarWidth: Double

    static let `default` = WindowLayout(
        selectedRepoID: nil,
        detailTab: .overview,
        sidebarWidth: Double(DesignTokens.Layout.sidebarIdealWidth)
    )

    /// Clamps sidebar width into the DesignTokens sidebar column range.
    static func clampedSidebarWidth(_ width: Double) -> Double {
        let minWidth = Double(DesignTokens.Layout.sidebarMinWidth)
        let maxWidth = Double(DesignTokens.Layout.sidebarMaxWidth)
        return min(max(width, minWidth), maxWidth)
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
