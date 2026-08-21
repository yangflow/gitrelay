import Foundation

/// How the status item renders. The mark never changes: failure tints the same
/// template glyph red instead of swapping in a second symbol (#92).
nonisolated enum MenuBarIconAppearance: Equatable, Sendable {
    case normal
    case failed

    /// One glyph for both states. Replaced wholesale when the Y-branch asset lands.
    static let symbolName = "arrow.triangle.2.circlepath"

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
