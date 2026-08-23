import Foundation

enum VerificationSampler {
    /// Randomly pick up to `count` mirror plans without replacement.
    static func sample(
        from mirrors: [MirrorPlan],
        count: Int,
        using generator: inout some RandomNumberGenerator
    ) -> [MirrorPlan] {
        guard count > 0, !mirrors.isEmpty else { return [] }
        let take = min(count, mirrors.count)
        return Array(mirrors.shuffled(using: &generator).prefix(take))
    }

    static func sample(from mirrors: [MirrorPlan], count: Int) -> [MirrorPlan] {
        var generator = SystemRandomNumberGenerator()
        return sample(from: mirrors, count: count, using: &generator)
    }
}
