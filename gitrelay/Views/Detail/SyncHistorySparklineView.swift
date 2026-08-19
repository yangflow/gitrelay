import SwiftUI

struct SyncHistorySparklineView: View {
    let sparkline: SyncHistorySparkline

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Syncs in the Last 30 Days")
                    .font(.headline)
                Spacer()
                legend
            }

            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 2) {
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
        HStack(spacing: 10) {
            legendItem(title: "Succeeded", color: .green)
            legendItem(title: "Failed", color: .red)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(title: String, color: Color) -> some View {
        Label(title, systemImage: "square.fill")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(color)
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
                        .fill(Color.red.opacity(day.failures > 0 ? 0.85 : 0.15))
                        .frame(height: failureHeight)
                }
                if successHeight > 0 {
                    Rectangle()
                        .fill(Color.green.opacity(day.successes > 0 ? 0.85 : 0.15))
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
            return "\(dateText): No Syncs"
        }
        return "\(dateText): \(day.successes) succeeded, \(day.failures) failed"
    }

    private var accessibilitySummary: String {
        let successes = sparkline.days.reduce(0) { $0 + $1.successes }
        let failures = sparkline.days.reduce(0) { $0 + $1.failures }
        return "Over the last 30 days, \(successes) succeeded and \(failures) failed"
    }
}
