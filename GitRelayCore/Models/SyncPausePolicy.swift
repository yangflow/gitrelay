import Foundation

/// Decides whether scheduled syncs should pause based on power / network conditions.
struct SyncPausePolicy: Equatable, Sendable {
    var pauseOnLowPowerMode: Bool
    var pauseOnExpensiveNetwork: Bool

    func shouldPause(isLowPowerMode: Bool, isExpensiveNetwork: Bool) -> Bool {
        pauseReason(isLowPowerMode: isLowPowerMode, isExpensiveNetwork: isExpensiveNetwork) != nil
    }

    func pauseReason(isLowPowerMode: Bool, isExpensiveNetwork: Bool) -> SyncPauseReason? {
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
    case lowPowerMode
    case expensiveNetwork
    case lowPowerAndExpensiveNetwork

    var displayMessage: String {
        switch self {
        case .lowPowerMode:
            return "Low Power Mode is on; scheduled sync is paused"
        case .expensiveNetwork:
            return "The current network is a cellular hotspot or an expensive network; scheduled sync is paused"
        case .lowPowerAndExpensiveNetwork:
            return "Low Power Mode is on and the network is expensive; scheduled sync is paused"
        }
    }
}
