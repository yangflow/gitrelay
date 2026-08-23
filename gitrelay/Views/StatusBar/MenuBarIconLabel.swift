import SwiftUI
import AppKit

struct MenuBarIconLabel: View {
    let mirrors: [MirrorSnapshot]
    let statuses: [UUID: SyncStatus]

    var body: some View {
        Image(nsImage: icon)
            .renderingMode(appearance.isTemplate ? .template : .original)
    }

    private var appearance: MenuBarIconAppearance {
        MenuBarIconAppearance.make(
            hasFailure: statuses.values.contains {
                if case .failed = $0 { true } else { false }
            },
            hasDivergence: statuses.values.contains {
                if case .diverged = $0 { true } else { false }
            } || mirrors.contains(where: \.isDiverged)
        )
    }

    private var icon: NSImage {
        switch appearance {
        case .normal: return Self.normalIcon
        case .failed: return Self.failedIcon
        }
    }

    /// Same merge-arrow in both states. Failure tints it red rather than swapping
    /// in a second glyph, and a tinted mark has to drop template rendering to keep
    /// the color.
    private static let normalIcon = MenuBarBranchMark.image(
        pointSize: DesignTokens.Size.menuBarIconPointSize,
        color: nil,
        strokeScale: DesignTokens.Size.menuBarStrokeScale
    )
    private static let failedIcon = MenuBarBranchMark.image(
        pointSize: DesignTokens.Size.menuBarIconPointSize,
        color: .systemRed,
        strokeScale: DesignTokens.Size.menuBarStrokeScale
    )
}
