import Foundation

/// The quiet copy for the sheet that appears when the destination turns out to
/// hold a different history. Three plain sentences and three button titles: what
/// the destination has, what overwriting it would cost, and the way out.
nonisolated enum DestructivePushCopy {
    static var title: String {
        String(localized: "Target already has different history")
    }

    /// `https://gitlab.com/yangflow/keychord.git` reads back as
    /// `gitlab.com/yangflow/keychord`, which is what the sentences name.
    static func destinationLabel(targetURL: String?, fallback: String) -> String {
        guard let targetURL else { return fallback }
        let trimmed = targetURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard let path = GitRemoteRepoPath.parse(from: trimmed) else { return trimmed }
        guard let host = GitRemoteHost.host(from: trimmed), !host.isEmpty else {
            return path.pathWithNamespace
        }
        return "\(host)/\(path.pathWithNamespace)"
    }

    /// What the destination is holding that the source is not.
    static func divergence(destinationLabel label: String, plan: DestructivePushPlan) -> String {
        guard let count = plan.destinationOnlyCommits, count > 0 else {
            return String(localized: "\(label) already has commits that the source does not.")
        }
        return String(localized: "\(label) already has \(count) commits that the source does not.")
    }

    /// What Overwrite and Sync would cost.
    static var overwriteExplanation: String {
        String(localized: "Continuing replaces those commits with the source, and the branches already on the target are replaced.")
    }

    /// The way out, naming the namespace the check branches land in.
    static var checkBranchExplanation: String {
        String(localized: "You can push to check branches under \(CheckBranchRefMapping.displayPrefix) first and leave the target's own branches where they are.")
    }

    static var cancelTitle: String {
        String(localized: "Cancel")
    }

    static var overwriteTitle: String {
        String(localized: "Overwrite and Sync")
    }

    static var checkBranchTitle: String {
        String(localized: "Push to Check Branch")
    }
}
