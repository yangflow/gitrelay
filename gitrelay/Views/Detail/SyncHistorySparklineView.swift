import SwiftUI

struct SyncHistorySparklineView: View {
    let sparkline: SyncHistorySparkline

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            legend

            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xxxs) {
                    ForEach(sparkline.days) { day in
                        dayColumn(day, maxHeight: geometry.size.height)
                    }
                }
            }
            .frame(height: 56)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var legend: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            legendItem(title: String.loc("Succeeded"), color: DesignTokens.StatusColor.success)
            legendItem(title: String.loc("Failed"), color: DesignTokens.StatusColor.escalatedFailure)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxxs) {
            Circle()
                .fill(color)
                .frame(width: DesignTokens.Size.statusDot, height: DesignTokens.Size.statusDot)
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
            return String.loc("\(dateText): No Syncs")
        }
        return String.loc("\(dateText): \(day.successes) succeeded, \(day.failures) failed")
    }

    private var accessibilitySummary: String {
        let successes = sparkline.days.reduce(0) { $0 + $1.successes }
        let failures = sparkline.days.reduce(0) { $0 + $1.failures }
        return String.loc("Over the last 30 days, \(successes) succeeded and \(failures) failed")
    }
}
