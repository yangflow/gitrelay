import Foundation

enum DestructivePushPolicy: String, Codable, CaseIterable, Identifiable {
    case strict
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strict: return String(localized: "Strict Protection")
        case .auto:   return String(localized: "Run Automatically")
        }
    }

    var description: String {
        switch self {
        case .strict:
            return String(localized: "Show a confirmation when the dry run detects ref deletions or forced updates on the target; canceling blocks the sync.")
        case .auto:
            return String(localized: "Continue pushing when deletions or forced updates are detected. Suitable for temporary mirrors or confirmed target repositories.")
        }
    }

    /// strict 策略在 dry-run 发现删除 / 强制更新时需要用户显式确认。
    func requiresConfirmation(for plan: DestructivePushPlan) -> Bool {
        self == .strict && plan.isDestructive
    }
}
