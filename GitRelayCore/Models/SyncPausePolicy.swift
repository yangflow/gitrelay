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
            return "低电量模式已开启，计划同步已暂停"
        case .expensiveNetwork:
            return "当前为蜂窝热点 / 昂贵网络，计划同步已暂停"
        case .lowPowerAndExpensiveNetwork:
            return "低电量模式且网络昂贵，计划同步已暂停"
        }
    }
}
