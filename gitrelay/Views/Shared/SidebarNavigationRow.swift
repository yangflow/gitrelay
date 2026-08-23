import SwiftUI

/// Shared navigation-row visual for both the workspace and Settings sidebars.
/// Selection remains native to `List`; only the icon tile, spacing, and count
/// treatment live here so the two windows cannot drift apart again.
struct SidebarNavigationRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var count: Int?

    init(
        title: String,
        systemImage: String,
        tint: Color,
        count: Int? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.count = count
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: DesignTokens.Size.sidebarIconPointSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .frame(
                    width: DesignTokens.Size.sidebarIconTile,
                    height: DesignTokens.Size.sidebarIconTile
                )
                .background(tint.opacity(0.11))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.CornerRadius.control,
                        style: .continuous
                    )
                )
                .accessibilityHidden(true)

            Text(title)
                .lineLimit(1)

            Spacer(minLength: DesignTokens.Spacing.xs)

            if let count {
                Text(count, format: .number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
