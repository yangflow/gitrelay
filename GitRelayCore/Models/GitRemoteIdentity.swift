import Foundation

/// Protocol-agnostic identity of one mirror endpoint. `git@host:ns/repo.git` and
/// `https://host/ns/repo` describe the same place, so both normalize to
/// `host/ns/repo`; archive targets and local sources normalize to a standardized
/// filesystem path.
nonisolated struct GitRemoteIdentity: Hashable, Sendable {
    let value: String

    private init(value: String) {
        self.value = value
    }

    /// Git remote identity, or nil when the string has no host + repo path.
    static func remote(_ remoteURL: String) -> GitRemoteIdentity? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let host = GitRemoteHost.host(from: trimmed),
              !host.isEmpty,
              let path = GitRemoteRepoPath.parse(from: trimmed),
              !path.name.isEmpty
        else { return nil }
        return GitRemoteIdentity(value: "\(host)/\(path.pathWithNamespace.lowercased())")
    }

    /// Filesystem identity for archive targets and local repositories.
    static func filesystemPath(_ rawPath: String) -> GitRemoteIdentity? {
        var trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://"), let fileURL = URL(string: trimmed) {
            trimmed = fileURL.path
        } else if trimmed.hasPrefix("~") {
            trimmed = NSString(string: trimmed).expandingTildeInPath
        }
        let standardized = URL(fileURLWithPath: trimmed).standardizedFileURL.path
        guard !standardized.isEmpty else { return nil }
        return GitRemoteIdentity(value: standardized)
    }

    /// Remote identity when the string looks like a remote, filesystem otherwise.
    static func any(_ location: String) -> GitRemoteIdentity? {
        remote(location) ?? filesystemPath(location)
    }
}

/// A source + target pair, compared the way a person would: same two places.
nonisolated struct MirrorPairIdentity: Hashable, Sendable {
    let source: GitRemoteIdentity
    let target: GitRemoteIdentity

    static func make(source: String, target: String) -> MirrorPairIdentity? {
        guard let source = GitRemoteIdentity.any(source),
              let target = GitRemoteIdentity.any(target)
        else { return nil }
        return MirrorPairIdentity(source: source, target: target)
    }
}

nonisolated enum MirrorPairDuplicates {
    /// Identity of every pair a saved repository already covers (one per target).
    static func identities(of repo: MirrorSnapshot) -> [MirrorPairIdentity] {
        guard let source = GitRemoteIdentity.any(repo.srcURL) else { return [] }
        return repo.targets.compactMap { target in
            guard let identity = GitRemoteIdentity.any(target.displayLabel) else { return nil }
            return MirrorPairIdentity(source: source, target: identity)
        }
    }

    /// The saved repository already mirroring `source` to `target`, if any.
    /// `excluding` keeps the repository being edited from matching itself.
    static func existingRepoID(
        source: String,
        target: String,
        in repos: [MirrorSnapshot],
        excluding excludedID: UUID? = nil
    ) -> UUID? {
        guard let pair = MirrorPairIdentity.make(source: source, target: target) else { return nil }
        return repos.first { repo in
            repo.id != excludedID && identities(of: repo).contains(pair)
        }?.id
    }
}
