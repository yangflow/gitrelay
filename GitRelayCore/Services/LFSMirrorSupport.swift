import Foundation

/// Pure helpers for Git LFS detection and sync planning (unit-testable without spawning git).
enum LFSAttributesDetector {
    /// Returns true when `.gitattributes` content declares the LFS filter.
    static func containsLFSFilter(_ content: String) -> Bool {
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if let commentIndex = line.firstIndex(of: "#") {
                line = String(line[..<commentIndex])
            }
            let tokens = line.split(whereSeparator: { $0.isWhitespace || $0 == "\t" })
                .map(String.init)
            guard tokens.count >= 2 else { continue }
            if tokens.dropFirst().contains(where: isLFSFilterAttribute) {
                return true
            }
        }
        return false
    }

    static func isGitAttributesPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == ".gitattributes" || trimmed.hasSuffix("/.gitattributes")
    }

    private static func isLFSFilterAttribute(_ token: String) -> Bool {
        token == "filter=lfs" || token.hasPrefix("filter=lfs=")
    }
}

enum LFSMirrorStep: Equatable, Sendable {
    case skip
    case warnMissingTool
    case fetchThenPush
}

enum LFSMirrorPlanner {
    /// Decide whether to run LFS fetch/push, warn, or skip.
    static func decide(
        mode: LFSMirrorMode,
        usesLFS: Bool,
        gitLFSAvailable: Bool
    ) -> LFSMirrorStep {
        switch mode {
        case .off:
            return .skip
        case .auto:
            guard usesLFS else { return .skip }
            return gitLFSAvailable ? .fetchThenPush : .warnMissingTool
        }
    }
}

enum LFSMirrorMessages {
    static var missingGitLFSWarning: String {
        String(localized: "Warning: This repository uses Git LFS, but git-lfs was not found. Install it (for example: brew install git-lfs), then sync again. Git objects were still mirrored successfully.")
    }

    static var skippedNoLFS: String {
        String(localized: "No Git LFS usage detected; skipping LFS sync.")
    }

    static var fetching: String {
        String(localized: "Fetching Git LFS objects...")
    }

    static var fetchComplete: String {
        String(localized: "LFS fetch complete.")
    }

    static var pushing: String {
        String(localized: "Pushing Git LFS objects...")
    }

    static var pushComplete: String {
        String(localized: "LFS push complete. ✓")
    }

    static var installHint: String {
        String(localized: "Install path tip: brew install git-lfs (or download from git-lfs.com), then sync again.")
    }

    static func isMissingGitLFSWarning(_ line: String) -> Bool {
        line == missingGitLFSWarning
    }
}

/// Candidate locations for the `git-lfs` binary (GUI apps often lack Homebrew on PATH).
enum GitLFSTool {
    static func candidatePaths(
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        [
            "/opt/homebrew/bin/git-lfs",
            "/usr/local/bin/git-lfs",
            "/usr/bin/git-lfs",
            "\(homeDirectory)/.local/bin/git-lfs"
        ]
    }

    static func isAvailable(
        fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        homeDirectory: String = NSHomeDirectory()
    ) -> Bool {
        candidatePaths(homeDirectory: homeDirectory).contains(where: fileExists)
    }

    /// Directories to prepend to PATH so `git lfs` can resolve `git-lfs`.
    static func pathDirectories(
        homeDirectory: String = NSHomeDirectory()
    ) -> [String] {
        Array(Set(candidatePaths(homeDirectory: homeDirectory).map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path
        }))
    }
}

/// Arguments for `git lfs` subcommands (invoked as `git lfs …` via GitRunner).
enum GitLFSArguments {
    static let versionArgs = ["lfs", "version"]
    static let lsFilesArgs = ["lfs", "ls-files"]
    static let fetchAllArgs = ["lfs", "fetch", "--all"]

    static func pushAllArgs(remoteURL: String) -> [String] {
        ["lfs", "push", "--all", remoteURL]
    }
}

/// Orchestrates LFS fetch (once) and push (per destination) for a sync run.
protocol LFSCommandRunning: Sendable {
    func isGitLFSAvailable() async throws -> Bool
    func repositoryUsesLFS(mirrorPath: String) async throws -> Bool
    func lfsFetchAll(
        mirrorPath: String,
        env: [String: String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws
    func lfsPushAll(
        mirrorPath: String,
        remoteURL: String,
        env: [String: String],
        onProgressLine: (@Sendable (String) -> Void)?
    ) async throws
}

struct LFSMirrorService: Sendable {
    enum PrepareResult: Equatable, Sendable {
        case skipped
        case warnedMissingTool
        case readyToPush
    }

    let runner: any LFSCommandRunning

    init(runner: any LFSCommandRunning) {
        self.runner = runner
    }

    /// After source fetch: detect LFS, optionally fetch objects. Missing git-lfs → warn, do not throw.
    func prepareAfterSourceFetch(
        mode: LFSMirrorMode,
        mirrorPath: String,
        env: [String: String],
        log: (String) -> Void,
        onProgressLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> PrepareResult {
        guard mode == .auto else { return .skipped }

        let usesLFS = try await runner.repositoryUsesLFS(mirrorPath: mirrorPath)
        let available = try await runner.isGitLFSAvailable()
        switch LFSMirrorPlanner.decide(mode: mode, usesLFS: usesLFS, gitLFSAvailable: available) {
        case .skip:
            return .skipped
        case .warnMissingTool:
            log(LFSMirrorMessages.missingGitLFSWarning)
            log(LFSMirrorMessages.installHint)
            return .warnedMissingTool
        case .fetchThenPush:
            log(LFSMirrorMessages.fetching)
            try await runner.lfsFetchAll(
                mirrorPath: mirrorPath,
                env: env,
                onProgressLine: onProgressLine
            )
            log(LFSMirrorMessages.fetchComplete)
            return .readyToPush
        }
    }

    /// Push LFS objects to one destination. Caller only invokes when prepare returned `.readyToPush`.
    func pushToDestination(
        mirrorPath: String,
        remoteURL: String,
        env: [String: String],
        log: (String) -> Void,
        onProgressLine: (@Sendable (String) -> Void)? = nil
    ) async throws {
        log(LFSMirrorMessages.pushing)
        try await runner.lfsPushAll(
            mirrorPath: mirrorPath,
            remoteURL: remoteURL,
            env: env,
            onProgressLine: onProgressLine
        )
        log(LFSMirrorMessages.pushComplete)
    }
}
