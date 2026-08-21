import SwiftUI

/// Quiet 1–2–3 rail above the browse-remote wizard.
///
/// Numbers and hairline connectors only: the step count is locked at three, so
/// the rail never needs labels or a progress percentage.
struct BrowseRemoteStepBar: View {
    let current: BrowseRemoteStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BrowseRemoteStep.allCases) { step in
                if !step.isFirst {
                    connector
                }
                marker(for: step)
            }
        }
        .frame(maxWidth: DesignTokens.Layout.browseStepBarMaxWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current.progressLabel)
    }

    private var connector: some View {
        Rectangle()
            .fill(DesignTokens.Surface.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .accessibilityHidden(true)
    }

    private func marker(for step: BrowseRemoteStep) -> some View {
        let isCurrent = step == current
        let isReached = step.number <= current.number
        return Text(String(step.number))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isCurrent ? Color.white : Color.secondary)
            .frame(
                width: DesignTokens.Size.stepMarker,
                height: DesignTokens.Size.stepMarker
            )
            .background {
                Circle()
                    .fill(isCurrent ? Color.accentColor : DesignTokens.Surface.chipFill)
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        isReached && !isCurrent ? Color.accentColor.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            }
    }
}
