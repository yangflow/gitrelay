import Foundation

enum SidebarRepoFilter {
    enum StatusFilter: String, CaseIterable, Identifiable, Sendable {
        case all = "All"
        case failed = "Failed"
        case diverged = "Diverged"
        case notSynced = "Not Synced"

        var id: String { rawValue }
    }

    /// Display-only filtering over the sidebar repo list. Does not mutate configs.
    static func filteredRepos(
        _ repos: [RepoConfig],
        searchText: String,
        statusFilter: StatusFilter,
        statuses: [UUID: SyncStatus]
    ) -> [RepoConfig] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return repos.filter { repo in
            matchesSearch(repo, query: query)
                && matchesStatus(
                    repo,
                    filter: statusFilter,
                    status: statuses[repo.id] ?? .unknown
                )
        }
    }

    static func matchesSearch(_ repo: RepoConfig, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if repo.name.localizedCaseInsensitiveContains(query) { return true }
        if repo.srcURL.localizedCaseInsensitiveContains(query) { return true }
        if repo.targets.contains(where: { $0.url.localizedCaseInsensitiveContains(query) }) {
            return true
        }
        if repo.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) {
            return true
        }
        return false
    }

    static func matchesStatus(
        _ repo: RepoConfig,
        filter: StatusFilter,
        status: SyncStatus
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .failed:
            if case .failed = status { return true }
            return false
        case .diverged:
            if case .diverged = status { return true }
            return repo.isDiverged
        case .notSynced:
            return RepoRowHealthPresentation.caption(for: repo, status: status).kind == .neverSynced
        }
    }
}
