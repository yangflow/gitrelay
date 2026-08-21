import Foundation

/// Segmented detail tabs on the main-window repo detail pane.
enum RepoDetailTab: String, CaseIterable, Identifiable, Codable, Sendable {
    case overview
    case releases

    var id: String { rawValue }
}
