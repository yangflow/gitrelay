import SwiftUI

struct FailureCountBadge: View {
    let count: Int

    var body: some View {
        Text(String(localized: "× \(count)"))
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .frame(minWidth: 28, minHeight: 18)
            .background(DesignTokens.Surface.badgeFill, in: .capsule)
            .help(String(localized: "\(count) consecutive failures"))
            .accessibilityLabel(String(localized: "\(count) consecutive failures"))
    }
}
