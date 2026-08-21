import Foundation

/// Rewrites push refspecs so the source refs land in a namespace GitRelay owns.
/// The destination can then receive everything the source has without a single
/// branch it already had moving or disappearing.
nonisolated enum CheckBranchRefMapping {
    /// Every check ref sits one level below this: `refs/heads/gitrelay-check/main`.
    static let namespace = "gitrelay-check"

    /// What the sheet names, e.g. `gitrelay-check/`.
    static var displayPrefix: String { "\(namespace)/" }

    /// Maps the destination side of `src:dst` push refspecs into the namespace.
    /// The result is forced, because the only refs it can ever move are the ones
    /// GitRelay itself wrote under `namespace`.
    static func refSpecs(
        from pushRefSpecs: [String],
        namespace: String = CheckBranchRefMapping.namespace
    ) -> [String] {
        pushRefSpecs.compactMap { refSpec(from: $0, namespace: namespace) }
    }

    static func refSpec(
        from pushRefSpec: String,
        namespace: String = CheckBranchRefMapping.namespace
    ) -> String? {
        let trimmed = pushRefSpec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var body = trimmed
        if body.hasPrefix("+") {
            body.removeFirst()
        }

        guard let colonIndex = body.lastIndex(of: ":") else { return nil }
        let source = String(body[..<colonIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = String(body[body.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              let mapped = checkRef(for: destination, namespace: namespace) else { return nil }
        return "+\(source):\(mapped)"
    }

    /// `refs/heads/main` becomes `refs/heads/gitrelay-check/main`, `refs/tags/*`
    /// becomes `refs/tags/gitrelay-check/*`, and a bare `main` is read as a branch.
    /// A ref already inside the namespace is returned unchanged, so repeated runs
    /// never nest one namespace inside another.
    static func checkRef(
        for destinationRef: String,
        namespace: String = CheckBranchRefMapping.namespace
    ) -> String? {
        let trimmed = destinationRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !namespace.isEmpty else { return nil }

        let category: String
        let remainder: String
        if trimmed.hasPrefix("refs/") {
            let afterRefs = trimmed.dropFirst("refs/".count)
            guard let slashIndex = afterRefs.firstIndex(of: "/") else { return nil }
            category = "refs/\(afterRefs[..<slashIndex])/"
            remainder = String(afterRefs[afterRefs.index(after: slashIndex)...])
            guard category != "refs//", !remainder.isEmpty else { return nil }
        } else {
            category = "refs/heads/"
            remainder = trimmed
        }

        if remainder == namespace || remainder.hasPrefix("\(namespace)/") {
            return category + remainder
        }
        return "\(category)\(namespace)/\(remainder)"
    }
}
