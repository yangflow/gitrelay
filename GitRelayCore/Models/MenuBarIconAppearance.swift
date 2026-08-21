import Foundation

/// How the status item renders. The mark never changes: failure tints the same
/// Y-branch red instead of swapping in a second symbol (#92).
///
/// The shape itself comes from ``GitRelayMark``, the same geometry the AppIcon is
/// drawn from, so there is no SF Symbol name to pick here.
nonisolated enum MenuBarIconAppearance: Equatable, Sendable {
    case normal
    case failed

    static func make(hasFailure: Bool, hasDivergence: Bool) -> MenuBarIconAppearance {
        hasFailure || hasDivergence ? .failed : .normal
    }

    /// Only the untinted mark follows the menu-bar appearance as a template.
    var isTemplate: Bool { self == .normal }

    /// Stable tint name for tests (no AppKit color equality).
    var tintLabel: String {
        switch self {
        case .normal: return "template"
        case .failed: return "red"
        }
    }
}
