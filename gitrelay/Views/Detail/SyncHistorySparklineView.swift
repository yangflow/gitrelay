import SwiftUI

struct SyncHistorySparklineView: View {
    let sparkline: SyncHistorySparkline

    private var successCount: Int {
        sparkline.days.reduce(0) { $0 + $1.successes }
    }

    private var failureCount: Int {
        sparkline.days.reduce(0) { $0 + $1.failures }
    }

    private var totalCount: Int { successCount + failureCount }

    var body: some View {
        Group {
            if totalCount == 0 {
                Text(String.loc("No sync activity in the last 30 days"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    legend

                    GeometryReader { geometry in
                        HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xxxs) {
                            ForEach(sparkline.days) { day in
                                dayColumn(day, maxHeight: geometry.size.height)
                            }
                        }
                    }
                    .frame(height: 44)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilitySummary)
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            legendItem(
                title: String.loc("Succeeded"),
                count: successCount,
                color: DesignTokens.StatusColor.success
            )
            legendItem(
                title: String.loc("Failed"),
                count: failureCount,
                color: DesignTokens.StatusColor.escalatedFailure
            )
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxxs) {
            Circle()
                .fill(color)
                .frame(width: DesignTokens.Size.statusDot, height: DesignTokens.Size.statusDot)
            Text(count, format: .number)
                .monospacedDigit()
            Text(title)
        }
    }

    private func dayColumn(_ day: SyncHistorySparkline.Day, maxHeight: CGFloat) -> some View {
        let scale = CGFloat(day.total) / CGFloat(sparkline.maxDailyTotal)
        let columnHeight = max(2, maxHeight * scale)
        let successRatio = day.total == 0 ? 0 : CGFloat(day.successes) / CGFloat(day.total)
        let successHeight = columnHeight * successRatio
        let failureHeight = columnHeight - successHeight

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if failureHeight > 0 {
                    Rectangle()
                        .fill(DesignTokens.StatusColor.escalatedFailure.opacity(day.failures > 0 ? 0.85 : 0.15))
                        .frame(height: failureHeight)
                }
                if successHeight > 0 {
                    Rectangle()
                        .fill(DesignTokens.StatusColor.success.opacity(day.successes > 0 ? 0.85 : 0.15))
                        .frame(height: successHeight)
                }
                if day.total == 0 {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .help(dayHelp(for: day))
    }

    private func dayHelp(for day: SyncHistorySparkline.Day) -> String {
        let dateText = day.date.formatted(.dateTime.month(.abbreviated).day())
        if day.total == 0 {
            return String(format: String.loc("%@: No Syncs"), dateText)
        }
        return String(format: String.loc("%@: %lld succeeded, %lld failed"), dateText, day.successes, day.failures)
    }

    private var accessibilitySummary: String {
        String(
            format: String.loc("Over the last 30 days, %lld succeeded and %lld failed"),
            successCount,
            failureCount
        )
    }
}
