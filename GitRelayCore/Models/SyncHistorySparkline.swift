import Foundation

nonisolated struct SyncHistorySparkline: Equatable, Sendable {
    struct Day: Equatable, Identifiable {
        let date: Date
        let successes: Int
        let failures: Int

        var id: Date { date }

        var total: Int {
            successes + failures
        }
    }

    let days: [Day]

    static let defaultDayCount = 30

    nonisolated static func make(
        from dailyOutcomes: [String: SyncDayOutcome],
        now: Date? = nil,
        calendar: Calendar? = nil,
        dayCount: Int = defaultDayCount
    ) -> SyncHistorySparkline {
        let calendar = calendar ?? Calendar(identifier: .gregorian)
        let now = now ?? Date()
        let normalizedDayCount = max(1, dayCount)
        let endDay = calendar.startOfDay(for: now)
        let days = (0 ..< normalizedDayCount).compactMap { offset -> Day? in
            guard let date = calendar.date(
                byAdding: .day,
                value: -(normalizedDayCount - 1 - offset),
                to: endDay
            ) else {
                return nil
            }

            let key = dayKey(for: date, calendar: calendar)
            let outcome = dailyOutcomes[key] ?? SyncDayOutcome()
            return Day(date: date, successes: outcome.successes, failures: outcome.failures)
        }

        return SyncHistorySparkline(days: days)
    }

    nonisolated static func make(
        from records: [SyncRecord],
        now: Date? = nil,
        calendar: Calendar? = nil,
        dayCount: Int = defaultDayCount
    ) -> SyncHistorySparkline {
        let calendar = calendar ?? Calendar(identifier: .gregorian)
        let now = now ?? Date()
        var dailyOutcomes: [String: SyncDayOutcome] = [:]

        for record in records {
            let finishedAt = record.finishedAt ?? record.startedAt
            let key = dayKey(for: finishedAt, calendar: calendar)
            var outcome = dailyOutcomes[key] ?? SyncDayOutcome()
            if record.succeeded {
                outcome.successes += 1
            } else {
                outcome.failures += 1
            }
            dailyOutcomes[key] = outcome
        }

        return make(from: dailyOutcomes, now: now, calendar: calendar, dayCount: dayCount)
    }

    var maxDailyTotal: Int {
        max(days.map(\.total).max() ?? 0, 1)
    }

    nonisolated static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated static func pruneDailyOutcomes(
        _ outcomes: [String: SyncDayOutcome],
        keepingDays: Int,
        referenceDate: Date,
        calendar: Calendar? = nil
    ) -> [String: SyncDayOutcome] {
        let calendar = calendar ?? Calendar(identifier: .gregorian)
        guard keepingDays > 0 else { return [:] }
        guard let cutoff = calendar.date(
            byAdding: .day,
            value: -(keepingDays - 1),
            to: calendar.startOfDay(for: referenceDate)
        ) else {
            return outcomes
        }

        return outcomes.filter { key, _ in
            guard let date = date(fromDayKey: key, calendar: calendar) else { return false }
            return date >= cutoff
        }
    }

    nonisolated private static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}
