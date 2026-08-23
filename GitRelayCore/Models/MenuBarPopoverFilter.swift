import Foundation

enum MenuBarPopoverFilter {
    /// Filters by search text, then pins failed / needs-credentials repos first.
    /// Relative order within each group matches the input (add-order) list.
    static func filteredRepos(
        _ repos: [MirrorSnapshot],
        searchText: String,
        statuses: [UUID: SyncStatus] = [:]
    ) -> [MirrorSnapshot] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched: [MirrorSnapshot]
        if query.isEmpty {
            matched = repos
        } else {
            matched = repos.filter { repo in
                repo.name.lowercased().contains(query)
                    || repo.tags.contains { $0.lowercased().contains(query) }
            }
        }
        return attentionFirst(matched, statuses: statuses)
    }

    /// Stable partition: attention repos first, then the rest in original order.
    static func attentionFirst(
        _ repos: [MirrorSnapshot],
        statuses: [UUID: SyncStatus]
    ) -> [MirrorSnapshot] {
        var attention: [MirrorSnapshot] = []
        var rest: [MirrorSnapshot] = []
        attention.reserveCapacity(repos.count)
        rest.reserveCapacity(repos.count)
        for repo in repos {
            if needsAttention(repo, status: statuses[repo.id] ?? .unknown) {
                attention.append(repo)
            } else {
                rest.append(repo)
            }
        }
        return attention + rest
    }

    /// Failed sync status or waiting for credentials — surfaces in the menu bar list.
    static func needsAttention(_ repo: MirrorSnapshot, status: SyncStatus) -> Bool {
        if repo.needsCredentials { return true }
        if case .failed = status { return true }
        return false
    }

    static func canTriggerSync(for status: SyncStatus) -> Bool {
        switch status {
        case .syncing, .queued:
            return false
        case .unknown, .idle, .ahead, .diverged, .failed:
            return true
        }
    }
}
