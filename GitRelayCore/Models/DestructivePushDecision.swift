import Foundation

/// What the user chose once the destination turned out to hold a history the
/// source does not share.
nonisolated enum DestructivePushDecision: String, Sendable, Equatable, CaseIterable {
    /// Dismiss and stop the sync, the same outcome the old Cancel button had.
    case cancel
    /// Force-update and delete the destination's refs until it matches the source.
    case overwrite
    /// Push the source refs under the check-branch namespace and leave every
    /// branch the destination already has exactly where it is.
    case checkBranch

    /// False only for `.cancel`, the one choice that never reaches the destination.
    var pushesToDestination: Bool {
        self != .cancel
    }

    /// True while the destination keeps its own branch tips.
    var preservesDestinationBranches: Bool {
        self != .overwrite
    }
}
