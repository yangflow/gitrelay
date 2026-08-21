import Foundation

/// Prefill values for the add-repository sheet from a dropped URL or local Git directory.
nonisolated struct RepoSourceDropPrefill: Equatable, Sendable {
    let srcURL: String
    let inferredName: String?
}

/// Parses dropped git remotes and local `.git` directories into add-sheet prefill.
nonisolated enum RepoSourceDropParser {
    /// Parses a dragged string: https / ssh / `github.com/org/repo` / local path.
    static func parse(_ raw: String, fileManager: FileManager = .default) -> RepoSourceDropPrefill? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let remote = normalizeRemoteURL(trimmed) {
            let name = GitRemoteRepoPath.parse(from: remote)?.name
            return RepoSourceDropPrefill(srcURL: remote, inferredName: name)
        }

        if let local = localGitSourcePath(from: trimmed, fileManager: fileManager) {
            return RepoSourceDropPrefill(
                srcURL: local,
                inferredName: inferredName(fromLocalPath: local)
            )
        }

        return nil
    }

    /// Parses a dropped file URL pointing at a working tree, bare repo, or `.git` directory.
    static func parse(fileURL: URL, fileManager: FileManager = .default) -> RepoSourceDropPrefill? {
        let resolved = fileURL.standardizedFileURL
        return parse(resolved.path, fileManager: fileManager)
    }

    /// Whether a source string is a usable local Git path (working tree, bare, or `.git`).
    static func isLocalGitPath(_ raw: String, fileManager: FileManager = .default) -> Bool {
        localGitSourcePath(from: raw, fileManager: fileManager) != nil
    }

    // MARK: - Private

    private static func normalizeRemoteURL(_ raw: String) -> String? {
        if raw.hasPrefix("git@") {
            return raw
        }

        if let url = URL(string: raw), let scheme = url.scheme?.lowercased() {
            if scheme == "https" || scheme == "http" || scheme == "ssh" {
                return raw
            }
            if scheme == "file" {
                return nil
            }
        }

        // Shorthand: github.com/org/repo[.git]
        if looksLikeHostRepoPath(raw) {
            var path = raw
            if path.hasSuffix("/") {
                path = String(path.dropLast())
            }
            if !path.hasSuffix(".git") {
                path += ".git"
            }
            return "https://\(path)"
        }

        return nil
    }

    private static func looksLikeHostRepoPath(_ raw: String) -> Bool {
        guard !raw.contains("://"), !raw.hasPrefix("/"), !raw.hasPrefix("~") else {
            return false
        }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return false }
        let host = parts[0]
        guard host.contains("."), !host.contains(" ") else { return false }
        let repoPath = parts.dropFirst().joined(separator: "/")
        return !repoPath.isEmpty && !repoPath.contains(" ")
    }

    private static func localGitSourcePath(from raw: String, fileManager: FileManager) -> String? {
        let path: String
        if raw.hasPrefix("file://"), let url = URL(string: raw) {
            path = url.standardizedFileURL.path
        } else if raw.hasPrefix("~") {
            path = NSString(string: raw).expandingTildeInPath
        } else {
            path = raw
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        let last = url.lastPathComponent

        if last == ".git" {
            return path
        }

        if last.hasSuffix(".git") {
            return path
        }

        let gitDir = url.appendingPathComponent(".git", isDirectory: false)
        var gitIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: gitDir.path, isDirectory: &gitIsDirectory) {
            // Working tree (directory) or gitfile (file) both count.
            return path
        }

        // Bare repository: has HEAD + objects
        let head = url.appendingPathComponent("HEAD", isDirectory: false)
        let objects = url.appendingPathComponent("objects", isDirectory: true)
        if fileManager.fileExists(atPath: head.path),
           fileManager.fileExists(atPath: objects.path, isDirectory: &gitIsDirectory),
           gitIsDirectory.boolValue {
            return path
        }

        return nil
    }

    private static func inferredName(fromLocalPath path: String) -> String? {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if url.lastPathComponent == ".git" {
            let parent = url.deletingLastPathComponent().lastPathComponent
            return parent.isEmpty ? nil : parent
        }
        var name = url.lastPathComponent
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        return name.isEmpty ? nil : name
    }
}
