import Foundation

/// Builds user-facing copy for org/group new-repo discovery notifications.
enum OrgDiscoveryNotificationCopy {
    static func title(newRepoCount: Int, organizationName: String) -> String {
        if newRepoCount == 1 {
            return String(format: String.loc("New Repository in %@"), organizationName)
        }
        return String(
            format: String.loc("%lld New Repositories in %@"),
            newRepoCount,
            organizationName
        )
    }

    static func body(newRepoCount: Int, previewNames: [String]) -> String {
        guard !previewNames.isEmpty else {
            return String.loc("Tap to review and mirror the new repositories.")
        }
        let preview = previewNames.prefix(3).joined(separator: ", ")
        if newRepoCount > previewNames.count || newRepoCount > 3 {
            return String(
                format: String.loc("Not yet mirrored: %@, and others. Tap to review."),
                preview
            )
        }
        return String(format: String.loc("Not yet mirrored: %@. Tap to review."), preview)
    }
}
