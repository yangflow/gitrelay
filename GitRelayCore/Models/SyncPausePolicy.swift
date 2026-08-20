import Foundation

/// Decides whether scheduled syncs should pause based on power / network / quiet hours.
struct SyncPausePolicy: Equatable, Sendable {
    var pauseOnLowPowerMode: Bool
    var pauseOnExpensiveNetwork: Bool
    var quietHours: QuietHoursSettings

    init(
        pauseOnLowPowerMode: Bool,
        pauseOnExpensiveNetwork: Bool,
        quietHours: QuietHoursSettings = .default
    ) {
        self.pauseOnLowPowerMode = pauseOnLowPowerMode
        self.pauseOnExpensiveNetwork = pauseOnExpensiveNetwork
        self.quietHours = quietHours
    }

    func shouldPause(
        isLowPowerMode: Bool,
        isExpensiveNetwork: Bool,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        pauseReason(
            isLowPowerMode: isLowPowerMode,
            isExpensiveNetwork: isExpensiveNetwork,
            date: date,
            calendar: calendar
        ) != nil
    }

    func pauseReason(
        isLowPowerMode: Bool,
        isExpensiveNetwork: Bool,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> SyncPauseReason? {
        // Quiet hours take precedence for the menu-bar “Quiet hours / 静默中” state.
        if quietHours.contains(date, calendar: calendar) {
            return .quietHours
        }

        let lowPower = pauseOnLowPowerMode && isLowPowerMode
        let expensive = pauseOnExpensiveNetwork && isExpensiveNetwork
        switch (lowPower, expensive) {
        case (true, true): return .lowPowerAndExpensiveNetwork
        case (true, false): return .lowPowerMode
        case (false, true): return .expensiveNetwork
        case (false, false): return nil
        }
    }
}

enum SyncPauseReason: Equatable, Sendable {
    case quietHours
    case lowPowerMode
    case expensiveNetwork
    case lowPowerAndExpensiveNetwork

    var displayMessage: String {
        switch self {
        case .quietHours:
            return String(localized: "Quiet hours")
        case .lowPowerMode:
            return String(localized: "Low Power Mode is on; scheduled sync is paused")
        case .expensiveNetwork:
            return String(localized: "The current network is a cellular hotspot or an expensive network; scheduled sync is paused")
        case .lowPowerAndExpensiveNetwork:
            return String(localized: "Low Power Mode is on and the network is expensive; scheduled sync is paused")
        }
    }

    var isQuietHours: Bool {
        if case .quietHours = self { return true }
        return false
    }
}
