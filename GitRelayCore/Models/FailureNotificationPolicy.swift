import Foundation

/// Pure policy for whether a sync failure should raise an external notification.
///
/// Suppresses transient blips by notifying only on the first failure of a streak
/// (optional) and/or when consecutive failures hit the configured threshold
/// (and multiples of that threshold).
struct FailureNotificationPolicy: Equatable, Sendable {
    var isEnabled: Bool
    var notifyOnFirstFailure: Bool
    /// Minimum 1. When count is a positive multiple of this value, notify.
    var consecutiveFailureThreshold: Int

    init(
        isEnabled: Bool = true,
        notifyOnFirstFailure: Bool = true,
        consecutiveFailureThreshold: Int = 3
    ) {
        self.isEnabled = isEnabled
        self.notifyOnFirstFailure = notifyOnFirstFailure
        self.consecutiveFailureThreshold = max(1, consecutiveFailureThreshold)
    }

    func shouldNotify(consecutiveFailureCount: Int) -> Bool {
        guard isEnabled, consecutiveFailureCount > 0 else { return false }

        if notifyOnFirstFailure && consecutiveFailureCount == 1 {
            return true
        }

        let threshold = max(1, consecutiveFailureThreshold)
        return consecutiveFailureCount % threshold == 0
    }
}

/// Builds copy for single-repo and aggregated Focus-flush notifications.
enum FailureNotificationCopy {
    static func title(repoName: String) -> String {
        String(localized: "Sync Failed: \(repoName)")
    }

    static func body(message: String, consecutiveFailureCount: Int) -> String {
        if consecutiveFailureCount > 1 {
            return String(localized: "\(consecutiveFailureCount) consecutive failures — \(message)")
        }
        return message
    }

    static func aggregatedTitle(failureCount: Int) -> String {
        String(localized: "Sync Summary After Focus")
    }

    static func aggregatedBody(items: [(repoName: String, message: String, count: Int)]) -> String {
        guard !items.isEmpty else { return String(localized: "Some mirrors failed to sync.") }
        if items.count == 1, let only = items.first {
            return body(message: "\(only.repoName): \(only.message)", consecutiveFailureCount: only.count)
        }
        let preview = items.prefix(3).map(\.repoName).joined(separator: ", ")
        let suffix = items.count > 3 ? String(localized: " and others") : ""
        return String(localized: "\(items.count) mirrors failed to sync: \(preview)\(suffix)")
    }
}
