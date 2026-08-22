import Foundation

nonisolated enum SyncFrequency: String, Codable, CaseIterable, Identifiable {
    case manual = "手动"
    case min15  = "每 15 分钟"
    case min30  = "每 30 分钟"
    case hour1  = "每小时"
    case day1   = "每天"

    var id: String { rawValue }

    /// Localized label for UI. Raw values stay Chinese for Codable compatibility.
    var displayName: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .min15:  String(localized: "Every 15 Minutes")
        case .min30:  String(localized: "Every 30 Minutes")
        case .hour1:  String(localized: "Hourly")
        case .day1:   String(localized: "Daily")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .min15:  return 900
        case .min30:  return 1800
        case .hour1:  return 3600
        case .day1:   return 86400
        }
    }
}
