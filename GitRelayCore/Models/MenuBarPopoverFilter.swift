import Foundation

enum MenuBarPopoverFilter {
    static func filteredRepos(
        _ repos: [RepoConfig],
        searchText: String
    ) -> [RepoConfig] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return repos }
        return repos.filter { repo in
            repo.name.lowercased().contains(query)
                || repo.tags.contains { $0.lowercased().contains(query) }
        }
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
