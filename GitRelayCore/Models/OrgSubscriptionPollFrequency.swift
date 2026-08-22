import Foundation

/// How often org/group subscriptions are polled for newly added remote repositories.
enum OrgSubscriptionPollFrequency: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual = "手动"
    case day1 = "每天"
    case week1 = "每周"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: String.loc("Manual")
        case .day1:   String.loc("Daily")
        case .week1:  String.loc("Weekly")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .day1:   return 86_400
        case .week1:  return 604_800
        }
    }
}
