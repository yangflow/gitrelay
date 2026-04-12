import Foundation

enum SyncFrequency: String, Codable, CaseIterable, Identifiable {
    case manual = "手动"
    case min15  = "每 15 分钟"
    case min30  = "每 30 分钟"
    case hour1  = "每小时"
    case day1   = "每天"

    var id: String { rawValue }

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
