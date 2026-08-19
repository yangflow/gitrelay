import Foundation

enum RepoTagGrouping {
    struct Section: Identifiable, Equatable {
        /// Display title for the sidebar section.
        let title: String
        /// Tag name for batch operations; `nil` for the untagged bucket.
        let tag: String?
        let repos: [RepoConfig]

        var id: String { tag ?? "__untagged__" }
    }

    static func normalizeTag(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            guard let normalized = normalizeTag(tag) else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
    }

    static func allUniqueTags(from repos: [RepoConfig]) -> [String] {
        var seen = Set<String>()
        for repo in repos {
            for tag in repo.tags {
                if let normalized = normalizeTag(tag) {
                    seen.insert(normalized)
                }
            }
        }
        return seen.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static func sections(from repos: [RepoConfig]) -> [Section] {
        let tags = allUniqueTags(from: repos)
        var sections = tags.map { tag in
            Section(
                title: tag,
                tag: tag,
                repos: repos(withTag: tag, in: repos)
            )
        }

        let untagged = untaggedRepos(in: repos)
        if !untagged.isEmpty {
            sections.append(Section(title: String(localized: "Untagged"), tag: nil, repos: untagged))
        }
        return sections
    }

    static func repos(withTag tag: String, in repos: [RepoConfig]) -> [RepoConfig] {
        repos
            .filter { $0.tags.contains(tag) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func untaggedRepos(in repos: [RepoConfig]) -> [RepoConfig] {
        repos
            .filter { normalizedTags($0.tags).isEmpty }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func repos(matching tag: String?, in repos: [RepoConfig]) -> [RepoConfig] {
        if let tag {
            return repos(withTag: tag, in: repos)
        }
        return untaggedRepos(in: repos)
    }

    static func repoIDs(matching tag: String?, in repos: [RepoConfig]) -> [UUID] {
        repos(matching: tag, in: repos).map(\.id)
    }

    static func matchingSuggestions(
        prefix: String,
        existing: [String],
        selected: [String]
    ) -> [String] {
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrefix.isEmpty else { return [] }
        let selectedSet = Set(selected)
        return existing
            .filter { !selectedSet.contains($0) && $0.localizedStandardContains(normalizedPrefix) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
