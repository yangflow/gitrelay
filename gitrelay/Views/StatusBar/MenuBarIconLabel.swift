import SwiftUI
import AppKit

struct MenuBarIconLabel: View {
    let appVM: AppViewModel

    var body: some View {
        Image(nsImage: icon)
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

    private static let normalIcon: NSImage = makeIcon(appearance: .normal)
    private static let failedIcon: NSImage = makeIcon(appearance: .failed)

    /// Same mark in both states. Failure tints it red rather than swapping in a
    /// second glyph, so a red template image drops out of template rendering.
    private static func makeIcon(appearance: MenuBarIconAppearance) -> NSImage {
        var config = NSImage.SymbolConfiguration(
            pointSize: DesignTokens.Size.menuBarIconPointSize,
            weight: .semibold
        )
        if !appearance.isTemplate {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.systemRed]))
        }
        let image = NSImage(
            systemSymbolName: MenuBarIconAppearance.symbolName,
            accessibilityDescription: "GitRelay"
        )?.withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = appearance.isTemplate
        return image
    }
}
