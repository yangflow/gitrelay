import SwiftUI
import AppKit

struct MenuBarIconLabel: View {
    let appVM: AppViewModel

    var body: some View {
        Image(nsImage: appVM.hasAnyFailure ? Self.failedIcon : Self.normalIcon)
    }

    private static let normalIcon: NSImage = makeIcon(name: "arrow.triangle.2.circlepath")
    private static let failedIcon: NSImage = makeIcon(name: "exclamationmark.triangle.fill")

    private static func makeIcon(name: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "GitRelay")?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
