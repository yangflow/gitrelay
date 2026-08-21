import SwiftUI

/// Sidebar footer: run state, repo / failure counts, and the scheduled-sync
/// pause control when any repository actually syncs on a frequency.
struct SidebarFooterView: View {
    let summary: SidebarFooterSummary
    let onTogglePause: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Label {
                    Text(summary.stateText)
                        .lineLimit(1)
                } icon: {
                    indicator
                }
                .font(.caption)
                .foregroundStyle(summary.isPaused ? DesignTokens.StatusColor.pause : DesignTokens.StatusColor.success)

                Text(summary.countsText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: DesignTokens.Spacing.xxs)

            if summary.showsPauseControl {
                Button(action: onTogglePause) {
                    Image(systemName: summary.isPaused ? "play.fill" : "pause.fill")
                        .font(.caption)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .help(pauseHelp)
                .accessibilityLabel(pauseHelp)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.sidebarChromeHorizontal)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GitRelayVisualEffectView(
                material: DesignTokens.Material.footer.nsMaterial,
                blendingMode: DesignTokens.Material.footer.blendingMode
            )
        }
    }

    @ViewBuilder
    private var indicator: some View {
        if summary.isPaused {
            Image(systemName: "pause.circle.fill")
        } else {
            Circle()
                .fill(DesignTokens.StatusColor.success)
                .frame(
                    width: DesignTokens.Size.runIndicatorDot,
                    height: DesignTokens.Size.runIndicatorDot
                )
        }
    }

    private var pauseHelp: String {
        summary.isPaused
            ? String(localized: "Resume Scheduled Sync")
            : String(localized: "Pause Scheduled Sync")
    }
}
