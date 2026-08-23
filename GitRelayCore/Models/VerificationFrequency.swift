import Foundation

nonisolated enum VerificationFrequency: String, Codable, CaseIterable, Identifiable {
    case manual = "手动"
    case day1 = "每天"
    case week1 = "每周"
    case month1 = "每月"

    var id: String { rawValue }

    /// Localized label for UI. Raw values stay Chinese for Codable compatibility.
    var displayName: String {
        switch self {
        case .manual: String(localized: "Manual")
        case .day1:   String(localized: "Daily")
        case .week1:  String(localized: "Weekly")
        case .month1: String(localized: "Monthly")
        }
    }

    var interval: TimeInterval? {
        switch self {
        case .manual: return nil
        case .day1:   return 86_400
        case .week1:  return 604_800
        case .month1: return 2_592_000
        }
    }
}
