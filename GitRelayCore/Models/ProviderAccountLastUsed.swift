import Foundation

/// The 最后使用 cell for one saved account: whether there is anything to say,
/// and the relative phrase to say it with (昨天 / 3 小时前).
///
/// Which of the three the timestamp falls into is decided here so it can be
/// checked without a locale; the phrase itself is left to Foundation, the same
/// way the pair table renders 上次.
nonisolated enum ProviderAccountLastUsed: Equatable, Sendable {
    case never
    /// Recent enough to read as 刚刚 — including a timestamp a skewed clock
    /// left slightly in the future.
    case justNow
    case at(Date)

    /// Anything this fresh reads better as 刚刚 than as "in 0 seconds".
    static let justNowWindow: TimeInterval = 60

    static func state(for lastUsedAt: Date?, now: Date = Date()) -> ProviderAccountLastUsed {
        guard let lastUsedAt else { return .never }
        guard now.timeIntervalSince(lastUsedAt) >= justNowWindow else { return .justNow }
        return .at(lastUsedAt)
    }

    var text: String {
        switch self {
        case .never:
            return String(localized: "Never used")
        case .justNow:
            return String(localized: "Just now")
        case .at(let date):
            return date.formatted(.relative(presentation: .named))
        }
    }
}
