import SwiftUI

/// The one quiet line under the popover search field (#107): a dot and a
/// sentence fragment, never a banner.
struct MenuBarStatusLineView: View {
    let line: MenuBarStatusLine

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.statusDotGap) {
            Circle()
                .fill(DesignTokens.StatusColor.forMenuBarStatusTone(line.tone))
                .frame(
                    width: DesignTokens.Size.statusDot,
                    height: DesignTokens.Size.statusDot
                )
                .accessibilityHidden(true)
            Text(line.message)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
