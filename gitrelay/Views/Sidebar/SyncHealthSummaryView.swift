import SwiftUI

struct SyncHealthSummaryView: View {
    let summary: SyncHealthSummary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.md) {
                title
                Spacer(minLength: DesignTokens.Spacing.xxs)
                metrics
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                title
                metrics
            }
        }
        .font(.caption)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Label(String(localized: "Today"), systemImage: "calendar")
            .foregroundStyle(.secondary)
    }

    private var metrics: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            HealthMetricView(
                title: String(localized: "Succeeded"),
                count: summary.succeededToday,
                systemImage: "checkmark.circle.fill",
                tint: DesignTokens.StatusColor.idle
            )
            HealthMetricView(
                title: String(localized: "Failed"),
                count: summary.failedToday,
                systemImage: "xmark.octagon.fill",
                tint: summary.hasFailures
                    ? DesignTokens.StatusColor.escalatedFailure
                    : .secondary
            )
            HealthMetricView(
                title: String(localized: "Not Run"),
                count: summary.notRunToday,
                systemImage: "clock",
                tint: .secondary
            )
        }
    }
}

private struct HealthMetricView: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text("\(title) \(count)")
                .monospacedDigit()
                .minimumScaleFactor(0.82)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }
}
