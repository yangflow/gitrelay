import SwiftUI
import AppKit

struct MenuBarIconLabel: View {
    let appVM: AppViewModel

    var body: some View {
        Image(nsImage: icon)
            .renderingMode(appearance.isTemplate ? .template : .original)
    }

    private var appearance: MenuBarIconAppearance {
        MenuBarIconAppearance.make(
            hasFailure: appVM.hasAnyFailure,
            hasDivergence: appVM.hasAnyDivergence
        )
    }

    private var icon: NSImage {
        switch appearance {
        case .normal: return Self.normalIcon
        case .failed: return Self.failedIcon
        }
    }

    /// Same Y-branch in both states. Failure tints it red rather than swapping in
    /// a second glyph, and a tinted mark has to drop template rendering to keep
    /// the color.
    private static let normalIcon = MenuBarBranchMark.image(
        pointSize: DesignTokens.Size.menuBarIconPointSize,
        color: nil
    )
    private static let failedIcon = MenuBarBranchMark.image(
        pointSize: DesignTokens.Size.menuBarIconPointSize,
        color: .systemRed
    )
}
