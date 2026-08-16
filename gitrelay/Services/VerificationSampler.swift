import Foundation

enum VerificationSampler {
    /// Randomly pick up to `count` repos without replacement.
    static func sample(
        from repos: [RepoConfig],
        count: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [RepoConfig] {
        guard count > 0, !repos.isEmpty else { return [] }
        let take = min(count, repos.count)
        return Array(repos.shuffled(using: &generator).prefix(take))
    }

    static func sample(from repos: [RepoConfig], count: Int) -> [RepoConfig] {
        var generator = SystemRandomNumberGenerator()
        return sample(from: repos, count: count, using: &generator)
    }
}
