import Foundation

/// Where 打开 sends a pair's endpoint: a web page for a Git remote, or the
/// enclosing folder for an archive directory or a local repository.
nonisolated enum RepoOpenLocation: Equatable, Sendable {
    case web(URL)
    case revealInFinder(URL)

    /// 打开 for a web page, Finder wording for a folder on this Mac.
    var actionTitle: String {
        switch self {
        case .web:
            return String.loc("Open")
        case .revealInFinder:
            return String.loc("Show in Finder")
        }
    }

    /// The pair's source: a remote page when the URL names a host, the folder
    /// when the source is a path on this Mac.
    static func source(of repo: RepoConfig) -> RepoOpenLocation? {
        make(gitLocation: repo.srcURL)
    }

    /// A mirror target: remote targets open in a browser, archive targets in Finder.
    static func target(_ target: MirrorTarget) -> RepoOpenLocation? {
        switch target.kind {
        case .gitRemote:
            return make(gitLocation: target.url)
        case .filesystem:
            return localDirectory(target.filesystemPath ?? target.url).map(RepoOpenLocation.revealInFinder)
        }
    }

    private static func make(gitLocation raw: String) -> RepoOpenLocation? {
        if let url = GitRemoteWebURL.url(forRemote: raw) {
            return .web(url)
        }
        if let directory = localDirectory(raw) {
            return .revealInFinder(directory)
        }
        return nil
    }

    /// Absolute path on this Mac, expanding `~` and unwrapping `file://`.
    /// Relative paths are refused: 打开 must not guess a working directory.
    static func localDirectory(_ raw: String) -> URL? {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }

        if path.hasPrefix("file://") {
            guard let fileURL = URL(string: path), fileURL.isFileURL else { return nil }
            path = fileURL.path
        } else if path.hasPrefix("~") {
            path = NSString(string: path).expandingTildeInPath
        }

        guard path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}

/// The browsable page behind a Git remote. `git@host:ns/repo.git`,
/// `ssh://git@host:2222/ns/repo`, and `https://host/ns/repo.git` all name the
/// same place, so all three become `https://host/ns/repo`.
///
/// An embedded credential never survives: only the host and the repository path
/// are carried over, so a URL holding a token cannot reach the browser.
nonisolated enum GitRemoteWebURL {
    static func url(forRemote remoteURL: String) -> URL? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let host = GitRemoteHost.host(from: trimmed),
              !host.isEmpty,
              let path = GitRemoteRepoPath.parse(from: trimmed),
              !path.name.isEmpty
        else { return nil }

        var components = URLComponents()
        components.scheme = isPlainHTTP(trimmed) ? "http" : "https"
        components.host = host
        // A web port only makes sense when the remote was already a web URL; an
        // SSH port (`ssh://host:2222`) says nothing about where the page lives.
        components.port = webPort(of: trimmed)
        components.path = "/" + path.pathWithNamespace
        return components.url
    }

    /// Keeps a self-hosted instance the user reaches over plain HTTP on HTTP.
    private static func isPlainHTTP(_ remoteURL: String) -> Bool {
        remoteURL.lowercased().hasPrefix("http://")
    }

    private static func webPort(of remoteURL: String) -> Int? {
        let lowered = remoteURL.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") else { return nil }
        return URLComponents(string: remoteURL)?.port
    }
}
