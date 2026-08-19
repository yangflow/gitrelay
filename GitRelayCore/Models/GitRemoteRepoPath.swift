import Foundation

/// Parsed owner/namespace and repository name from a Git remote URL.
nonisolated struct GitRemoteRepoPath: Equatable, Sendable {
    let namespace: String
    let name: String

    /// Full path used by GitLab-style APIs (`group/subgroup/repo`).
    var pathWithNamespace: String {
        namespace.isEmpty ? name : "\(namespace)/\(name)"
    }

    /// Two-segment path used by GitHub-style APIs (`owner/repo`).
    var ownerRepoPath: String { pathWithNamespace }

    static func parse(from remoteURL: String) -> GitRemoteRepoPath? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let repoPath: String?
        if trimmed.hasPrefix("git@") {
            repoPath = sshRepoPath(from: trimmed)
        } else if let components = URLComponents(string: trimmed),
                  let host = components.host,
                  !host.isEmpty {
            repoPath = httpsRepoPath(from: components)
        } else {
            repoPath = nil
        }

        guard let repoPath, !repoPath.isEmpty else { return nil }
        let segments = repoPath.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard let name = segments.last else { return nil }
        let namespace = segments.dropLast().joined(separator: "/")
        return GitRemoteRepoPath(namespace: namespace, name: name)
    }

    private static func sshRepoPath(from url: String) -> String? {
        let remainder = url.dropFirst("git@".count)
        guard let separator = remainder.firstIndex(where: { $0 == ":" || $0 == "/" }) else {
            return nil
        }
        var path = String(remainder[remainder.index(after: separator)...])
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }
        return path
    }

    private static func httpsRepoPath(from components: URLComponents) -> String? {
        var path = components.path
        if path.hasPrefix("/") { path.removeFirst() }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        if path.hasSuffix("/") { path = String(path.dropLast()) }
        return path.isEmpty ? nil : path
    }
}
