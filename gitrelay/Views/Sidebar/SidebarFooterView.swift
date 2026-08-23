import SwiftUI

/// Sidebar footer: run state, repo / failure counts, and the scheduled-sync
/// pause control when any repository actually syncs on a frequency.
struct SidebarFooterView: View {
    let summary: SidebarFooterSummary
    let onTogglePause: () -> Void

    private var statusColor: Color {
        summary.isPaused ? DesignTokens.StatusColor.pause : DesignTokens.StatusColor.success
    }

    private var stateText: String {
        switch summary.pauseReason {
        case nil:
            String.loc("Running")
        case .manual:
            String.loc("Scheduled sync paused")
        case .quietHours:
            String.loc("Quiet hours")
        case .lowPowerMode:
            String.loc("Low Power Mode is on; scheduled sync is paused")
        case .expensiveNetwork:
            String.loc("The current network is a cellular hotspot or an expensive network; scheduled sync is paused")
        case .lowPowerAndExpensiveNetwork:
            String.loc("Low Power Mode is on and the network is expensive; scheduled sync is paused")
        }
    }

    private var countsText: String {
        String(
            format: String.loc("%lld mirrors · %lld failed"),
            Int64(summary.repoCount),
            Int64(summary.failedCount)
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxs) {
                Label {
                    Text(stateText)
                        .lineLimit(1)
                } icon: {
                    indicator
                }
                .font(.caption)
                .foregroundStyle(statusColor)

                Text(countsText)
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
    }

    @ViewBuilder
    private var indicator: some View {
        if summary.isPaused {
            Image(systemName: "pause.circle.fill")
        } else {
            Circle()
                .fill(statusColor)
                .frame(
                    width: DesignTokens.Size.runIndicatorDot,
                    height: DesignTokens.Size.runIndicatorDot
                )
        }
    }

    private var pauseHelp: String {
        summary.isPaused
            ? String.loc("Resume Scheduled Sync")
            : String.loc("Pause Scheduled Sync")
    }
}
