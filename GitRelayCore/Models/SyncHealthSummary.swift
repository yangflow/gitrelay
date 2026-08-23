import Foundation

struct SyncHealthSummary: Equatable {
    let succeededToday: Int
    let failedToday: Int
    let notRunToday: Int

    var total: Int {
        succeededToday + failedToday + notRunToday
    }

    var hasFailures: Bool {
        failedToday > 0
    }

    static func make(
        repos: [MirrorSnapshot],
        statuses: [UUID: SyncStatus],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SyncHealthSummary {
        var succeededToday = 0
        var failedToday = 0
        var notRunToday = 0

        for repo in repos {
            guard isSameDay(repo.lastSyncedAt, as: now, calendar: calendar) else {
                notRunToday += 1
                continue
            }

            if repo.lastSyncError != nil || isFailed(statuses[repo.id]) {
                failedToday += 1
            } else if isSameDay(repo.lastSuccessfulSyncedAt, as: now, calendar: calendar) {
                succeededToday += 1
            } else {
                notRunToday += 1
            }
        }

        return SyncHealthSummary(
            succeededToday: succeededToday,
            failedToday: failedToday,
            notRunToday: notRunToday
        )
    }

    private static func isSameDay(_ date: Date?, as referenceDate: Date, calendar: Calendar) -> Bool {
        guard let date else { return false }
        return calendar.isDate(date, inSameDayAs: referenceDate)
    }

    private static func isFailed(_ status: SyncStatus?) -> Bool {
        if case .failed = status {
            return true
        }
        return false
    }
}
