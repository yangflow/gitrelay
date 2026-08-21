import Foundation

/// Builds git CLI argument lists for mirror vs partial (depth / ref-filtered) sync.
enum GitSyncArguments {
    static let partialSyncLogLine =
        "Partial ref sync mode — syncing selected refs only; not a complete mirror backup."

    static func fetchArgs(
        depth: Int?,
        refSpecs: [String],
        remote: String = "origin",
        prune: Bool = true,
        progress: Bool = false
    ) -> [String] {
        var args = ["fetch"]
        if prune {
            args.append("--prune")
        }
        if progress {
            args.append("--progress")
        }
        if let depth, depth > 0 {
            args.append(contentsOf: ["--depth", String(depth)])
        }
        args.append(remote)
        args.append(contentsOf: refSpecs)
        return args
    }

    static func cloneMirrorArgs(srcURL: String, mirrorPath: String) -> [String] {
        ["clone", "--mirror", "--progress", srcURL, mirrorPath]
    }

    static func pushRefSpecs(from fetchRefSpecs: [String]) -> [String] {
        fetchRefSpecs.compactMap { spec in
            let trimmed = spec.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            var body = trimmed
            if body.hasPrefix("+") {
                body.removeFirst()
            }

            guard let colonIndex = body.lastIndex(of: ":") else { return nil }
            let destination = String(body[body.index(after: colonIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !destination.isEmpty else { return nil }
            return "\(destination):\(destination)"
        }
    }

    static func pushMirrorArgs(dstURL: String) -> [String] {
        ["push", "--mirror", "--progress", dstURL]
    }

    static func pushMirrorDryRunArgs(dstURL: String) -> [String] {
        ["push", "--mirror", "--dry-run", dstURL]
    }

    /// Commits reachable from the destination's branches but from no source
    /// branch. Reads `refs/dst/*`, so it only answers after `fetchDstRefs`.
    static let destinationOnlyCommitCountArgs = [
        "rev-list", "--count", "--glob=refs/dst/heads", "--not", "--glob=refs/heads"
    ]

    static func pushSelectiveArgs(dstURL: String, refSpecs: [String], dryRun: Bool = false) -> [String] {
        var args = ["push"]
        if dryRun {
            args.append("--dry-run")
        } else {
            args.append("--progress")
        }
        args.append(dstURL)
        args.append(contentsOf: refSpecs)
        return args
    }
}
